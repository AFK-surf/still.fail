//! Named calls and their input validation; execution stays in the core.
use super::*;

#[derive(Debug, PartialEq)]
pub(crate) enum Call {
    ConnectFlow { topic: Topic, action: String, patch: Value },
    SlackTokens { topic: Topic, action: String, patch: Value },
    /// A client could not do something with what the core gave it (a view it cannot read, say): recorded as an error
    /// span, so it is seen with the rest of the trace, the same one at most once a minute.
    ClientError { source: String, message: String },
    /// A UI is back after `away` ms (a page hidden, a phone's app in the background): what went out before is
    /// suspect (wake.rs); `network`: the network changed, and all that is under way is. Its answer also tells the UI
    /// the core is alive.
    /// `retry` goes with `network` from a UI that asks to try again: a core from before `retry` takes it for the
    /// network changed, which also tries everything again.
    Wake { away: f64, network: bool, retry: bool },
    /// `device_name`: as the device is (`client.device`) when not given.
    AuthBegin { redirect_uri: String, return_to: String, device_name: Option<String> },
    AuthComplete { query: String },
    SignOut { account: String },
    /// Something to have done on a station or still.fail cloud, by its name (ops.rs): the UI never makes a request itself.
    Op(crate::ops::Request),
    ProfileModels { op: crate::ops::Request, id: String, models: Value },
    /// A chat into the archive or back (`chat.archive`, an `Op`): one going in is hidden from the lists meanwhile.
    ChatArchive { op: crate::ops::Request, thread: Option<u64>, session: String, archived: bool },
    /// `client`: the app it is sent from ("android 0.1.1123"), for the station to tell its agent; older UIs give none.
    ChatSend { station: String, thread: u64, text: String, attachments: Value, quotes: Value, client: Option<String> },
    /// A new chat on a station (`POST /sessions` with `ask`): answered at once with the key it goes by here; the
    /// station makes it meanwhile (views.rs, `Pending`).
    ChatCreate { station: String, ask: Value },
    /// Sending, trying again, dropping in a chat by its key: one asked for here goes to its thread once made.
    ChatSendTo { station: String, session: String, text: String, attachments: Value, quotes: Value, client: Option<String> },
    /// An options card answered with one of its options (decisions.rs): the viewer's message in its chat, the option's
    /// label quoting the post that asked, sent as `chat.send` sends one. Only while its chat's row says it is pending.
    DecisionAnswer { station: String, thread: u64, seq: u64, option: String },
    /// A card answered in writing (decisions.rs): what the viewer wrote, quoting the post that asked, sent as `chat.send`
    /// sends one. Only while its chat's row says it is pending; options and text cards accept it.
    DecisionReply { station: String, thread: u64, seq: u64, text: String, attachments: Value, quotes: Value },
    /// A decision set aside by the viewer (待定): last on the decisions page, still pending. Kept on the device; nothing
    /// is sent.
    DecisionDefer { station: String, thread: u64, seq: u64 },
    ChatRetryIn { station: String, session: String, id: String },
    ChatDiscardIn { station: String, session: String, id: String },
    ChatRetry { station: String, thread: u64, id: String },
    ChatDiscard { station: String, thread: u64, id: String },
    ChatOlder { station: String, thread: u64 },
    /// The page after a chat's window (it is short of its end), and the chat at its end.
    ChatNewer { station: String, thread: u64 },
    ChatLatest { station: String, thread: u64 },
    /// Where the reader leaves a chat: the entry at the top of what shows and how far below the list's top its top is
    /// (`offset`, the client's measure; optional), or none at its end (it opens there next).
    ChatPlace { station: String, thread: u64, seq: Option<u64>, offset: Option<f64> },
    HistoryOlder { station: String, key: String },
    /// The ways to a station measured now (its card's 重新测量: mesh.rs `Mesh::remeasure`).
    StationMeasure { station: String },
    StationUpdateNotice { station: String, action: String, version: Option<String> },
    ChatRead { station: String, thread: u64, seq: u64 },
    StationUpload { station: String, name: String, bytes: Vec<u8> },
    StationFile { station: String, key: String, name: String, thumb: bool, progress: bool },
    StationPreview { station: String, port: u16, method: String, path: String, headers: Vec<(String, String)>, body: Vec<u8>, stream: bool },
    /// `socket`: the name the UI gives it, for what it sends.
    PreviewSocket { station: String, port: u16, path: String, headers: Vec<(String, String)>, socket: String },
    /// A message (or the close) for the socket this client named `socket`.
    PreviewSocketSend { socket: String, frame: station::SocketFrame },
    Migrate { accounts: Option<Value>, device: Option<Vec<u8>> },
    /// still.fail cloud's VAPID key, for a browser to subscribe to pushes with (docs/notifications.md).
    PushKey,
    /// This device's push registration (`{kind: "web", endpoint, keys}` or `{kind: "fcm", token}`): given to every
    /// signed-in account, and to each signed in later.
    PushRegister { registration: Value },
    PushUnregister,
    /// What is written to a chat on this device, as it is now (`Topic::Draft`): nothing written forgets it.
    DraftPut { station: String, chat: String, draft: Value },
    /// Where a UI's attention is, notifications' settings, a notice taken to show (attend.rs).
    Attend(crate::attend::Call),
    /// What is written to a chat on this device, once (empty: nothing).
    DraftGet { station: String, chat: String },
    /// A chat picked to refer to from the composer (refs.rs): answers its mark, `{ mark }`, its link kept until sent.
    /// `base`: where the page's own links start (still.fail cloud when not given).
    ChatRef { station: String, id: String, title: String, base: Option<String> },
    /// Links of references kept by a client before the core kept them (title, link), the latest last.
    ChatRefsKeep { links: Vec<(String, String)> },
    /// What a chat runs on, chosen (choose.rs): `newChat.pick`, `newChat.create`, `newChat.migrate`, `pick.set`,
    /// `pick.save`.
    Choose { name: String, params: Value },
    /// How its person likes it on this device (`Topic::Prefs`, prefs.rs); `fill`: only what is not kept yet.
    PrefsSet { patch: Value, fill: bool },
    /// What the device is, as its host says once at start (prefs.rs).
    ClientDevice { facts: Value },
    /// The changelog shown, up to this build (changelog.rs).
    ChangelogSeen,
    /// A link's target, a newer app, a picture, the buddies, a dev sign-in (asks.rs).
    Ask(crate::asks::Ask),
    /// This phone's adb lent to a station's agents, or no longer; its pairing, its grant (adb.rs).
    Adb(crate::adb::Call),
}

