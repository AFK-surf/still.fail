//! stillfail-core in a native app. `start(data_dir, cloud_origin, listener)`
//! starts the core on a thread of its own — a tokio current-thread runtime
//! with a `LocalSet`, since the core is `!Send` — and returns an
//! [`StillFailCoreFfi`] the app feeds with each UI's messages. Those calls only
//! post to the core thread, so they never block the caller; everything the
//! core says comes back on output threads through
//! `listener.on_message(client, json)`. Messages cross as JSON strings.
//!
//! If the core panics it is finished: every connected client gets
//! `{"fatal": "…"}` (as from the web worker) and the thread ends; the app
//! starts a new core.

mod host;

use std::collections::BTreeSet;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::{Arc, Mutex};

use stillfail_core::{ClientId, ClientMessage, Core, CoreError, CoreMessage, Host, PreparedMessage};
use stillfail_core::i18n::t;
use serde_json::{Value, json};
use tokio::sync::mpsc::{self, UnboundedReceiver, UnboundedSender};

use crate::host::{NativeHost, panic_message};

uniffi::setup_scaffolding!();

/// Receives what the core says to a client. Data and API output threads call this concurrently; hand messages on.
#[uniffi::export(callback_interface)]
pub trait CoreListener: Send + Sync {
    fn on_message(&self, client: u64, json: String);
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum StartError {
    #[error("{0}")]
    Io(String),
}

/// What the app's threads post to the core thread.
pub(crate) enum Command {
    Connect(ClientId),
    Receive(ClientId, PreparedMessage),
    Invalid(ClientId, CoreMessage),
    Disconnect(ClientId),
    /// A task on the core thread panicked.
    Fatal(String),
}

/// JSON from a UI is decoded on its own thread before it reaches the core's event loop.
/// All input commands share this queue so connect/receive/disconnect keep their order.
enum Input {
    Connect(ClientId),
    Receive(ClientId, String),
    Disconnect(ClientId),
}

fn decode_input(input: Input) -> Option<Command> {
    match input {
        Input::Connect(client) => Some(Command::Connect(client)),
        Input::Disconnect(client) => Some(Command::Disconnect(client)),
        Input::Receive(client, json) => match serde_json::from_str::<ClientMessage>(&json) {
            Ok(message) => Some(Command::Receive(client, Core::prepare(message))),
            Err(error) => {
                let id = serde_json::from_str::<Value>(&json).ok()?.get("id")?.as_u64()?;
                let error = CoreError::new("bad_message", t!("core-misc.host.bad_message", error = error));
                Some(Command::Invalid(client, CoreMessage::Error { id, error }))
            }
        },
    }
}

#[derive(uniffi::Object)]
pub struct StillFailCoreFfi {
    commands: std::sync::mpsc::Sender<Input>,
    /// Held while a connect is posted, so the ids given out reach the core in their order.
    next_client: Mutex<ClientId>,
}

/// Starts a core. `data_dir` is where it keeps accounts and the device key
/// (created if missing); `cloud_origin` is still.fail cloud, e.g. https://app.still.fail.
#[uniffi::export]
pub fn start(data_dir: String, cloud_origin: String, listener: Box<dyn CoreListener>) -> Result<Arc<StillFailCoreFfi>, StartError> {
    start_as(data_dir, cloud_origin, false, listener)
}

/// Starts a core as `start` does, of a beta app when `beta` (a build of its own beside the released one): its calls
/// to still.fail cloud say so, and its newer builds come from the beta feed.
#[uniffi::export]
pub fn start_as(data_dir: String, cloud_origin: String, beta: bool, listener: Box<dyn CoreListener>) -> Result<Arc<StillFailCoreFfi>, StartError> {
    let data_dir = PathBuf::from(data_dir);
    std::fs::create_dir_all(&data_dir).map_err(|e| StartError::Io(t!("core-misc.host.no_data_dir", dir = data_dir.display(), error = e)))?;
    let (commands, queue) = mpsc::unbounded_channel();
    let (input, inputs) = std::sync::mpsc::channel();
    let decoded = commands.clone();
    std::thread::Builder::new().name("stillfail-input".into()).spawn(move || {
        for input in inputs {
            let command = match std::panic::catch_unwind(AssertUnwindSafe(|| decode_input(input))) {
                Ok(command) => command,
                Err(panic) => { let _ = decoded.send(Command::Fatal(panic_message(&*panic))); break; }
            };
            if let Some(command) = command {
                if decoded.send(command).is_err() { break; }
            }
        }
    }).map_err(|e| StartError::Io(t!("core-misc.host.no_input_thread", error = e)))?;
    let listener: Arc<dyn CoreListener> = Arc::from(listener);
    let host_commands = commands.clone();
    std::thread::Builder::new()
        .name("stillfail-core".into())
        .spawn(move || run(data_dir, cloud_origin.trim_end_matches('/').to_string(), beta, listener, host_commands, queue))
        .map_err(|e| StartError::Io(t!("core-misc.host.no_core_thread", error = e)))?;
    Ok(Arc::new(StillFailCoreFfi { commands: input, next_client: Mutex::new(1) }))
}

#[uniffi::export]
impl StillFailCoreFfi {
    /// A UI connected; its messages and emissions use the id returned.
    pub fn connect(&self) -> u64 {
        let mut next = self.next_client.lock().unwrap_or_else(|e| e.into_inner());
        let client = *next;
        *next += 1;
        let _ = self.commands.send(Input::Connect(client));
        client
    }

