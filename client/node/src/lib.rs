//! ember-core in Node, for the desktop app's utility process (apps/desktop).
//! A thin layer over client/ffi: the same core thread, host and JSON
//! messages; only the listener differs, a JS function that the core thread
//! reaches through a threadsafe function, so it runs on Node's own thread.
//!
//!   const core = start(dataDir, cloudOrigin, (client, json) => …);
//!   const client = core.connect(); core.receive(client, json); core.disconnect(client);
//!
//! A panic ends the core as in client/ffi: every client gets `{"fatal": "…"}`,
//! and the host starts a new one.

use std::sync::Arc;

use ember_core_ffi::{CoreListener, EmberCoreFfi};
use napi::bindgen_prelude::{FnArgs, Function};
use napi::threadsafe_function::{ThreadsafeFunction, ThreadsafeFunctionCallMode};
use napi_derive::napi;

type Message = FnArgs<(u32, String)>;

/// The JS listener, callable from the core thread.
struct Listener(ThreadsafeFunction<Message, (), Message, napi::Status, false>);

impl CoreListener for Listener {
    fn on_message(&self, client: u64, json: String) {
        // Queued for Node's thread; the core thread never waits on JS.
        self.0.call((client as u32, json).into(), ThreadsafeFunctionCallMode::NonBlocking);
    }
}

#[napi]
pub struct EmberCore {
    inner: Arc<EmberCoreFfi>,
}

/// Starts a core (client/ffi's `start`): `data_dir` holds accounts and the device key;
/// `cloud_origin` is ember cloud; `listener(client, json)` gets what the core says to each client.
#[napi]
pub fn start(data_dir: String, cloud_origin: String, listener: Function<Message, ()>) -> napi::Result<EmberCore> {
    let listener = listener.build_threadsafe_function().callee_handled::<false>().build()?;
    let inner = ember_core_ffi::start(data_dir, cloud_origin, Box::new(Listener(listener)))
        .map_err(|error| napi::Error::from_reason(error.to_string()))?;
    Ok(EmberCore { inner })
}

#[napi]
impl EmberCore {
    /// A UI connected; its messages and emissions use the id returned.
    #[napi]
    pub fn connect(&self) -> u32 {
        self.inner.connect() as u32
    }

    /// One message from a UI as JSON.
    #[napi]
    pub fn receive(&self, client: u32, json: String) {
        self.inner.receive(client as u64, json);
    }

    /// The UI went away: its subscriptions end.
    #[napi]
    pub fn disconnect(&self, client: u32) {
        self.inner.disconnect(client as u64);
    }
}