impl Call {
    /// Whether a UI can cancel it (`{id, cancel}`), and one gone does: the calls that hold something open for a page.
    pub(super) fn cancellable(&self) -> bool {
        matches!(self, Call::StationPreview { stream: true, .. } | Call::PreviewSocket { .. })
    }

    /// The station a call is about, if any.
    pub(super) fn station(&self) -> Option<&str> {
        match self {
            Call::Op(op) | Call::ProfileModels { op, .. } | Call::ChatArchive { op, .. } => match &op.target {
                crate::ops::Target::Station(station) => Some(station),
                crate::ops::Target::Cloud(_) => None,
            },
            Call::ChatSend { station, .. } | Call::ChatRetry { station, .. } | Call::ChatDiscard { station, .. } => Some(station),
            Call::ChatCreate { station, .. } | Call::ChatSendTo { station, .. } | Call::ChatRetryIn { station, .. } | Call::ChatDiscardIn { station, .. } => Some(station),
            Call::DecisionAnswer { station, .. } | Call::DecisionReply { station, .. } | Call::DecisionDefer { station, .. } => Some(station),
            Call::ChatOlder { station, .. } | Call::ChatNewer { station, .. } | Call::ChatLatest { station, .. } | Call::ChatPlace { station, .. } | Call::ChatRead { station, .. } | Call::StationUpload { station, .. } | Call::StationFile { station, .. } => Some(station),
            Call::StationPreview { station, .. } | Call::HistoryOlder { station, .. } | Call::PreviewSocket { station, .. } | Call::StationMeasure { station } | Call::StationUpdateNotice { station, .. } => Some(station),
            Call::AuthBegin { .. } | Call::AuthComplete { .. } | Call::SignOut { .. } | Call::Migrate { .. } | Call::ClientError { .. } | Call::Wake { .. } | Call::PreviewSocketSend { .. } => None,
            Call::PushKey | Call::PushRegister { .. } | Call::PushUnregister => None,
            Call::DraftPut { station, .. } | Call::DraftGet { station, .. } | Call::ChatRef { station, .. } => Some(station),
            Call::Attend(_) | Call::ChatRefsKeep { .. } => None,
            Call::Choose { params, .. } => params.get("station").and_then(Value::as_str),
            Call::PrefsSet { .. } | Call::ClientDevice { .. } | Call::ChangelogSeen => None,
            Call::Ask(_) => None,
            Call::Adb(crate::adb::Call::Share(offer)) => Some(&offer.station),
            Call::Adb(_) => None,
            Call::ConnectFlow { topic, .. } => match topic { Topic::ConnectFlow { station, .. } => Some(station), _ => None },
            Call::SlackTokens { topic, .. } => match topic { Topic::SlackTokens { station, .. } => Some(station), _ => None },
        }
    }
}

