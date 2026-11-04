//! The certificate the TLS listeners present, replaceable while they run: a renewed certificate (by `lego`, `certbot`,
//! `acme.sh` or the gateway's own CA) takes effect for the next connection with no restart and no dropped connection.
use std::{
    io,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, RwLock},
    time::SystemTime,
};

use rustls::{
    server::{ClientHello, ResolvesServerCert},
    sign::CertifiedKey,
    ServerConfig,
};
use rustls_pki_types::{pem::PemObject, CertificateDer, PrivateKeyDer};

#[derive(Debug, Clone)]
pub enum Source {
    /// PEM files written by whoever manages the certificate; read again when either changes.
    Files { cert: PathBuf, key: PathBuf },
    /// The gateway's own CA (feature `selfcert`).
    #[cfg(feature = "selfcert")]
    Auto(crate::selfcert::AutoSettings),
}

pub struct Reloadable {
    current: RwLock<Arc<CertifiedKey>>,
    source: Source,
    stamp: Mutex<Option<(SystemTime, SystemTime)>>,
    /// Public CA certificate and its fingerprint, in `Auto` mode.
    ca: RwLock<Option<(String, String)>>,
}

impl std::fmt::Debug for Reloadable {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Reloadable").field("source", &self.source).finish()
    }
}

fn invalid(e: impl ToString) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, e.to_string())
}

fn certified(chain_pem: &[u8], key_pem: &[u8]) -> io::Result<Arc<CertifiedKey>> {
    let chain = CertificateDer::pem_slice_iter(chain_pem)
        .collect::<Result<Vec<_>, _>>()
        .map_err(invalid)?;
    if chain.is_empty() {
        return Err(invalid("no certificate in the file"));
    }
    let key = PrivateKeyDer::from_pem_slice(key_pem).map_err(invalid)?;
    let signing = rustls::crypto::ring::sign::any_supported_type(&key).map_err(invalid)?;
    Ok(Arc::new(CertifiedKey::new(chain, signing)))
}

fn mtimes(cert: &Path, key: &Path) -> Option<(SystemTime, SystemTime)> {
    Some((
        std::fs::metadata(cert).ok()?.modified().ok()?,
        std::fs::metadata(key).ok()?.modified().ok()?,
    ))
}

impl Reloadable {
    pub fn new(source: Source) -> io::Result<Arc<Self>> {
        let me = Self {
            current: RwLock::new(Arc::new(CertifiedKey::new(Vec::new(), Arc::new(Unused)))),
            source,
            stamp: Mutex::new(None),
            ca: RwLock::new(None),
        };
        me.load()?;
        Ok(Arc::new(me))
    }

    fn load(&self) -> io::Result<bool> {
        match &self.source {
            Source::Files { cert, key } => {
                let stamp = mtimes(cert, key);
                let fresh = certified(&std::fs::read(cert)?, &std::fs::read(key)?)?;
                *self.current.write().unwrap() = fresh;
                *self.stamp.lock().unwrap() = stamp;
                Ok(true)
            }
            #[cfg(feature = "selfcert")]
            Source::Auto(settings) => {
                let issued = crate::selfcert::ensure(settings)?;
                let fresh = certified(issued.leaf_pem.as_bytes(), issued.leaf_key_pem.as_bytes())?;
                let changed = self.current.read().unwrap().cert.first() != fresh.cert.first();
                *self.current.write().unwrap() = fresh;
                *self.ca.write().unwrap() = Some((issued.ca_pem, issued.ca_fingerprint));
                Ok(changed)
            }
        }
    }

    /// Looks again. A file that is half written or broken keeps the certificate in use (and says so): a renewal that
    /// goes wrong must not take the server down. Returns whether the certificate in use changed.
    pub fn refresh(&self) -> io::Result<bool> {
        #[allow(irrefutable_let_patterns)] // with the `selfcert` feature there is a second kind of source
        if let Source::Files { cert, key } = &self.source {
            if mtimes(cert, key) == *self.stamp.lock().unwrap() {
                return Ok(false);
            }
        }
        self.load()
    }

    pub fn ca(&self) -> Option<(String, String)> {
        self.ca.read().unwrap().clone()
    }

    pub fn serial_hint(&self) -> usize {
        self.current.read().unwrap().cert.first().map(|c| c.len()).unwrap_or(0)
    }
}

impl ResolvesServerCert for Reloadable {
    fn resolve(&self, _hello: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        Some(self.current.read().unwrap().clone())
    }
}

/// Placeholder signer until the first real load replaces it.
#[derive(Debug)]
struct Unused;
impl rustls::sign::SigningKey for Unused {
    fn choose_scheme(&self, _: &[rustls::SignatureScheme]) -> Option<Box<dyn rustls::sign::Signer>> {
        None
    }
    fn algorithm(&self) -> rustls::SignatureAlgorithm {
        rustls::SignatureAlgorithm::ECDSA
    }
}

pub fn server_config(resolver: Arc<Reloadable>, alpn: &[&[u8]]) -> io::Result<Arc<ServerConfig>> {
    let mut cfg = ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
        .with_safe_default_protocol_versions()
        .map_err(invalid)?
        .with_no_client_auth()
        .with_cert_resolver(resolver);
    cfg.alpn_protocols = alpn.iter().map(|p| p.to_vec()).collect();
    Ok(Arc::new(cfg))
}
