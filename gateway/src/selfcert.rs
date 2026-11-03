//! A LAN needs no domain: the gateway keeps its own certificate authority and signs its server certificate with it.
//! Feature `selfcert`.
//!
//! Clients trust the CA (never the server certificate), identified by the SHA-256 of its certificate. That number is
//! what a pairing code carries: a phone that scanned it only talks to a server whose CA has that fingerprint, so the
//! server certificate can change (new address, yearly renewal) without asking anyone again.
use std::{
    fs, io,
    net::IpAddr,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use rcgen::{
    BasicConstraints, CertificateParams, DnType, ExtendedKeyUsagePurpose, GeneralSubtree, IsCa, Issuer, KeyPair, KeyUsagePurpose,
    NameConstraints, SanType, PKCS_ECDSA_P256_SHA256,
};
use rustls_pki_types::{pem::PemObject, CertificateDer};

const CA_YEARS: i64 = 10;
const LEAF_DAYS: i64 = 365;
/// A server certificate with less than this left is replaced.
const RENEW_BEFORE_SECS: u64 = 30 * 86_400;
const MAX_SANS: usize = 32;

#[derive(Debug, Clone)]
pub struct AutoSettings {
    pub dir: PathBuf,
    /// Extra names or addresses for the certificate (`TLS_SANS`), on top of the machine's own.
    pub extra_sans: Vec<String>,
}

/// What the TLS side needs: the chain and key of the server, the public CA and its fingerprint.
pub struct Issued {
    pub leaf_pem: String,
    pub leaf_key_pem: String,
    pub ca_pem: String,
    pub ca_fingerprint: String,
}

fn invalid(e: impl ToString) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, e.to_string())
}

pub fn fingerprint_of_pem(pem: &str) -> io::Result<String> {
    let der = CertificateDer::from_pem_slice(pem.as_bytes()).map_err(invalid)?;
    let digest = ring::digest::digest(&ring::digest::SHA256, &der);
    Ok(digest.as_ref().iter().map(|b| format!("{b:02x}")).collect())
}

/// Everything this machine is known by: it is what the certificate has to cover, and what decides a renewal.
pub fn wanted_names(extra: &[String]) -> Vec<String> {
    let mut names = vec!["localhost".to_string(), "127.0.0.1".into(), "::1".into()];
    let host = gethostname::gethostname().to_string_lossy().to_string();
    if !host.is_empty() && host.len() <= 63 && host.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.') {
        names.push(host);
    }
    if let Ok(ifaces) = if_addrs::get_if_addrs() {
        for i in ifaces {
            if let IpAddr::V4(ip) = i.ip() {
                if !ip.is_loopback() && (ip.is_private() || ip.is_link_local()) {
                    names.push(ip.to_string());
                }
            }
        }
    }
    names.extend(extra.iter().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()));
    names.sort();
    names.dedup();
    names.truncate(MAX_SANS);
    names
}

fn now_secs() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn write_private(path: &Path, data: &str) -> io::Result<()> {
    #[cfg(unix)]
    {
        use std::{io::Write, os::unix::fs::OpenOptionsExt};
        let tmp = path.with_extension("tmp");
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(&tmp)?;
        f.write_all(data.as_bytes())?;
        f.sync_all()?;
        fs::rename(tmp, path)
    }
    #[cfg(not(unix))]
    {
        fs::write(path, data)
    }
}

fn write_public(path: &Path, data: &str) -> io::Result<()> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, data)?;
    fs::rename(tmp, path)
}

/// The CA described the same way every time: a leaf is signed by name and key, so the CA certificate on disk (the one
/// clients trust) keeps validating leaves signed with these parameters and the stored key.
fn ca_params() -> io::Result<CertificateParams> {
    let mut params = CertificateParams::new(Vec::<String>::new()).map_err(invalid)?;
    params.distinguished_name.push(DnType::CommonName, "Pindrel local CA");
    params.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));
    params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
    let now = time::OffsetDateTime::now_utc();
    params.not_before = now - time::Duration::days(1);
    params.not_after = now + time::Duration::days(365 * CA_YEARS);
    Ok(params)
}

/// A CA that someone installs in a browser or a phone is trusted for every site there, so this one is limited by the
/// certificate itself (name constraints, honoured by browsers, rustls and BoringSSL): it can only vouch for
/// `localhost`, `.local`, `.lan`, `.home.arpa`, this machine's name and the names given when it was created. A stolen
/// `ca.key` cannot be used to impersonate a public site by name.
fn constrained(mut params: CertificateParams, names: &[String]) -> CertificateParams {
    // Only DNS names are constrained. Constraints on IP addresses would be right too, but BoringSSL (the TLS library
    // inside Dart and therefore Flutter) refuses a CA that has them ("unsupported name constraint type"), and a public
    // site is reached by name, not by address, so the names are what has to be fenced in.
    let permitted = permitted_dns(names).into_iter().map(GeneralSubtree::DnsName).collect();
    params.name_constraints = Some(NameConstraints {
        permitted_subtrees: permitted,
        excluded_subtrees: Vec::new(),
    });
    params
}

/// The DNS names a CA made with `names` can vouch for (anything below them).
fn permitted_dns(names: &[String]) -> Vec<String> {
    let mut dns: Vec<String> = ["localhost", "local", "lan", "home.arpa"].map(String::from).to_vec();
    dns.extend(names.iter().filter(|n| n.parse::<IpAddr>().is_err()).cloned());
    dns.sort();
    dns.dedup();
    dns
}