pub(super) fn parse_call(name: &str, params: Value) -> Result<Call> {
    if let Some(action @ ("open" | "edit" | "go" | "config" | "make" | "verify" | "create" | "drop")) = name.strip_prefix("connect.flow.") {
        let form: stillfail_shapes::SlackTokenForm = serde_json::from_value(params.clone()).map_err(|e| CoreError::invalid(t!("core-misc.params.invalid", error = e)))?;
        StationAddr::parse(&form.station)?;
        if form.form.is_empty() { return Err(CoreError::invalid(t!("core-misc.params.missing_form"))); }
        return Ok(Call::ConnectFlow { topic: Topic::ConnectFlow { station: form.station, form: form.form }, action: action.into(), patch: params.get("input").cloned().unwrap_or(json!({})) });
    }
    if let Some(action @ ("edit" | "verify" | "drop")) = name.strip_prefix("slack.tokens.") {
        let form: stillfail_shapes::SlackTokenForm = serde_json::from_value(params.clone()).map_err(|e| CoreError::invalid(t!("core-misc.params.invalid", error = e)))?;
        StationAddr::parse(&form.station)?;
        if form.form.is_empty() { return Err(CoreError::invalid(t!("core-misc.params.missing_form"))); }
        let topic = Topic::SlackTokens { station: form.station, form: form.form };
        return Ok(Call::SlackTokens { topic, action: action.into(), patch: params.get("input").cloned().unwrap_or(json!({})) });
    }
    if let Some(call) = crate::attend::parse(name, &params) {
        return call.map(Call::Attend);
    }
    #[derive(Deserialize)]
    struct Begin {
        redirect_uri: String,
        return_to: String,
        #[serde(default)]
        device_name: Option<String>,
    }
    #[derive(Deserialize)]
    struct Complete {
        query: String,
    }
    #[derive(Deserialize)]
    struct SignOut {
        account: String,
    }
    #[derive(Deserialize)]
    struct ClientErrorParams {
        source: String,
        message: String,
    }
    #[derive(Deserialize)]
    struct Send {
        station: String,
        thread: u64,
        #[serde(default)]
        text: String,
        #[serde(default = "empty_list")]
        attachments: Value,
        #[serde(default = "empty_list")]
        quotes: Value,
        #[serde(default)]
        client: Option<String>,
    }
    fn empty_list() -> Value {
        json!([])
    }
    #[derive(Deserialize)]
    struct SendTo {
        station: String,
        session: String,
        #[serde(default)]
        text: String,
        #[serde(default = "empty_list")]
        attachments: Value,
        #[serde(default = "empty_list")]
        quotes: Value,
        #[serde(default)]
        client: Option<String>,
    }
    #[derive(Deserialize)]
    struct OutgoingIn {
        station: String,
        session: String,
        id: String,
    }
    #[derive(Deserialize)]
    struct Create {
        station: String,
        runtime: String,
        #[serde(default)]
        model: Option<String>,
        #[serde(default)]
        effort: Option<String>,
        #[serde(default)]
        profile: Option<String>,
    }
    #[derive(Deserialize)]
    struct Outgoing {
        station: String,
        thread: u64,
        id: String,
    }
    #[derive(Deserialize)]
    struct Chat {
        station: String,
        thread: u64,
    }
    #[derive(Deserialize)]
    struct Read {
        station: String,
        thread: u64,
        seq: u64,
    }
    #[derive(Deserialize)]
    struct Session {
        station: String,
        key: String,
    }
    #[derive(Deserialize)]
    struct Upload {
        station: String,
        name: String,
        bytes: String,
    }
    #[derive(Deserialize)]
    struct File {
        station: String,
        key: String,
        name: String,
        /// An image as a chat shows it: its thumbnail, where the station keeps one.
        #[serde(default)]
        thumb: bool,
        /// Tell the UI how far it has got as it comes (a big file).
        #[serde(default)]
        progress: bool,
    }
    #[derive(Deserialize)]
    struct Preview {
        station: String,
        port: u16,
        method: String,
        path: String,
        #[serde(default)]
        headers: Vec<(String, String)>,
        #[serde(default)]
        body: String,
        /// Hand the answer on as it comes (see `Inner::execute`).
        #[serde(default)]
        stream: bool,
    }
    #[derive(Deserialize)]
    struct Socket {
        station: String,
        port: u16,
        path: String,
        #[serde(default)]
        headers: Vec<(String, String)>,
        socket: String,
    }
    #[derive(Deserialize)]
    struct SocketSend {
        socket: String,
        text: Option<String>,
        binary: Option<String>,
        close: Option<(u16, String)>,
    }
    #[derive(Deserialize)]
    struct WakeParams {
        #[serde(default)]
        away: f64,
        #[serde(default)]
        network: bool,
        #[serde(default)]
        retry: bool,
    }
    #[derive(Deserialize)]
    struct Migrate {
        accounts: Option<Value>,
        device: Option<String>,
    }

    fn read<T: DeserializeOwned>(params: Value) -> Result<T> {
        serde_json::from_value(params_or_empty(params)).map_err(|e| CoreError::invalid(t!("core-misc.params.invalid", error = e)))
    }
    fn base64(text: &str, what: &str) -> Result<Vec<u8>> {
        BASE64.decode(text).map_err(|_| CoreError::invalid(t!(what)))
    }

    Ok(match name {
        "auth.begin" => {
            let p: Begin = read(params)?;
            Call::AuthBegin { redirect_uri: p.redirect_uri, return_to: p.return_to, device_name: p.device_name }
        }
        "auth.complete" => Call::AuthComplete { query: read::<Complete>(params)?.query },
        "auth.signOut" => Call::SignOut { account: read::<SignOut>(params)?.account },
        "client.error" => {
            let p = read::<ClientErrorParams>(params)?;
            Call::ClientError { source: p.source, message: p.message }
        }
        "client.wake" => {
            let params = read::<WakeParams>(params)?;
            Call::Wake { away: params.away, network: params.network, retry: params.retry }
        }
        "push.key" => Call::PushKey,
        "push.register" => {
            let registration = params_or_empty(params);
            let kind = registration.get("kind").and_then(Value::as_str);
            let text = |k: &str| registration.get(k).and_then(Value::as_str).is_some_and(|v| !v.is_empty());
            let keys = |k: &str| registration.get("keys").and_then(|keys| keys.get(k)).and_then(Value::as_str).is_some_and(|v| !v.is_empty());
            let ok = match kind {
                Some("web") => text("endpoint") && keys("p256dh") && keys("auth"),
                Some("fcm") => text("token"),
                _ => false,
            };
            if !ok {
                return Err(CoreError::invalid(t!("core-misc.params.push_registration")));
            }
            Call::PushRegister { registration }
        }
        "push.unregister" => Call::PushUnregister,
        "chat.create" => {
            let p: Create = read(params)?;
            let mut ask = json!({ "runtime": p.runtime });
            for (name, value) in [("model", p.model), ("effort", p.effort), ("profile", p.profile)] {
                if let Some(value) = value.filter(|v| !v.is_empty()) {
                    ask[name] = json!(value);
                }
            }
            Call::ChatCreate { station: p.station, ask }
        }
        // By its key (`session`) rather than its thread: a chat asked for here, made or not.
        "chat.send" if params.get("session").is_some() && params.get("thread").is_none() => {
            let p: SendTo = read(params)?;
            Call::ChatSendTo { station: p.station, session: p.session, text: p.text, attachments: p.attachments, quotes: p.quotes, client: p.client }
        }
        "chat.retry" if params.get("session").is_some() && params.get("thread").is_none() => {
            let p: OutgoingIn = read(params)?;
            Call::ChatRetryIn { station: p.station, session: p.session, id: p.id }
        }
        "chat.discard" if params.get("session").is_some() && params.get("thread").is_none() => {
            let p: OutgoingIn = read(params)?;
            Call::ChatDiscardIn { station: p.station, session: p.session, id: p.id }
        }
        "chat.send" => {
            let p: Send = read(params)?;
            Call::ChatSend { station: p.station, thread: p.thread, text: p.text, attachments: p.attachments, quotes: p.quotes, client: p.client }
        }
        "decision.answer" => {
            #[derive(Deserialize)]
            struct P { station: String, thread: u64, seq: u64, option: String }
            let p: P = read(params)?;
            if p.option.trim().is_empty() {
                return Err(CoreError::invalid(t!("core-misc.params.empty_option")));
            }
            Call::DecisionAnswer { station: p.station, thread: p.thread, seq: p.seq, option: p.option.trim().to_string() }
        }
        "decision.reply" => {
            #[derive(Deserialize)]
            struct P {
                station: String, thread: u64, seq: u64, text: String,
                #[serde(default)] attachments: Vec<Value>,
                #[serde(default)] quotes: Vec<Value>,
            }
            let p: P = read(params)?;
            if p.text.trim().is_empty() && p.attachments.is_empty() && p.quotes.is_empty() {
                return Err(CoreError::invalid(t!("core-misc.params.empty_reply")));
            }
            Call::DecisionReply { station: p.station, thread: p.thread, seq: p.seq, text: p.text.trim().to_string(), attachments: json!(p.attachments), quotes: json!(p.quotes) }
        }
        "station.updateNotice" => {
            #[derive(Deserialize)]
            struct P { station: String, action: String, #[serde(default)] version: Option<String> }
            let p: P = read(params)?;
            StationAddr::parse(&p.station)?;
            if !matches!(p.action.as_str(), "open" | "close" | "dismiss") || (p.action == "dismiss" && p.version.as_ref().is_none_or(|v| v.is_empty() || v.len() > 200)) {
                return Err(CoreError::invalid("参数不对：更新提示的操作或版本无效"));
            }
            Call::StationUpdateNotice { station: p.station, action: p.action, version: p.version }
        }
        "decision.defer" => {
            #[derive(Deserialize)]
            struct P { station: String, thread: u64, seq: u64 }
            let p: P = read(params)?;
            Call::DecisionDefer { station: p.station, thread: p.thread, seq: p.seq }
        }
        "chat.retry" => {
            let p: Outgoing = read(params)?;
            Call::ChatRetry { station: p.station, thread: p.thread, id: p.id }
        }
        "chat.discard" => {
            let p: Outgoing = read(params)?;
            Call::ChatDiscard { station: p.station, thread: p.thread, id: p.id }
        }
        "chat.older" => {
            let p: Chat = read(params)?;
            Call::ChatOlder { station: p.station, thread: p.thread }
        }
        "chat.newer" => {
            let p: Chat = read(params)?;
            Call::ChatNewer { station: p.station, thread: p.thread }
        }
        "chat.latest" => {
            let p: Chat = read(params)?;
            Call::ChatLatest { station: p.station, thread: p.thread }
        }
        "chat.place" => {
            #[derive(Deserialize)]
            struct P { station: String, thread: u64, #[serde(default)] seq: Option<u64>, #[serde(default)] offset: Option<f64> }
            let p: P = read(params)?;
            Call::ChatPlace { station: p.station, thread: p.thread, seq: p.seq, offset: p.offset }
        }
        "history.older" => {
            let p: Session = read(params)?;
            Call::HistoryOlder { station: p.station, key: p.key }
        }
        "station.measure" => {
            #[derive(Deserialize)]
            struct P { station: String }
            Call::StationMeasure { station: read::<P>(params)?.station }
        }
        "chat.read" => {
            let p: Read = read(params)?;
            Call::ChatRead { station: p.station, thread: p.thread, seq: p.seq }
        }
        "newChat.pick" | "newChat.create" | "newChat.migrate" | "pick.set" | "pick.save" => {
            let params = params_or_empty(params);
            let needs: &[&str] = match name {
                "newChat.pick" => &["scope"],
                "newChat.create" => &["station"],
                "pick.set" | "pick.save" => &["station", "of"],
                _ => &[],
            };
            if let Some(field) = needs.iter().find(|f| params.get(**f).and_then(Value::as_str).is_none_or(str::is_empty)) {
                return Err(CoreError::invalid(t!("core-misc.params.missing", field = field)));
            }
            Call::Choose { name: name.to_string(), params }
        }
        "draft.put" | "draft.get" => {
            let mut p = params_or_empty(params);
            // By the page's key for it (refs.rs, draft_at), or by its station and chat.
            let at = |field: &str| p.get(field).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
            let (Some(station), Some(chat)) = at("key").and_then(|k| crate::refs::draft_at(&k)).map_or((at("station"), at("chat")), |(s, c)| (Some(s), Some(c))) else {
                return Err(CoreError::invalid(t!("core-misc.params.key_or_chat")));
            };
            if name == "draft.get" {
                return Ok(Call::DraftGet { station, chat });
            }
            if let Some(o) = p.as_object_mut() {
                o.remove("station");
                o.remove("chat");
                o.remove("key");
            }
            let draft = stillfail_shapes::conform::<stillfail_shapes::DraftView>(p).map_err(|e| CoreError::invalid(t!("core-misc.params.invalid", error = e)))?;
            Call::DraftPut { station, chat, draft }
        }
        "chat.ref" => {
            #[derive(Deserialize)]
            struct Ref {
                station: String,
                id: String,
                title: String,
                base: Option<String>,
            }
            let p: Ref = read(params)?;
            Call::ChatRef { station: p.station, id: p.id, title: p.title, base: p.base }
        }
        "chat.refs" => {
            #[derive(Deserialize)]
            struct Links {
                links: Vec<(String, String)>,
            }
            Call::ChatRefsKeep { links: read::<Links>(params)?.links }
        }
        "prefs.set" => {
            let mut p = params_or_empty(params);
            let fill = p.as_object_mut().and_then(|o| o.remove("fill")).and_then(|v| v.as_bool()).unwrap_or(false);
            Call::PrefsSet { patch: p, fill }
        }
        "client.device" => Call::ClientDevice { facts: params_or_empty(params) },
        "changelog.seen" => Call::ChangelogSeen,
        "station.upload" => {
            let p: Upload = read(params)?;
            Call::StationUpload { bytes: base64(&p.bytes, "core-misc.call.base64.file")?, station: p.station, name: p.name }
        }
        "station.file" => {
            let p: File = read(params)?;
            Call::StationFile { station: p.station, key: p.key, name: p.name, thumb: p.thumb, progress: p.progress }
        }
        "station.preview" => {
            let p: Preview = read(params)?;
            Call::StationPreview { body: base64(&p.body, "core-misc.call.base64.body")?, station: p.station, port: p.port, method: p.method, path: p.path, headers: p.headers, stream: p.stream }
        }
        "preview.socket" => {
            let p: Socket = read(params)?;
            Call::PreviewSocket { station: p.station, port: p.port, path: p.path, headers: p.headers, socket: p.socket }
        }
        "preview.socket.send" => {
            let p: SocketSend = read(params)?;
            let frame = match (p.text, p.binary, p.close) {
                (Some(text), None, None) => station::SocketFrame::Text(text),
                (None, Some(bytes), None) => station::SocketFrame::Binary(base64(&bytes, "core-misc.call.base64.message")?),
                (None, None, Some((code, reason))) => station::SocketFrame::Close(code, reason),
                _ => return Err(CoreError::invalid(t!("core-misc.params.one_frame"))),
            };
            Call::PreviewSocketSend { socket: p.socket, frame }
        }
        "migrate" => {
            let p: Migrate = read(params)?;
            let device = match p.device {
                Some(text) => {
                    let key = base64(&text, "core-misc.call.base64.device_key")?;
                    if key.len() != 32 {
                        return Err(CoreError::invalid(t!("core-misc.params.device_key_size")));
                    }
                    Some(key)
                }
                None => None,
            };
            Call::Migrate { accounts: p.accounts.filter(|a| !a.is_null()), device }
        }
        "profile.put" if params.get("input").and_then(|v| v.get("models")).is_some() => {
            let op = crate::ops::request(name, &params).expect("an op")?;
            let models = params["input"]["models"].clone();
            if !models.as_array().is_some_and(|a| a.iter().all(Value::is_string)) {
                return Err(CoreError::invalid(t!("core-misc.params.bad_models")));
            }
            Call::ProfileModels { op, id: params["id"].as_str().unwrap_or_default().into(), models }
        }
        "chat.archive" => {
            let params = params_or_empty(params);
            let op = crate::ops::request(name, &params).expect("an op")?;
            let session = params.get("session").and_then(Value::as_str).unwrap_or("").to_string();
            Call::ChatArchive { op, thread: params.get("thread").and_then(Value::as_u64), session, archived: params.get("archived").and_then(Value::as_bool) == Some(true) }
        }
        _ => {
            let params = params_or_empty(params);
            if let Some(call) = crate::adb::parse(name, &params) {
                return Ok(Call::Adb(call?));
            }
            match (crate::asks::parse(name, &params), crate::ops::request(name, &params)) {
                (Some(ask), _) => Call::Ask(ask?),
                (None, Some(op)) => Call::Op(op?),
                (None, None) => return Err(CoreError::new("unknown_call", t!("core-misc.call.unknown", name = name))),
            }
        }
    })
}

/// Missing params read as `{}`, so the error names the missing field.
fn params_or_empty(params: Value) -> Value {
    if params.is_null() { json!({}) } else { params }
}
