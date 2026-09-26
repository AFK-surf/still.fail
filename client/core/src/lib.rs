//! ember-core: the logic every ember client shares. See docs/client-core.md.
//!
//! Single-threaded and async: futures are `!Send`, shared state is
//! `Rc<RefCell<…>>`. The platform comes in through [`host::Host`].

pub mod accounts;
pub mod cloud;
pub mod core;
pub mod delta;
pub mod entries;
pub mod error;
pub mod host;
pub mod kept;
pub mod mesh;
pub mod protocol;
pub mod station;
pub mod store;
#[cfg(any(test, feature = "testing"))]
pub mod testing;
pub mod trace;
pub mod views;

pub use crate::core::Core;
pub use error::CoreError;
pub use host::Host;
pub use protocol::{ClientId, ClientMessage, CoreMessage, Topic};
