//! The protobuf the gateway reads back from `KNOWN_SERVERS_FILE`: a file on disk that anyone with access to
//! the directory can replace. It must never panic, and what it accepts must survive being written and read again.
#![no_main]
use libfuzzer_sys::fuzz_target;
use pindrel_gateway::proto::{discovered_servers, parse_discovered_servers};

fuzz_target!(|data: &[u8]| {
    if let Some(list) = parse_discovered_servers(data) {
        let again = parse_discovered_servers(&discovered_servers(&list)).expect("what we wrote can be read");
        assert_eq!(list, again);
    }
});
