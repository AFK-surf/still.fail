//! stillfail-core: the logic every still.fail client shares. See docs/client-core.md.
//!
//! Single-threaded and async: futures are `!Send`, shared state is
//! `Rc<RefCell<…>>`. The platform comes in through [`host::Host`].

pub mod accounts;
pub mod activity;
pub mod asks;
pub mod attend;
pub mod changelog;
pub mod brand;
pub mod choose;
pub mod cloud;
pub mod data;
pub mod core;
pub mod delta;
pub mod doing;
pub mod entries;
pub mod error;
pub mod format;
pub mod history;
pub mod jobs;
pub mod host;
pub mod kept;
pub mod looks;
pub mod mesh;
pub mod notices;
pub mod ops;
pub mod pill;
pub mod prefs;
pub mod present;
pub mod protocol;
pub mod refs;
pub mod station;
pub mod status;
pub mod store;
pub mod sync;
#[cfg(any(test, feature = "testing"))]
pub mod testing;
pub mod trace;
pub mod views;
pub mod wake;
pub mod workspace;

pub use crate::core::Core;
pub use error::CoreError;
pub use host::Host;
pub use protocol::{ClientId, ClientMessage, CoreMessage, Topic};
