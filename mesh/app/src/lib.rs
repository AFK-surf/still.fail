//! ember station's own work, in Rust. It takes over what the station's Node part (src/*.ts) does, module by module, the
//! same data on disk (config.json, the SQLite store) and the same admin API; the station binary (../station) runs it
//! in place of the Node part once it does all of it (docs/station-rust.md).

pub mod agent_home;
pub mod chat;
pub mod config;
pub mod connections;
pub mod host;
pub mod hub;
pub mod image_size;
pub mod instructions;
pub mod live;
pub mod machine_logins;
pub mod mcp;
pub mod pool;
pub mod ports;
pub mod profiles;
pub mod quota;
pub mod runtime;
pub mod session;
pub mod settings;
pub mod store;
pub mod telemetry;
pub mod transcript;
