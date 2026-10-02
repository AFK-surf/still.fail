//! The still.fail station's own work, in Rust: what the station's Node part did, on the same data on disk (config.json, the
//! SQLite store) and with the same admin API. The station binary (../station) runs it in its own process
//! (docs/station-rust.md).

pub mod access;
pub mod adb;
mod archive;
pub mod admin;
pub mod agent_home;
pub mod chat;
pub mod config;
pub mod decision;
pub mod connections;
pub mod feedback;
pub mod former;
pub mod handoff;
pub mod host;
pub mod hub;
pub mod image_size;
pub mod instructions;
pub mod jobs;
pub mod lang;
pub mod live;
pub mod login;
mod claude_oauth;
mod local_links;
pub mod machine_logins;
pub mod machine_sessions;
pub mod mcp;
pub mod migrations;
pub mod no_keychain;
pub mod pool;
pub mod ports;
pub mod preview;
pub mod profiles;
pub mod quota;
pub mod runtime;
pub mod server;
pub mod session;
pub mod settings;
pub mod store;
pub mod telemetry;
pub mod thumbs;
pub mod transcript;
pub mod updates;
pub mod usage;
pub mod footprint;

pub mod remote;
