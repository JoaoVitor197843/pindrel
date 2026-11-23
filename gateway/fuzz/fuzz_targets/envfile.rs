//! A settings file is whatever somebody saved: parsing it must never panic.
#![no_main]
use libfuzzer_sys::fuzz_target;
use pindrel_gateway::envfile;

fuzz_target!(|data: &[u8]| {
    let text = String::from_utf8_lossy(data).into_owned();
    let _ = envfile::parse(&text);
    let _ = envfile::path_from(text.split_whitespace().map(String::from), |_| Some(text.clone()));
});
