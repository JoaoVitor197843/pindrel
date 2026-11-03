//! Pindrel gateway: the single front-facing process of a deployment (see CLAUDE.md).
pub mod clientip;
pub mod config;
pub mod discovery;
#[cfg(feature = "http3")]
pub mod h3;
pub mod handler;
pub mod identity;
pub mod known;
pub mod limiter;
pub mod pool;
pub mod proto;
pub mod server;
#[cfg(feature = "tls")]
pub mod tls;
