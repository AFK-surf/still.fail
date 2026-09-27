//! ember station's own work, in Rust. It takes over what the station's Node part (src/*.ts) does, module by module, the
//! same data on disk (config.json, the SQLite store) and the same admin API; the station binary (../station) runs it
//! in place of the Node part once it does all of it (docs/station-rust.md).

pub mod config;
pub mod profiles;
