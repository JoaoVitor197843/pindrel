//! The id of this server: random, made once and then kept, so the others (and the clients that remember them) can tell
//! "Casa" from another machine that announces the same name. It is not a secret and not a credential: it only lets
//! a client notice that the server behind a name has changed.
use std::path::Path;

use crate::discovery::valid_id;

/// 128 random bits as 32 hex digits.
fn generate() -> String {
    let mut b = [0u8; 16];
    // the OS cannot refuse in practice; without randomness a fixed id would be worse than none
    getrandom::fill(&mut b).expect("the operating system has no random numbers");
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// The id kept in `file`, or a new one written there (in one piece, so a crash never leaves half an id). Without a
/// file the id lives as long as the process.
pub fn load_or_create(file: Option<&Path>) -> String {
    let Some(file) = file else { return generate() };
    if let Some(id) = std::fs::read_to_string(file)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| valid_id(s))
    {
        return id;
    }
    let id = generate();
    let tmp = file.with_extension("tmp");
    if let Err(e) = std::fs::write(&tmp, format!("{id}\n")).and_then(|_| std::fs::rename(&tmp, file)) {
        eprintln!("server id: could not save {}: {e} (it will change on restart)", file.display());
    }
    id
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A scratch directory that goes away with the test.
    struct Dir(std::path::PathBuf);

    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    impl std::ops::Deref for Dir {
        type Target = std::path::Path;
        fn deref(&self) -> &std::path::Path {
            &self.0
        }
    }

    fn dir(name: &str) -> Dir {
        let d = std::env::temp_dir().join(format!("pindrel-id-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        Dir(d)
    }

    #[test]
    fn ids_are_long_valid_and_different_every_time() {
        let (a, b) = (generate(), generate());
        assert_eq!(a.len(), 32);
        assert!(valid_id(&a) && valid_id(&b));
        assert_ne!(a, b);
    }

    #[test]
    fn without_a_file_every_start_is_a_new_server() {
        assert_ne!(load_or_create(None), load_or_create(None));
    }

    #[test]
    fn the_id_survives_restarts() {
        let d = dir("keep");
        let f = d.join("id");
        let first = load_or_create(Some(&f));
        assert_eq!(load_or_create(Some(&f)), first);
        assert_eq!(std::fs::read_to_string(&f).unwrap().trim(), first);
    }

    #[test]
    fn a_damaged_file_is_replaced_not_trusted() {
        let d = dir("bad");
        for junk in ["", "   \n", "not an id!", "../../etc", &"a".repeat(65), "ünï"] {
            let f = d.join("id");
            std::fs::write(&f, junk).unwrap();
            let id = load_or_create(Some(&f));
            assert!(valid_id(&id) && id.len() == 32, "{junk:?} gave {id:?}");
            assert_eq!(std::fs::read_to_string(&f).unwrap().trim(), id, "the new one is saved");
        }
    }

    #[test]
    fn a_place_that_cannot_be_written_still_gives_an_id() {
        let d = dir("nowhere");
        let id = load_or_create(Some(&d.join("missing").join("id")));
        assert!(valid_id(&id));
    }

    #[test]
    fn an_id_someone_else_wrote_is_kept_when_it_is_valid() {
        let d = dir("given");
        let f = d.join("id");
        std::fs::write(&f, "casa-2025-ABC\n").unwrap();
        assert_eq!(load_or_create(Some(&f)), "casa-2025-ABC");
    }
}