fn private_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => v.is_loopback() || v.is_private() || v.is_link_local(),
        IpAddr::V6(v) => v.is_loopback() || (v.segments()[0] & 0xffc0) == 0xfe80 || (v.segments()[0] & 0xfe00) == 0xfc00,
    }
}

/// Drops the names the CA cannot vouch for (a certificate with one of them would be refused as a whole by every client).
fn within_ca(names: Vec<String>, dir: &Path) -> Vec<String> {
    let allowed: Vec<String> = fs::read_to_string(dir.join("ca.names"))
        .map(|t| t.lines().map(String::from).collect())
        .unwrap_or_default();
    names
        .into_iter()
        .filter(|n| {
            let ok = match n.parse::<IpAddr>() {
                Ok(ip) => private_ip(ip),
                Err(_) => allowed.is_empty() || allowed.iter().any(|a| n == a || n.ends_with(&format!(".{a}"))),
            };
            if !ok {
                eprintln!(
                    "TLS: {n} is outside what this CA can vouch for (private addresses and the names it was made with); left out. Delete {} to make a new CA (devices pair again)",
                    dir.join("ca.pem").display()
                );
            }
            ok
        })
        .collect()
}

fn make_ca(names: &[String]) -> io::Result<(String, String)> {
    let key = KeyPair::generate_for(&PKCS_ECDSA_P256_SHA256).map_err(invalid)?;
    let cert = constrained(ca_params()?, names).self_signed(&key).map_err(invalid)?;
    Ok((cert.pem(), key.serialize_pem()))
}

fn make_leaf(ca_key_pem: &str, names: &[String]) -> io::Result<(String, String)> {
    let ca_key = KeyPair::from_pem(ca_key_pem).map_err(invalid)?;
    let issuer = Issuer::new(ca_params()?, ca_key);
    let leaf_key = KeyPair::generate_for(&PKCS_ECDSA_P256_SHA256).map_err(invalid)?;
    let mut params = CertificateParams::new(Vec::<String>::new()).map_err(invalid)?;
    params.distinguished_name.push(DnType::CommonName, "Pindrel");
    params.subject_alt_names = names
        .iter()
        .map(|n| match n.parse::<IpAddr>() {
            Ok(ip) => Ok(SanType::IpAddress(ip)),
            Err(_) => n.clone().try_into().map(SanType::DnsName).map_err(invalid),
        })
        .collect::<io::Result<_>>()?;
    params.key_usages = vec![KeyUsagePurpose::DigitalSignature];
    params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
    let now = time::OffsetDateTime::now_utc();
    params.not_before = now - time::Duration::days(1);
    params.not_after = now + time::Duration::days(LEAF_DAYS);
    let cert = params.signed_by(&leaf_key, &issuer).map_err(invalid)?;
    Ok((cert.pem(), leaf_key.serialize_pem()))
}

/// Returns the certificate to serve now, creating the CA on the first run and signing a new server certificate when
/// there is none, when it expires within 30 days, or when the machine's names (addresses) are no longer the ones it covers.
pub fn ensure(s: &AutoSettings) -> io::Result<Issued> {
    fs::create_dir_all(&s.dir)?;
    let (ca_path, ca_key_path) = (s.dir.join("ca.pem"), s.dir.join("ca.key"));
    let (leaf_path, leaf_key_path, meta_path) = (s.dir.join("server.pem"), s.dir.join("server.key"), s.dir.join("server.meta"));
    let names = wanted_names(&s.extra_sans);
    let (ca_pem, ca_key_pem) = match (fs::read_to_string(&ca_path), fs::read_to_string(&ca_key_path)) {
        // a file that no longer parses is as good as missing (a new CA means every paired device pairs again)
        (Ok(c), Ok(k)) if fingerprint_of_pem(&c).is_ok() && KeyPair::from_pem(&k).is_ok() => (c, k),
        _ => {
            // a half-written pair is never reused: both or nothing
            let (c, k) = make_ca(&names)?;
            write_private(&ca_key_path, &k)?;
            write_public(&ca_path, &c)?;
            write_public(&s.dir.join("ca.names"), &permitted_dns(&names).join("\n"))?;
            (c, k)
        }
    };
    let names = within_ca(names, &s.dir);
    let meta = fs::read_to_string(&meta_path).unwrap_or_default();
    let mut lines = meta.lines();
    let (saved_names, not_after) = (
        lines.next().unwrap_or(""),
        lines.next().and_then(|l| l.parse::<u64>().ok()).unwrap_or(0),
    );
    let current = saved_names == names.join(",") && not_after > now_secs() + RENEW_BEFORE_SECS;
    let existing = if current {
        fs::read_to_string(&leaf_path).ok().zip(fs::read_to_string(&leaf_key_path).ok())
    } else {
        None
    };
    let existing = existing.filter(|(c, k)| fingerprint_of_pem(c).is_ok() && KeyPair::from_pem(k).is_ok());
    let (leaf_pem, leaf_key_pem) = match existing {
        Some(pair) => pair,
        None => {
            let (c, k) = make_leaf(&ca_key_pem, &names)?;
            write_private(&leaf_key_path, &k)?;
            write_public(&leaf_path, &c)?;
            write_public(
                &meta_path,
                &format!("{}\n{}\n", names.join(","), now_secs() + LEAF_DAYS as u64 * 86_400),
            )?;
            (c, k)
        }
    };
    Ok(Issued {
        ca_fingerprint: fingerprint_of_pem(&ca_pem)?,
        leaf_pem,
        leaf_key_pem,
        ca_pem,
    })
}