    /// One message from a UI (`{ id, call, params }`, `{ id, subscribe }`, `{ id, unsubscribe }`) as JSON.
    pub fn receive(&self, client: u64, json: String) {
        let _ = self.commands.send(Input::Receive(client, json));
    }

    /// The UI went away: its subscriptions end.
    pub fn disconnect(&self, client: u64) {
        let _ = self.commands.send(Input::Disconnect(client));
    }
}

/// The viewer's time zone at `at_ms` as the core sees it (minutes to add to UTC); for checking the host against the platform.
#[uniffi::export]
pub fn utc_offset_min(at_ms: f64) -> i32 {
    host::utc_offset_min(at_ms)
}

/// The core thread: builds the core, then serves commands until the app lets go of it or the core panics.
fn run(data_dir: PathBuf, cloud_origin: String, beta: bool, listener: Arc<dyn CoreListener>, commands: UnboundedSender<Command>, queue: UnboundedReceiver<Command>) {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().expect("tokio runtime");
    let local = tokio::task::LocalSet::new();
    let host = Rc::new(NativeHost::new(data_dir, cloud_origin, beta, listener.clone(), commands));
    let mut clients = BTreeSet::new();
    let served = std::panic::catch_unwind(AssertUnwindSafe(|| local.block_on(&runtime, serve(host, queue, &mut clients))));
    let reason = match served {
        Ok(None) => return,
        Ok(Some(reason)) => reason,
        Err(panic) => panic_message(&*panic),
    };
    let fatal = json!({ "fatal": reason }).to_string();
    for client in clients {
        listener.on_message(client, fatal.clone());
    }
}

/// Returns why the core is finished, or `None` when the app dropped it.
async fn serve(host: Rc<NativeHost>, mut queue: UnboundedReceiver<Command>, clients: &mut BTreeSet<ClientId>) -> Option<String> {
    // Messages that arrive meanwhile wait in the queue, in order.
    let core = Core::new(host.clone() as Rc<dyn Host>).await;
    core.keep_time();
    while let Some(command) = queue.recv().await {
        match command {
            Command::Connect(client) => {
                let id = core.connect();
                // The app numbers clients itself (so connect() returns at once); both count from 1 in the same order.
                debug_assert_eq!(id, client);
                clients.insert(client);
            }
            Command::Receive(client, message) => {
                if let Some(id) = message.call_id() { host.call_started(client, id); }
                core.receive_prepared(client, message);
            }
            Command::Invalid(client, error) => host.emit(client, error),
            Command::Disconnect(client) => {
                clients.remove(&client);
                host.client_left(client);
                core.disconnect(client);
            }
            Command::Fatal(reason) => return Some(reason),
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[derive(Default)]
    struct Collect(Mutex<Vec<(u64, String)>>, std::sync::Condvar);

    impl CoreListener for Arc<Collect> {
        fn on_message(&self, client: u64, json: String) {
            self.0.lock().unwrap().push((client, json));
            self.1.notify_all();
        }
    }

    impl Collect {
        fn wait_for(&self, count: usize) -> Vec<(u64, Value)> {
            let mut seen = self.0.lock().unwrap();
            while seen.len() < count {
                let (next, timeout) = self.1.wait_timeout(seen, Duration::from_secs(10)).unwrap();
                assert!(!timeout.timed_out(), "only {} messages", next.len());
                seen = next;
            }
            seen.iter().map(|(c, j)| (*c, serde_json::from_str(j).unwrap())).collect()
        }
    }

    #[test]
    fn answers_calls_and_subscriptions_over_json_from_another_thread() {
        let dir = tempfile::tempdir().unwrap();
        let seen = Arc::new(Collect::default());
        let core = start(dir.path().to_string_lossy().into(), "http://127.0.0.1:9".into(), Box::new(seen.clone())).unwrap();
        let client = core.connect();
        assert_eq!(client, 1);
        core.receive(client, json!({"id": 1, "subscribe": {"topic": "accounts"}}).to_string());
        core.receive(client, json!({"id": 2, "call": "nope"}).to_string());
        core.receive(client, r#"{"id": 3, "what": true}"#.into());
        core.receive(client, "not json".into());
        let mut messages = seen.wait_for(3);
        messages.sort_by_key(|(_, m)| m["id"].as_u64());
        assert_eq!(messages[0], (1, json!({"id": 1, "value": []})));
        assert_eq!(messages[1].1["error"]["code"], "unknown_call");
        assert_eq!(messages[2].1["error"]["code"], "bad_message");
    }

    #[test]
    fn keeps_accounts_in_the_data_directory() {
        let dir = tempfile::tempdir().unwrap();
        let account = json!({"sub": "s1", "email": "a@b.c", "name": "A", "picture": "", "access": "x", "refresh": "y", "accessExpires": 4102444800u64});
        {
            let seen = Arc::new(Collect::default());
            let core = start(dir.path().to_string_lossy().into(), "http://127.0.0.1:9".into(), Box::new(seen.clone())).unwrap();
            let client = core.connect();
            core.receive(client, json!({"id": 1, "call": "migrate", "params": {"accounts": [account]}}).to_string());
            assert_eq!(seen.wait_for(1)[0].1, json!({"id": 1, "ok": null}));
        }
        let seen = Arc::new(Collect::default());
        let core = start(dir.path().to_string_lossy().into(), "http://127.0.0.1:9".into(), Box::new(seen.clone())).unwrap();
        let client = core.connect();
        core.receive(client, json!({"id": 1, "subscribe": {"topic": "accounts"}}).to_string());
        let value = &seen.wait_for(1)[0].1["value"];
        assert_eq!(value[0]["sub"], "s1");
        assert_eq!(value[0]["email"], "a@b.c");
    }

    #[test]
    fn knows_the_time_zone_across_dst() {
        // SAFETY: tests in this binary do not read TZ concurrently except through localtime_r after tzset.
        unsafe { std::env::set_var("TZ", "Europe/Berlin") };
        unsafe extern "C" {
            fn tzset();
        }
        unsafe { tzset() };
        assert_eq!(utc_offset_min(1_767_225_600_000.0), 60); // 2026-01-01
        assert_eq!(utc_offset_min(1_782_864_000_000.0), 120); // 2026-07-01
    }
}
