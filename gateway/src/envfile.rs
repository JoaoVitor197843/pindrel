//! A settings file (`KEY=VALUE` lines) for the gateway, for hosts where setting environment variables is awkward
//! (a Windows scheduled task, a double-clicked program). `--config <file>` or `GATEWAY_CONFIG` names it. The real
//! environment wins over the file, so a variable set by hand still overrides what the installer wrote.
use std::{collections::HashMap, fs, io::Read, path::Path};

/// A settings file is a few lines; anything bigger is not one.
const MAX_BYTES: u64 = 64 * 1024;

/// Reads the lines `KEY=VALUE`. Blank lines and lines starting with `#` are skipped, `export ` before a key and one pair of
/// matching quotes around a value are accepted, nothing is expanded, and a line that is not a setting is ignored: this never
/// fails on what it is given. The last line for a key wins.
pub fn parse(text: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for line in text.trim_start_matches('\u{feff}').lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let line = line.strip_prefix("export ").map(str::trim_start).unwrap_or(line);
        let Some((key, value)) = line.split_once('=') else { continue };
        let key = key.trim();
        let mut chars = key.chars();
        let valid =
            chars.next().is_some_and(|c| c.is_ascii_alphabetic() || c == '_') && chars.all(|c| c.is_ascii_alphanumeric() || c == '_');
        if !valid {
            continue;
        }
        out.insert(key.to_string(), unquote(value.trim()).to_string());
    }
    out
}

fn unquote(v: &str) -> &str {
    for q in ['"', '\''] {
        if v.len() >= 2 && v.starts_with(q) && v.ends_with(q) {
            return &v[1..v.len() - 1];
        }
    }
    v
}

/// Reads and parses a settings file; the error says what is wrong in words the operator can act on.
pub fn load(path: &Path) -> Result<HashMap<String, String>, String> {
    let file = fs::File::open(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    let mut raw = Vec::new();
    file.take(MAX_BYTES + 1)
        .read_to_end(&mut raw)
        .map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    if raw.len() as u64 > MAX_BYTES {
        return Err(format!(
            "{} is too big to be a settings file (over {} KiB)",
            path.display(),
            MAX_BYTES / 1024
        ));
    }
    Ok(parse(&String::from_utf8_lossy(&raw)))
}

/// Which file to read: `--config <file>` (or `--config=<file>`) first, then `GATEWAY_CONFIG`.
pub fn path_from(args: impl IntoIterator<Item = String>, env: impl Fn(&str) -> Option<String>) -> Option<String> {
    let mut args = args.into_iter();
    while let Some(a) = args.next() {
        if a == "--config" {
            return args.next().filter(|v| !v.is_empty());
        }
        if let Some(v) = a.strip_prefix("--config=") {
            return Some(v.to_string()).filter(|v| !v.is_empty());
        }
    }
    env("GATEWAY_CONFIG").map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_plain_pairs_comments_quotes_and_export() {
        let m =
            parse("# a comment\n\nUPSTREAMS=127.0.0.1:9000-9003\n  SERVER_NAME = \"Casa da Vó\"  \nexport MDNS_ENABLED='false'\nEMPTY=\n");
        assert_eq!(m["UPSTREAMS"], "127.0.0.1:9000-9003");
        assert_eq!(m["SERVER_NAME"], "Casa da Vó");
        assert_eq!(m["MDNS_ENABLED"], "false");
        assert_eq!(m["EMPTY"], "");
        assert_eq!(m.len(), 4);
    }

    #[test]
    fn windows_line_ends_and_a_byte_order_mark_are_fine() {
        let m = parse("\u{feff}UPSTREAMS=127.0.0.1:1\r\nGATEWAY_PORT=8200\r\n");
        assert_eq!(m["UPSTREAMS"], "127.0.0.1:1");
        assert_eq!(m["GATEWAY_PORT"], "8200");
    }

    #[test]
    fn what_is_not_a_setting_is_skipped_without_failing() {
        let m = parse("no equals sign\n=novalue\n1BAD=x\nBAD KEY=x\nBAD-KEY=x\nGOOD=1\n\"QUOTED\"=2\n");
        assert_eq!(m.len(), 1);
        assert_eq!(m["GOOD"], "1");
    }

    #[test]
    fn the_last_line_wins_and_quotes_must_match() {
        let m = parse("A=1\nA=2\nB=\"x\nC='y\"\nD=\"\"\nE=\"\n");
        assert_eq!(m["A"], "2");
        assert_eq!(m["B"], "\"x");
        assert_eq!(m["C"], "'y\"");
        assert_eq!(m["D"], "");
        assert_eq!(m["E"], "\"");
    }

    #[test]
    fn nothing_is_expanded() {
        let m = parse("A=$HOME\nB=%APPDATA%\\x\nC=`id`\n");
        assert_eq!(m["A"], "$HOME");
        assert_eq!(m["B"], "%APPDATA%\\x");
        assert_eq!(m["C"], "`id`");
    }

    #[test]
    fn a_value_keeps_an_equals_sign_and_a_hash() {
        let m = parse("TLS_SANS=a.lan,b.lan\nX=a=b#c\n");
        assert_eq!(m["X"], "a=b#c");
    }

    #[test]
    fn the_path_comes_from_the_flag_then_the_environment() {
        let none = |_: &str| None;
        let env = |k: &str| (k == "GATEWAY_CONFIG").then(|| " /etc/g.env ".to_string());
        let args = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(path_from(args(&["--config", "a.env"]), env).as_deref(), Some("a.env"));
        assert_eq!(path_from(args(&["--config=b.env"]), env).as_deref(), Some("b.env"));
        assert_eq!(path_from(args(&[]), env).as_deref(), Some("/etc/g.env"));
        assert_eq!(
            path_from(args(&["--config"]), env),
            None,
            "a flag without a file is not silently replaced"
        );
        assert_eq!(path_from(args(&["healthcheck"]), none), None);
    }

    #[test]
    fn a_missing_or_huge_file_is_an_error_not_a_panic() {
        let dir = std::env::temp_dir().join(format!("pindrel-envfile-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        assert!(load(&dir.join("nope.env")).unwrap_err().contains("cannot read"));
        let big = dir.join("big.env");
        fs::write(&big, vec![b'#'; (MAX_BYTES + 1) as usize]).unwrap();
        assert!(load(&big).unwrap_err().contains("too big"));
        let ok = dir.join("ok.env");
        fs::write(&ok, b"A=1\n\xff\xfeB=2\n").unwrap(); // invalid UTF-8 is replaced, not fatal
        assert_eq!(load(&ok).unwrap()["A"], "1");
        fs::remove_dir_all(&dir).ok();
    }
}
