//! Plany gateway: the single front-facing process of a deployment (see CLAUDE.md).
pub mod config;
pub mod discovery;
pub mod handler;
pub mod limiter;
pub mod pool;
pub mod proto;
pub mod server;
