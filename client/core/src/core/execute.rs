//! Execution of named client calls.
use super::*;

impl Inner {
    /// The card a chat waits on, as its row has it, if it is the one at `seq` (decisions.rs).
    fn pending_card(&self, station: &str, thread: u64, seq: u64) -> Result<Value> {
        let rows = self.store.value(&Topic::ChatRows { station: station.to_string() }).and_then(Result::ok).unwrap_or(Value::Null);
        let row = rows.as_array().into_iter().flatten().find(|r| r.get("thread").and_then(Value::as_u64) == Some(thread));
        row.and_then(crate::decisions::of_row).filter(|d| d.get("seq").and_then(Value::as_u64) == Some(seq))
            .ok_or_else(|| CoreError::invalid("这件事已经有人回复了"))
    }

    /// Runs a call; `at` is the client and id it came with.
    pub(super) async fn execute(&self, call: Call, progress: Progress, at: (ClientId, RequestId)) -> Result<Value> {
        let at_call = at;
        match call {
            Call::ConnectFlow { topic, action, patch } => {
                let Topic::ConnectFlow { station, form } = &topic else { unreachable!() };
                let token_topic = crate::connect_flow::tokens(station, form);
                match action.as_str() {
                    "open" => { self.connect_flow.open(&topic, at.0, &patch)?; self.slack_tokens.edit(&token_topic, at.0, &json!({}))?; }
                    "drop" => { self.connect_flow.drop(&topic, at.0); self.slack_tokens.drop(&token_topic, at.0); self.store.invalidate(&token_topic); return Ok(json!({})); }
                    "edit" => self.connect_flow.edit(&topic, at.0, &patch)?,
                    "go" => return self.connect_flow.go(&topic, at.0, patch["to"].as_str().unwrap_or("")),
                    _ => {
                        let view = self.connect_flow.value(&topic)?;
                        self.slack_tokens.edit(&token_topic, at.0, &json!({"install":view["made"]["state"]}))?;
                        let (input, verified) = self.slack_tokens.input(&token_topic, at.0)?;
                        let (generation, name, params) = self.connect_flow.begin(&topic, at.0, &action, &input, verified)?;
                        let revision = if action == "verify" {
                            match self.slack_tokens.begin(&token_topic, at.0) {
                                Ok((revision, _, _)) => Some(revision),
                                Err(e) => { self.connect_flow.finish(&topic, generation, &action, &Err(e.clone())); return Err(e); }
                            }
                        } else {None};
                        let answer = match crate::ops::request(name, &params).unwrap() {
                            Ok(op) => self.stations.perform(&StationAddr::parse(station)?, &op).await,
                            Err(e) => Err(e),
                        };
                        let current = if let Some(revision) = revision { let ok = self.slack_tokens.finish(&token_topic, revision, &answer); self.store.invalidate(&token_topic); ok } else {true};
                        let transition = if current {answer.clone()} else {Err(CoreError::invalid("token 已改变，请重新校验"))};
                        let alive = self.connect_flow.finish(&topic, generation, &action, &transition);
                        if !alive { return Err(CoreError::invalid("连接草稿已关闭")); }
                        return answer;
                    }
                }
                self.store.invalidate(&topic);
                self.connect_flow.value(&topic)
            }
            Call::SlackTokens { topic, action, patch } => {
                match action.as_str() {
                    "edit" => { self.slack_tokens.edit(&topic, at.0, &patch)?; }
                    "drop" => { self.slack_tokens.drop(&topic, at.0); }
                    _ => {
                        let (revision, mut input, verified) = self.slack_tokens.begin(&topic, at.0)?;
                        if verified { return Ok(json!(true)); }
                        let Topic::SlackTokens { station, .. } = &topic else { unreachable!() };
                        input["station"] = json!(station);
                        let op = crate::ops::request("slack.verify", &input).unwrap()?;
                        let answer = self.stations.perform(&StationAddr::parse(station)?, &op).await;
                        let verified = self.slack_tokens.finish(&topic, revision, &answer);
                        self.store.invalidate(&topic);
                        answer?;
                        return Ok(json!(verified));
                    }
                }
                self.store.invalidate(&topic);
                Ok(self.slack_tokens.value(&topic))
            }
            Call::AuthBegin { redirect_uri, return_to, device_name } => {
                // Named by the UI (those from before `client.device`), else as the device is.
                let device_name = device_name.or_else(|| crate::prefs::device_name(&self.data)).unwrap_or_else(|| crate::brand::name().into());
                let url = self.accounts.begin_sign_in(&redirect_uri, &return_to, &device_name).await?;
                Ok(json!({ "url": url }))
            }
            Call::AuthComplete { query } => {
                let (account, return_to) = self.accounts.complete_sign_in(&query).await?;
                Ok(json!({ "account": account, "return_to": return_to }))
            }
            Call::Wake { away, network, retry } => {
                let wake = Wake { at: self.host.now_ms(), away: away.max(0.0), network: network && !retry, retry };
                // What is asked again as the wake fails what was under way goes on new connections.
                if wake.suspects_connections() {
                    self.host.reset_connections();
                }
                self.wakes.wake(wake);
                Ok(json!({}))
            }
            Call::ClientError { source, message } => {
                let key = format!("{source}\u{0}{message}");
                let now = self.host.now_ms();
                let fresh = {
                    let mut reported = self.reported.borrow_mut();
                    let fresh = reported.get(&key).is_none_or(|at| now - at > 60_000.0);
                    if fresh {
                        reported.insert(key, now);
                    }
                    fresh
                };
                if fresh {
                    let mut span = self.tracer.always("client.error", Kind::Internal);
                    span.set("stillfail.source", source);
                    span.set("error.type", "client");
                    span.set("exception.message", message.chars().take(1000).collect::<String>());
                    span.fail();
                    span.end();
                }
                Ok(json!({}))
            }
            Call::SignOut { account } => {
                self.accounts.sign_out(&account).await?;
                Ok(Value::Null)
            }
            Call::PushKey => {
                let request = crate::host::HttpRequest { method: "GET".into(), url: format!("{}/v1/push/key", self.host.cloud_origin()), headers: Vec::new(), body: None };
                let response = self.host.fetch(request).await?;
                let data: Value = serde_json::from_slice(&response.body).unwrap_or_else(|_| json!({}));
                match data.get("vapid").and_then(Value::as_str) {
                    Some(key) if response.status == 200 => Ok(json!({ "vapid": key })),
                    _ => Err(CoreError::new("push_unavailable", format!("{} cloud 还不能推送", crate::brand::name()))),
                }
            }
            Call::PushRegister { registration } => {
                // Notifications off: this device has no pushes (attend.rs).
                if !self.attend.on() {
                    return Ok(Value::Null);
                }
                let kept = KeptPush { registration, with: Vec::new() };
                let _ = self.host.storage_set(PUSH_KEY, serde_json::to_vec(&kept).unwrap_or_default()).await;
                let done = self.push_registered().await;
                self.attend.set_pushing(done.is_ok());
                done
            }
            Call::PushUnregister => {
                self.attend.set_pushing(false);
                let kept = self.host.storage_get(PUSH_KEY).await.ok().flatten().and_then(|b| serde_json::from_slice::<KeptPush>(&b).ok());
                let _ = self.host.storage_delete(PUSH_KEY).await;
                if let Some(kept) = kept {
                    let mut gone = json!({});
                    for k in ["endpoint", "token"] {
                        if let Some(v) = kept.registration.get(k) {
                            gone[k] = v.clone();
                        }
                    }
                    for account in self.accounts.list() {
                        let _ = self.cloud.request(&account.sub, "DELETE", "/v1/push", Some(gone.clone())).await;
                    }
                }
                Ok(Value::Null)
            }
            Call::ProfileModels { op, id, models } => {
                let station = match &op.target {
                    crate::ops::Target::Station(station) => station.clone(),
                    _ => return Err(CoreError::invalid("缺少 station")),
                };
                if !self.data.begin_models(&station, &id, models) {
                    return Err(CoreError::invalid("模型正在保存"));
                }
                let result = Box::pin(self.execute(Call::Op(op), progress, at)).await;
                // after_write has already installed the confirmed overview. Clear in core, not in a UI
                // callback that may run before its coalesced topic update arrives. Failure reveals real data.
                self.data.end_models(&station, &id);
                result
            }
            Call::Op(op) => match &op.target {
                crate::ops::Target::Cloud(account) => {
                    let made = op.method == "POST" && op.path == "/v1/workspaces";
                    let result = self.cloud.request(&account, op.method, &op.path, op.body).await?;
                    // A workspace made: the invite code kept through signing in is done with.
                    if made {
                        crate::prefs::invite_used(&self.data);
                    }
                    // A write may rename, join or leave a workspace: what the account topics show changed too.
                    if op.method != "GET" {
                        self.refresh_all().await;
                    }
                    Ok(result)
                }
                crate::ops::Target::Station(station) => {
                    let addr = StationAddr::parse(&station)?;
                    let path = op.path.clone();
                    let machine = op.method == "GET" && op.path.starts_with("/machine-sessions");
                    let mut result = self.stations.perform(&addr, &op).await;
                    // The machine's own sessions, each in a line (choose.rs).
                    if let (true, Ok(answer)) = (machine, result.as_mut()) {
                        let now = self.host.now_ms();
                        answer.get_mut("sessions").and_then(Value::as_array_mut).into_iter().flatten().for_each(|s| crate::choose::machine_meta(s, now));
                        if let Some(s) = answer.get_mut("session") {
                            crate::choose::machine_meta(s, now);
                        }
                    }
                    // What the clients show of it, put in here (looks.rs).
                    result.map(|mut value| {
                        crate::looks::answer(op.method, &path, &mut value);
                        value
                    })
                }
            },
            // Out of the chat lists at once while its station archives it; back if it could not.
            Call::ChatArchive { op, thread, session, archived } => {
                let station = match &op.target {
                    crate::ops::Target::Station(station) => station.clone(),
                    crate::ops::Target::Cloud(_) => return Err(CoreError::invalid("参数不对：要有 station")),
                };
                if archived {
                    self.views.archiving(&station, thread, &session, true);
                }
                let result = Box::pin(self.execute(Call::Op(op), progress, at)).await;
                if archived {
                    self.views.archiving(&station, thread, &session, false);
                }
                result
            }
            Call::ChatSend { station, thread, text, attachments, quotes, client } => {
                let message = outgoing(crate::refs::expand(&self.data, &station, &text), attachments, quotes, client.or_else(|| crate::prefs::sent_from(&self.data)));
                let id = self.views.outbox_add(&station, thread, message.clone());
                self.deliver(&station, thread, &id, message).await
            }
            Call::ChatCreate { station, ask } => {
                StationAddr::parse(&station)?;
                let key = self.views.pending_new(&station, ask);
                self.make_chat(&key);
                Ok(json!({ "key": key }))
            }
            Call::ChatSendTo { station, session, text, attachments, quotes, client } => {
                let message = outgoing(crate::refs::expand(&self.data, &station, &text), attachments, quotes, client.or_else(|| crate::prefs::sent_from(&self.data)));
                match self.views.pending_thread(&station, &session) {
                    Some(Some(thread)) => {
                        let id = self.views.outbox_add(&station, thread, message.clone());
                        self.deliver(&station, thread, &id, message).await
                    }
                    // It waits for the chat; one that could not be made is tried again with it.
                    Some(None) => {
                        let failed = self.views.pending_failed_now(&session);
                        let id = self.views.pending_queue(&session, message).ok_or_else(|| CoreError::invalid("没有这个对话"))?;
                        if failed {
                            self.make_chat(&session);
                        }
                        Ok(json!({ "id": id }))
                    }
                    None => Err(CoreError::invalid("没有这个对话")),
                }
            }
            Call::DecisionAnswer { station, thread, seq, option } => {
                // As its chat's row has it: still pending, an options card, and the option one it offers.
                let card = self.pending_card(&station, thread, seq)?;
                let (text, quotes) = crate::decisions::answer(&card, &option).ok_or_else(|| CoreError::invalid("没有这个选项"))?;
                crate::prefs::undefer_decision(&self.data, &crate::decisions::deferral_key(&station, thread, seq));
                let send = Call::ChatSend { station, thread, text, attachments: json!([]), quotes, client: None };
                Box::pin(self.execute(send, progress, at)).await
            }
            Call::DecisionReply { station, thread, seq, text, attachments, quotes: added } => {
                // As its chat's row has it: still pending, and a supported card.
                let card = self.pending_card(&station, thread, seq)?;
                let extras = attachments.as_array().is_some_and(|a| !a.is_empty()) || added.as_array().is_some_and(|a| !a.is_empty());
                let (text, mut quotes) = crate::decisions::reply(&card, &text, extras).ok_or_else(|| CoreError::invalid("请在 chat 里回复这张卡片"))?;
                if let (Some(quotes), Some(added)) = (quotes.as_array_mut(), added.as_array()) {
                    quotes.extend(added.iter().cloned());
                }
                crate::prefs::undefer_decision(&self.data, &crate::decisions::deferral_key(&station, thread, seq));
                let send = Call::ChatSend { station, thread, text, attachments, quotes, client: None };
                Box::pin(self.execute(send, progress, at)).await
            }
            Call::DecisionDefer { station, thread, seq } => {
                // The prefs changed: the decisions page is put together again. Nothing is sent.
                crate::prefs::defer_decision(&self.data, &crate::decisions::deferral_key(&station, thread, seq), self.host.now_ms());
                Ok(Value::Null)
            }
            Call::ChatRetryIn { station, session, id } => match self.views.pending_thread(&station, &session) {
                Some(Some(thread)) => Box::pin(self.execute(Call::ChatRetry { station, thread, id }, progress, at)).await,
                Some(None) => {
                    self.make_chat(&session);
                    Ok(Value::Null)
                }
                None => Err(CoreError::invalid("没有这个对话")),
            },
            Call::ChatDiscardIn { station, session, id } => {
                match self.views.pending_thread(&station, &session) {
                    Some(Some(thread)) => self.views.outbox_remove(&station, thread, &id),
                    Some(None) => {
                        self.views.pending_discard(&session, &id);
                    }
                    None => return Err(CoreError::invalid("没有这个对话")),
                }
                Ok(Value::Null)
            }
            Call::ChatRetry { station, thread, id } => {
                let entry = self.views.outbox_get(&station, thread, &id).ok_or_else(|| CoreError::invalid("没有这条待发的消息"))?;
                self.views.outbox_state(&station, thread, &id, None);
                self.deliver(&station, thread, &id, crate::views::sent_as(&entry)).await
            }
            Call::ChatDiscard { station, thread, id } => {
                self.views.outbox_remove(&station, thread, &id);
                Ok(Value::Null)
            }
            Call::ChatOlder { station, thread } => Ok(json!({ "more": self.stations.older(&StationAddr::parse(&station)?, thread).await? })),
            Call::ChatNewer { station, thread } => Ok(json!({ "more": self.stations.newer(&StationAddr::parse(&station)?, thread).await? })),
            Call::ChatLatest { station, thread } => {
                self.stations.latest(&StationAddr::parse(&station)?, thread).await?;
                Ok(Value::Null)
            }
            Call::ChatPlace { station, thread, seq, offset } => {
                self.stations.place(&station, thread, seq, offset);
                Ok(Value::Null)
            }
            Call::HistoryOlder { station, key } => Ok(json!({ "more": self.stations.history_older(&StationAddr::parse(&station)?, &key).await? })),
            Call::StationMeasure { station } => {
                self.stations.measure(&StationAddr::parse(&station)?).await?;
                Ok(Value::Null)
            }
            Call::ChatRead { station, thread, seq } => {
                self.stations.read(&StationAddr::parse(&station)?, thread, seq).await?;
                Ok(Value::Null)
            }
            Call::Attend(call) => match call {
                crate::attend::Call::Focus(focus) => {
                    // Kept as the chat to come back to in its workspace (views/marks.rs).
                    if let Some((station, key)) = focus.opened() {
                        crate::prefs::chat_opened(&self.data, station, key);
                    }
                    self.attend.focus(at.0, focus);
                    self.attended();
                    // Another workspace now: what a page is to show is the new one's.
                    self.store.invalidate_all(|t| matches!(t, Topic::Notify { .. }));
                    Ok(Value::Null)
                }
                crate::attend::Call::Set { on, asked } => {
                    self.attend.set(on, asked).await;
                    self.store.invalidate_all(|t| matches!(t, Topic::Notify { .. }));
                    // Off: this device's pushes go too.
                    if on == Some(false) {
                        Box::pin(self.execute(Call::PushUnregister, progress, at)).await?;
                    }
                    Ok(self.attend.value(None))
                }
                crate::attend::Call::Claim { id } => {
                    let show = self.attend.claim(&id);
                    if show {
                        self.store.invalidate_all(|t| matches!(t, Topic::Notify { .. }));
                    }
                    Ok(json!({ "show": show }))
                }
                crate::attend::Call::Pushed { workspace } => Ok(json!({ "show": self.attend.pushed(workspace.as_deref()) })),
            },
            Call::Choose { name, params } => {
                let at = |field: &str| params.get(field).and_then(Value::as_str).unwrap_or("").to_string();
                match name.as_str() {
                    "newChat.pick" => self.choose.pick_new(&at("scope"), &params).map(|_| Value::Null),
                    "newChat.migrate" => {
                        self.choose.migrate(&params);
                        Ok(Value::Null)
                    }
                    // Made as `chat.create` makes it, with what is picked there.
                    "newChat.create" => {
                        let ask = self.choose.create(&at("station"))?;
                        let made = Box::pin(self.execute(Call::ChatCreate { station: at("station"), ask: ask.clone() }, progress, at_call)).await?;
                        Ok(json!({ "key": made["key"], "runtime": ask["runtime"], "model": ask["model"], "effort": ask.get("effort") }))
                    }
                    "pick.set" => self.choose.set(&at("station"), &at("of"), &params).map(|_| Value::Null),
                    _ => match self.choose.save(&at("station"), &at("of"))? {
                        Saved::Done(value) => Ok(value),
                        Saved::Op(op) => {
                            Box::pin(self.execute(Call::Op(op), progress, at_call)).await?;
                            Ok(json!({ "saved": true }))
                        }
                    },
                }
            }
            Call::DraftPut { station, chat, draft } => {
                let topic = Topic::Draft { station, chat };
                let empty = |field: &str| draft.get(field).is_none_or(|v| v.as_str().is_some_and(|s| s.trim().is_empty()) || v.as_array().is_some_and(Vec::is_empty));
                if empty("text") && empty("quotes") && empty("files") {
                    self.data.forget_topic(&topic);
                } else {
                    self.data.set_soon(&topic, draft);
                }
                Ok(Value::Null)
            }
            Call::DraftGet { station, chat } => Ok(self.data.get(&Topic::Draft { station, chat }).unwrap_or_else(|| json!({ "text": "", "quotes": [], "files": [] }))),
            Call::ChatRef { station, id, title, base } => {
                let base = base.unwrap_or_else(|| self.host.cloud_origin());
                Ok(json!({ "mark": crate::refs::mark(&self.data, &base, &station, &id, &title) }))
            }
            Call::ChatRefsKeep { links } => {
                crate::refs::keep(&self.data, links);
                Ok(Value::Null)
            }
            Call::PrefsSet { patch, fill } => {
                crate::prefs::set(&self.data, patch, fill, self.host.now_ms())?;
                Ok(Value::Null)
            }
            Call::ClientDevice { facts } => {
                crate::prefs::device(&self.data, &facts)?;
                self.changelog.device(&facts);
                Ok(Value::Null)
            }
            Call::ChangelogSeen => {
                self.changelog.seen();
                Ok(Value::Null)
            }
            Call::StationUpload { station, name, bytes } => {
                self.stations.upload(&StationAddr::parse(&station)?, &name, bytes).await
            }
            Call::StationFile { station, key, name, thumb, progress: wanted } => {
                // `{ loaded, total }` in bytes as the file comes (total: null when the station does not say), for a UI
                // that asked: one that did not would take the first as the answer.
                let report = |loaded: u64, total: Option<u64>| {
                    if wanted {
                        progress(json!({ "loaded": loaded, "total": total }));
                    }
                };
                let (kind, bytes) = self.stations.file(&StationAddr::parse(&station)?, &key, &name, thumb, report).await?;
                Ok(json!({ "type": kind, "bytes": encode_bytes(self.host.as_ref(), bytes).await? }))
            }
            Call::StationPreview { station, port, method, path, headers, body, stream: false } => {
                let (status, headers, bytes) = self.stations.preview(&StationAddr::parse(&station)?, port, &method, &path, headers, body).await?;
                Ok(json!({ "status": status, "headers": headers, "body": encode_bytes(self.host.as_ref(), bytes).await? }))
            }
            // As it comes: `{head: {status, headers}}`, then `{chunk}` (base64) for each piece of the body; the answer
            // (null) once it ended. Cancelling the call stops it.
            Call::StationPreview { station, port, method, path, headers, body, stream: true } => {
                let (status, headers, mut chunks) = self.stations.preview_stream(&StationAddr::parse(&station)?, port, &method, &path, headers, body).await?;
                progress(json!({ "head": { "status": status, "headers": headers } }));
                while let Some(chunk) = chunks.next().await {
                    progress(json!({ "chunk": encode_bytes(self.host.as_ref(), chunk?).await? }));
                }
                Ok(Value::Null)
            }
            // A preview page's WebSocket: `{open: {protocol}}` once the service took it, then `{text}` or `{binary}`
            // (base64) for each message; the answer is its close, `{code, reason}`. What the page sends goes by
            // `preview.socket.send` under the socket's name; cancelling the call drops the socket.
            Call::PreviewSocket { station, port, path, headers, socket: name } => {
                // Named before it opens: what the page sends meanwhile (a close right away) waits, and goes once it is open.
                let (tx, mut from_page) = futures::channel::mpsc::unbounded();
                let _open = Registered::new(self.preview_sockets.clone(), (at.0, name), tx).ok_or_else(|| CoreError::invalid("这个名字的 WebSocket 已经开着"))?;
                let station = StationAddr::parse(&station)?;
                let opening = self.stations.preview_socket(&station, port, &path, headers);
                let mut held = Vec::new();
                let socket = match open_unless_closed(opening, &mut from_page, &mut held).await? {
                    Ok(socket) => socket,
                    Err((code, reason)) => return Ok(json!({ "code": code, "reason": reason })),
                };
                let protocol = socket.reply.header("sec-websocket-protocol").unwrap_or("").to_string();
                progress(json!({ "open": { "protocol": protocol } }));
                let (mut from_station, mut to_station) = (socket.reply.body.fuse(), socket.send);
                let mut from_page = futures::stream::iter(held).chain(from_page);
                let mut buf = Vec::new();
                // The page's own close, once sent: what the socket closed with if the station says nothing after.
                let mut closing: Option<(u16, String)> = None;
                loop {
                    futures::select! {
                        chunk = from_station.next() => {
                            let Some(Ok(chunk)) = chunk else {
                                let (code, reason) = closing.unwrap_or((1006, String::new()));
                                return Ok(json!({ "code": code, "reason": reason }));
                            };
                            buf.extend(chunk);
                            for frame in station::SocketFrame::take(&mut buf) {
                                match frame {
                                    station::SocketFrame::Text(text) => progress(json!({ "text": text })),
                                    station::SocketFrame::Binary(bytes) => progress(json!({ "binary": encode_bytes(self.host.as_ref(), bytes).await? })),
                                    station::SocketFrame::Close(code, reason) => return Ok(json!({ "code": code, "reason": reason })),
                                }
                            }
                        }
                        frame = from_page.next() => {
                            let Some(frame) = frame else { continue };
                            if let station::SocketFrame::Close(code, reason) = &frame {
                                closing = Some((*code, reason.clone()));
                            }
                            if to_station.write(frame.encode()).await.is_err() {
                                let (code, reason) = closing.unwrap_or((1006, String::new()));
                                return Ok(json!({ "code": code, "reason": reason }));
                            }
                        }
                    }
                }
            }
            Call::PreviewSocketSend { socket, frame } => {
                let sent = self.preview_sockets.borrow().get(&(at.0, socket)).map(|tx| tx.unbounded_send(frame).is_ok());
                match sent {
                    Some(true) => Ok(Value::Null),
                    _ => Err(CoreError::new("not_found", "这个 WebSocket 已经关了")),
                }
            }
            Call::Ask(ask) => self.asks.run(ask, &self.accounts).await,
            Call::Migrate { accounts, device } => {
                if let Some(accounts) = accounts {
                    self.accounts.migrate(accounts).await?;
                }
                if let Some(device) = device {
                    self.mesh().await?.migrate(device).await?;
                }
                Ok(Value::Null)
            }
        }
    }
    /// Has the station make a chat asked for here (`chat.create`), in the background: then what was sent to it
    /// meanwhile goes in, in order. Failing, the chat and its messages say why, until tried again.
    pub(super) fn make_chat(&self, key: &str) {
        let Some((station, ask)) = self.views.pending_try(key) else { return };
        let (Some(core), key) = (self.me.upgrade(), key.to_string()) else { return };
        self.host.spawn(async move {
            let made = async {
                let op = crate::ops::Request { target: crate::ops::Target::Station(station.clone()), method: "POST", path: "/sessions".into(), body: Some(ask), fallback: None, effect: crate::ops::Effect::Session(None) };
                core.stations.perform(&StationAddr::parse(&station)?, &op).await
            }.await;
            let made = made.and_then(|answer| {
                let session = answer.get("key").and_then(Value::as_str).map(str::to_string);
                let thread = answer.get("thread").and_then(|t| t.get("id")).and_then(Value::as_u64);
                session.zip(thread).ok_or_else(|| CoreError::new("bad_response", "station 的回复里没有新会话"))
            });
            match made {
                Ok((session, thread)) => {
                    for (id, message) in core.views.pending_made(&key, &session, thread) {
                        // One failing stays in the outbox as failed; the rest still go, in order.
                        let _ = core.deliver(&station, thread, &id, message).await;
                    }
                }
                Err(error) => core.views.pending_failed(&key, &error.message),
            }
        }.boxed_local());
    }
    /// Posts an outgoing message into a chat. The entry leaves the outbox in the emission that brings the message
    /// into the chat's messages; a failure leaves it there as `failed`.
    pub(super) async fn deliver(&self, station: &str, thread: u64, id: &str, message: Value) -> Result<Value> {
        let result = async { self.stations.post(&StationAddr::parse(station)?, thread, message).await }.await;
        match result {
            Ok(seq) => {
                self.views.outbox_sent(station, thread, id, seq);
                Ok(json!({ "seq": seq }))
            }
            Err(error) => {
                self.views.outbox_state(station, thread, id, Some(&error.message));
                Err(error)
            }
        }
    }
}
