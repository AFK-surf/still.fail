//! stillfail-core on the web. `start(emit)` builds the core over a [`WebHost`] and
//! returns an [`StillFailCore`] the worker (web/src/core/worker.ts) feeds with the
//! messages of its ports; everything the core says to a UI comes back through
//! `emit(clientId, message)`.

mod host;
mod idb;

use std::rc::Rc;

use stillfail_core::{ClientId, ClientMessage, Core, CoreError, CoreMessage, Host};
use stillfail_core::i18n::t;
use js_sys::{Function, Reflect};
use wasm_bindgen::prelude::*;

use crate::host::WebHost;

#[wasm_bindgen]
pub struct StillFailCore {
    core: Rc<Core>,
    host: Rc<WebHost>,
}

/// Starts the core (loads accounts, the device key, …). `emit` is called as
/// `emit(clientId: number, message: object)`; `test_channel`: the page is the test channel's (app.youdid.wtf), so what
/// the core says names the product youdid.wtf (stillfail_core::brand).
#[wasm_bindgen]
pub async fn start(emit: Function, test_channel: Option<bool>) -> Result<StillFailCore, JsValue> {
    console_error_panic_hook::set_once();
    let host = Rc::new(WebHost::new(emit, test_channel.unwrap_or(false)));
    let core = Core::new(host.clone() as Rc<dyn Host>).await;
    core.keep_time();
    Ok(StillFailCore { core: Rc::new(core), host })
}

// Client ids cross as plain numbers: a u64 would become a BigInt in JS.
#[wasm_bindgen]
impl StillFailCore {
    pub fn connect(&self) -> f64 {
        self.core.connect() as f64
    }

    pub fn disconnect(&self, client: f64) {
        self.core.disconnect(client as ClientId);
    }

    pub fn receive(&self, client: f64, message: JsValue) {
        let client = client as ClientId;
        match serde_wasm_bindgen::from_value::<ClientMessage>(message.clone()) {
            Ok(message) => self.core.receive(client, message),
            Err(error) => {
                // Answer only what can be answered: without an id nobody is waiting.
                let id = Reflect::get(&message, &JsValue::from_str("id")).ok().and_then(|id| id.as_f64());
                if let Some(id) = id.filter(|id| *id >= 0.0 && id.fract() == 0.0) {
                    let error = CoreError::new("bad_message", t!("core-misc.host.bad_message", error = error));
                    self.host.emit(client, CoreMessage::Error { id: id as u64, error });
                }
            }
        }
    }
}
