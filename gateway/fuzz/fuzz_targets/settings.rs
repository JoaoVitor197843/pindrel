//! Everything the operator types in the environment, as the worst text: the parsers must report an error
//! and never panic.
#![no_main]
use libfuzzer_sys::fuzz_target;
use plany_gateway::{clientip, config::Config, pool::parse_targets};

fuzz_target!(|data: &[u8]| {
    let text = String::from_utf8_lossy(data).into_owned();
    let _ = parse_targets(&text);
    let _ = clientip::parse_trusted(&text);
    let _ = clientip::ClientIp::new(Vec::new(), &text);
    let _ = Config::from_lookup(|key| match key {
        "UPSTREAMS" => Some("127.0.0.1:9000".into()),
        _ => Some(text.clone()),
    });
});
