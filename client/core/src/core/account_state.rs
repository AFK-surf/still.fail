//! Accounts, workspace ownership, credentials and cloud topic refresh.
use super::*;

impl Inner {
    /// Dispatch for the agreed native UI calls; deliberately separate from best-effort sign-out.
    pub(super) async fn execute_native_auth(&self, call: super::calls::NativeAuthCall) -> Result<Value> {
        use super::calls::NativeAuthCall;
        match call {
            NativeAuthCall::AppleBegin => self.accounts.apple_begin().await,
            NativeAuthCall::AppleComplete { attempt, identity_token, authorization_code, name, state } =>
                self.accounts.apple_complete(&attempt, &identity_token, &authorization_code, name, state).await,
            NativeAuthCall::DeletionSummary { account } => self.accounts.deletion_summary(&account).await,
            NativeAuthCall::DeleteAccount { account } => {
                let receipt = self.accounts.delete_account(&account).await?;
                self.recompute_owners();
                self.forget_unreachable();
                Ok(receipt)
            }
        }
    }

    /// The device endpoint, bringing it up the first time.
    pub(super) async fn mesh(&self) -> Result<Rc<Mesh>> {
        let pending = self.mesh.borrow().clone();
        let pending = match pending {
            Some(pending) => pending,
            None => {
                let core = self.me.clone();
                let pending = async move {
                    let core = core.upgrade().ok_or_else(gone)?;
                    let relays = core.relays().await?;
                    Mesh::new(core.host.clone(), core.tracer.clone(), &relays).await
                }
                .boxed_local()
                .shared();
                *self.mesh.borrow_mut() = Some(pending.clone());
                pending
            }
        };
        let result = pending.clone().await;
        if result.is_err() {
            let mut mesh = self.mesh.borrow_mut();
            if mesh.as_ref().is_some_and(|m| m.ptr_eq(&pending)) {
                *mesh = None;
            }
        }
        result
    }
    /// This device's member credential for a workspace, kept on the device: what gets it into the workspace's
    /// stations with no still.fail cloud on the way (on a LAN, or the cloud down). Kept, it serves for a day; then, or when
    /// a station refused it (`fresh`), a new one is asked for — and if still.fail cloud cannot be reached, the kept one goes
    /// on serving until it runs out (30 days).
    pub(super) async fn credential(&self, workspace: &str, device: &str, fresh: bool) -> Result<Credential> {
        let sub = self.owner(workspace).await?;
        let key = format!("{CREDENTIAL_KEY}/{sub}/{workspace}");
        // The mesh's endpoints on one relay alone have keys of their own (mesh.rs `pinned_key`): theirs are kept apart,
        // and the device key's where it always was.
        let others_key = format!("{key}/{CREDENTIAL_OTHERS}");
        let main = self.mesh.borrow().as_ref().and_then(|m| m.peek().cloned()).and_then(|m| m.ok()).map(|m| m.device_id());
        let other = main.is_some_and(|main| main != device);
        let now = self.host.now_ms() / 1000.0;
        let mut others: Vec<KeptCredential> = if other { self.host.storage_get(&others_key).await.ok().flatten().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default() } else { Vec::new() };
        let kept = if other {
            others.iter().find(|k| k.device == device).cloned()
        } else {
            self.host.storage_get(&key).await.ok().flatten().and_then(|bytes| serde_json::from_slice::<KeptCredential>(&bytes).ok()).filter(|k| k.device == device)
        };
        let kept = kept.map(|k| k.credential).filter(|c| c.expires_at > now + 60.0 && !fresh);
        if let Some(c) = kept.as_ref().filter(|c| now - c.issued_at < CREDENTIAL_FOR_S) {
            return Ok(c.clone());
        }
        match self.cloud.credential(&sub, workspace, device).await {
            Ok(credential) => {
                let kept = KeptCredential { device: device.to_string(), credential: credential.clone() };
                if other {
                    others.retain(|k| k.device != device);
                    others.insert(0, kept);
                    others.truncate(CREDENTIAL_OTHERS_KEPT);
                    let _ = self.host.storage_set(&others_key, serde_json::to_vec(&others).unwrap_or_default()).await;
                } else {
                    let _ = self.host.storage_set(&key, serde_json::to_vec(&kept).unwrap_or_default()).await;
                }
                Ok(credential)
            }
            Err(error) => kept.ok_or(error),
        }
    }
    /// The relays the mesh uses, from any account's `/v1/me`.
    pub(super) async fn relays(&self) -> Result<Vec<String>> {
        if let Some(relays) = self.relays.borrow().clone() {
            return Ok(relays);
        }
        // As last heard (kept on the device): the mesh comes up without still.fail cloud.
        for account in self.accounts.list() {
            if let Some(relays) = self.data.record("me", &account.sub).and_then(|me| relays_of(&me)) {
                return Ok(relays);
            }
        }
        let mut last = CoreError::signed_out(t!("core-misc.account.none"));
        for (_, me) in self.load_me().await {
            match me {
                Ok(me) => {
                    if let Some(relays) = relays_of(&me) {
                        return Ok(relays);
                    }
                }
                Err(error) => last = error,
            }
        }
        Err(last)
    }
    /// The signed-in account that reaches `workspace`, asking every account's `/v1/me` if it is not known yet.
    pub(super) async fn owner(&self, workspace: &str) -> Result<String> {
        let known = |core: &Inner| {
            let sub = core.workspaces.owner(workspace)?;
            core.accounts.list().iter().any(|a| a.sub == sub).then_some(sub)
        };
        if let Some(sub) = known(self) {
            return Ok(sub);
        }
        self.load_me().await;
        known(self).ok_or_else(|| CoreError::new("not_found", t!("core-misc.account.no_access")).with_status(404))
    }
    /// Every account's `/v1/me`, noting who reaches which workspace and the relay url on the way.
    /// One at a time: whoever asks while it is under way waits for that one.
    pub(super) async fn load_me(&self) -> Vec<(AccountView, Result<Value>)> {
        let pending = self.me_loading.borrow().clone();
        let pending = match pending {
            Some(pending) => pending,
            None => {
                let core = self.me.clone();
                let pending = async move {
                    let Some(core) = core.upgrade() else { return };
                    let accounts = core.accounts.list();
                    core.load_me_of(&accounts).await;
                    core.me_loading.borrow_mut().take();
                }
                .boxed_local()
                .shared();
                *self.me_loading.borrow_mut() = Some(pending.clone());
                pending
            }
        };
        pending.await;
        let accounts = self.accounts.list();
        let mes = self.mes.borrow();
        accounts.into_iter().map(|a| {
            let me = match mes.get(&a.sub).cloned() {
                Some(Ok(())) => self.data.record("me", &a.sub).ok_or_else(|| CoreError::signed_out(t!("core-misc.account.signed_out"))),
                Some(Err(error)) => Err(error),
                None => Err(CoreError::signed_out(t!("core-misc.account.signed_out"))),
            };
            (a, me)
        }).collect()
    }
    /// These accounts' `/v1/me`, kept per account; an answer overtaken by a newer request is dropped.
    pub(super) async fn load_me_of(&self, accounts: &[AccountView]) {
        let asked: Vec<u64> = accounts.iter().map(|a| {
            let mut fetches = self.me_fetches.borrow_mut();
            let n = fetches.entry(a.sub.clone()).or_default();
            *n += 1;
            *n
        }).collect();
        let answers = join_all(accounts.iter().map(|a| self.cloud.me(&a.sub))).await;
        for ((account, n), me) in accounts.iter().zip(asked).zip(answers) {
            if self.me_fetches.borrow().get(&account.sub) != Some(&n) {
                continue;
            }
            if let Ok(me) = &me {
                if let Some(relays) = relays_of(me) {
                    let first = self.relays.borrow().is_none();
                    self.relays.borrow_mut().get_or_insert(relays);
                    // The relay is known: bring the device endpoint up now and let it reach the relay while the page
                    // loads, so a station link has only its own handshake to do (no request of its own: the URL is here).
                    if first && self.mesh.borrow().is_none() {
                        let warm = self.me.clone();
                        self.host.spawn(
                            async move {
                                if let Some(core) = warm.upgrade() {
                                    let _ = core.mesh().await;
                                }
                            }
                            .boxed_local(),
                        );
                    }
                }
                self.data.put("me", &account.sub, me.clone());
            } else if let Err(error) = &me
                && error.code == crate::cloud::NOT_BETA
            {
                // A beta app the account may not use: what it reached is not reached through this app (kept from
                // before, it would show its workspaces as if they could be opened).
                self.data.forget_record("me", &account.sub);
            }
            self.mes.borrow_mut().insert(account.sub.clone(), me.map(|_| ()));
        }
        self.recompute_owners();
        self.forget_unreachable();
    }
    /// Which account reaches each workspace: the first (in sign-in order) whose last `/v1/me` answer lists it.
    /// An account whose latest request failed keeps what it was known to reach; signed-out ones are forgotten.
    pub(super) fn recompute_owners(&self) {
        let accounts = self.accounts.list();
        self.mes.borrow_mut().retain(|sub, _| accounts.iter().any(|a| &a.sub == sub));
        for (sub, me) in self.data.records("me") {
            if !accounts.iter().any(|a| a.sub == sub) {
                // Signed out: its credentials go too (a station would take them for 30 days).
                for workspace in me.get("workspaces").and_then(Value::as_array).into_iter().flatten() {
                    if let Some(id) = workspace.get("id").and_then(Value::as_str) {
                        let (host, key) = (self.host.clone(), format!("{CREDENTIAL_KEY}/{sub}/{id}"));
                        self.host.spawn(async move {
                            let _ = host.storage_delete(&format!("{key}/{CREDENTIAL_OTHERS}")).await;
                            let _ = host.storage_delete(&key).await;
                        }.boxed_local());
                    }
                }
                self.data.forget_record("me", &sub);
            }
        }
        let mut owners: HashMap<String, String> = HashMap::new();
        for account in &accounts {
            let Some(me) = self.data.record("me", &account.sub) else { continue };
            for workspace in me.get("workspaces").and_then(Value::as_array).into_iter().flatten() {
                if let Some(id) = workspace.get("id").and_then(Value::as_str) {
                    owners.entry(id.to_string()).or_insert_with(|| account.sub.clone());
                }
            }
        }
        self.workspaces.set_owners(&owners);
        // A workspace's status shows its account's socket.
        self.store.invalidate_all(|t| matches!(t, Topic::Status { workspace: Some(_) }));
    }
    /// What is kept on the device of stations no signed-in account reaches any more goes (all of it once the last
    /// one signs out) — decided only when every account's `/v1/me` has answered once, since one not heard from
    /// yet may reach them. What a station's own page (`local`, gone) left goes with them.
    pub(super) fn forget_unreachable(&self) {
        if self.accounts.list().iter().any(|a| self.data.record("me", &a.sub).is_none()) {
            return;
        }
        let workspaces: HashSet<String> = self.workspaces.owned().into_iter().map(|(id, _)| id).collect();
        let reached = workspaces.clone();
        self.data.retain(move |station| station.split_once('/').is_some_and(|(w, _)| reached.contains(w)), Some(&workspaces));
        self.host.spawn(self.kept.retain(move |station| station.split_once('/').is_some_and(|(w, _)| workspaces.contains(w))));
    }
    /// A workspace's stations as it lists them now: what is kept of the others in it goes.
    pub(super) fn forget_gone_stations(&self, workspace: &str, view: &Value) {
        let ids: HashSet<String> = view.get("stations").and_then(Value::as_array).into_iter().flatten().filter_map(|s| Some(s.get("id")?.as_str()?.to_string())).collect();
        let workspace = workspace.to_string();
        let (listed, of) = (ids.clone(), workspace.clone());
        self.data.retain(move |station| match station.split_once('/') {
            Some((w, id)) if w == of => listed.contains(id),
            _ => true,
        }, None);
        self.host.spawn(self.kept.retain(move |station| match station.split_once('/') {
            Some((w, id)) if w == workspace => ids.contains(id),
            _ => true,
        }));
    }
    pub(super) fn accounts_value(&self) -> Result<Value> {
        Ok(serde_json::to_value(self.accounts.list()).expect("accounts serialize"))
    }
    /// Every account with what its `/v1/me` said, as the data center has it (from this run, or kept from the last).
    /// `loaded` is true only once it answered this run: what was kept, or an empty list before an answer (or after a
    /// failure), is not "none" — a UI that makes a workspace for an account with none waits for it.
    pub(super) fn workspaces_value(&self) -> Value {
        let mes = self.mes.borrow();
        let entries = self.accounts.list().into_iter().map(|account| {
            let me = self.data.record("me", &account.sub).unwrap_or(Value::Null);
            let mut entry = json!({
                "account": account,
                "workspaces": me.get("workspaces").cloned().unwrap_or_else(|| json!([])),
                "invitations": me.get("invitations").cloned().unwrap_or_else(|| json!([])),
                "relay_url": me.get("relay_url").cloned().unwrap_or(Value::Null),
                "loaded": matches!(mes.get(&account.sub), Some(Ok(()))),
            });
            // still.fail cloud lets this account use the beta apps (`user.beta`); absent otherwise.
            if me.pointer("/user/beta").and_then(Value::as_bool) == Some(true) {
                entry["beta"] = json!(true);
            }
            // One account failing (offline, signed out elsewhere) still shows the others.
            if let Some(Err(error)) = mes.get(&account.sub) {
                entry["error"] = json!(error);
                // A beta app, and an account still.fail cloud has not let into the beta: said as such, for the UI to
                // show with a way to sign the account out (it reaches nothing here).
                if error.code == crate::cloud::NOT_BETA {
                    entry["blocked"] = json!(crate::cloud::not_beta_text());
                }
            }
            entry
        });
        Value::Array(entries.collect())
    }
    pub(super) async fn workspace_value(&self, workspace: &str) -> Result<Value> {
        let sub = self.owner(workspace).await?;
        self.cloud.request(&sub, "GET", &format!("/v1/workspaces/{}", encode(workspace)), None).await
    }
    pub(super) fn start_topic(&self, topic: &Topic) {
        if *topic == Topic::Accounts {
            self.store.set(topic, self.accounts_value());
            return;
        }
        self.live.borrow_mut().insert(topic.clone(), 0);
        // What the accounts' `/v1/me` said last time is shown at once (not `loaded`); reading it again follows.
        if *topic == Topic::Workspaces && self.accounts.list().iter().any(|a| self.data.record("me", &a.sub).is_some()) {
            self.store.set(topic, Ok(self.workspaces_value()));
        }
        self.sync_sockets();
        // A socket on its first try reads the topics when it opens; otherwise they are read now.
        if !self.sockets.borrow().values().any(|s| s.state == SocketState::Connecting) {
            self.spawn_refresh(topic.clone());
        }
    }
    pub(super) fn spawn_refresh(&self, topic: Topic) {
        let core = self.me.clone();
        self.host.spawn(
            async move {
                if let Some(core) = core.upgrade() {
                    core.refresh(&topic).await;
                }
            }
            .boxed_local(),
        );
    }
    /// Reads one account topic again; an answer overtaken by a newer fetch is dropped.
    pub(super) async fn refresh(&self, topic: &Topic) {
        self.refresh_with(topic, false).await
    }
    /// `me_read`: every account's `/v1/me` was just read, so `workspaces` needs no request of its own.
    pub(super) async fn refresh_with(&self, topic: &Topic, me_read: bool) {
        let fetch = {
            let mut live = self.live.borrow_mut();
            let Some(fetch) = live.get_mut(topic) else { return };
            *fetch += 1;
            *fetch
        };
        let value = match topic {
            Topic::Workspaces => {
                if !me_read {
                    self.load_me().await;
                }
                Ok(self.workspaces_value())
            }
            Topic::Workspace { workspace } => self.workspace_value(workspace).await,
            // Read as they are now; a write to still.fail cloud (ops.rs) reads them again (refresh_all).
            Topic::LoginSessions { account } => self.cloud.request(account, "GET", "/v1/auth/sessions", None).await.map(|v| v.get("sessions").cloned().unwrap_or(json!([]))),
            Topic::Admin { account, list } => match list.as_str() {
                "users" | "workspaces" | "invite-codes" | "feedback" => self.cloud.request(account, "GET", &format!("/v1/admin/{list}"), None).await,
                _ => Err(CoreError::invalid(t!("core-misc.account.no_list"))),
            },
            _ => return,
        };
        if let (Topic::Workspace { workspace }, Ok(view)) = (topic, &value) {
            self.forget_gone_stations(workspace, view);
        }
        if self.live.borrow().get(topic) == Some(&fetch) {
            // A workspace goes to the data center; the list of them is put together from the accounts' records.
            self.center.set(topic, value);
        }
    }
    /// What UIs attend to changed: the chats shown are put together again (their lines, what is read).
    pub(super) fn attended(&self) {
        for topic in self.store.live_topics() {
            if matches!(topic, Topic::Chat { .. }) {
                self.store.invalidate(&topic);
            }
        }
    }
    /// Gives this device's push registration (as kept) to the signed-in accounts that do not have it yet.
    pub(super) async fn push_registered(&self) -> Result<Value> {
        let Some(mut kept) = self.host.storage_get(PUSH_KEY).await.ok().flatten().and_then(|b| serde_json::from_slice::<KeptPush>(&b).ok()) else {
            return Ok(Value::Null);
        };
        let accounts = self.accounts.list();
        kept.with.retain(|sub| accounts.iter().any(|a| &a.sub == sub));
        // Notifications are said in the person's language: the cloud is told it with the registration, again when it changes.
        let lang = stillfail_i18n::current().code();
        if kept.lang.as_deref() != Some(lang) {
            kept.with.clear();
            kept.lang = Some(lang.to_string());
        }
        if let Value::Object(registration) = &mut kept.registration {
            registration.insert("lang".into(), Value::from(lang));
        }
        let mut failed = None;
        let missing: Vec<&AccountView> = accounts.iter().filter(|a| !kept.with.contains(&a.sub)).collect();
        for account in missing {
            match self.cloud.request(&account.sub, "POST", "/v1/push", Some(kept.registration.clone())).await {
                Ok(_) => kept.with.push(account.sub.clone()),
                Err(error) => failed = Some(error),
            }
        }
        let _ = self.host.storage_set(PUSH_KEY, serde_json::to_vec(&kept).unwrap_or_default()).await;
        match failed {
            Some(error) => Err(error),
            None => Ok(Value::Null),
        }
    }
    /// The accounts as UIs see them changed (a token refresh alone changes nothing here).
    pub(super) fn accounts_changed(&self) {
        let list = self.accounts.list();
        if *self.shown_accounts.borrow() == list {
            return;
        }
        *self.shown_accounts.borrow_mut() = list;
        // Signed out: what only that account reached goes now, whether or not anything is shown.
        self.recompute_owners();
        self.forget_unreachable();
        self.store.set(&Topic::Accounts, self.accounts_value());
        self.sync_sockets();
        let core = self.me.clone();
        self.host.spawn(
            async move {
                if let Some(core) = core.upgrade() {
                    // Someone signed in: their devices hear pushes too.
                    let _ = core.push_registered().await;
                    core.refresh_all().await;
                }
            }
            .boxed_local(),
        );
    }
    /// Reads every live `workspaces` / `workspace` topic again: `/v1/me` once, then each workspace.
    pub(super) async fn refresh_all(&self) {
        let topics: Vec<Topic> = self.live.borrow().keys().cloned().collect();
        if topics.is_empty() {
            return;
        }
        self.load_me().await;
        join_all(topics.iter().map(|topic| self.refresh_with(topic, true))).await;
    }
    // ── still.fail cloud's events ──

    /// One socket per signed-in account while any account topic is live; none otherwise.
    pub(super) fn sync_sockets(&self) {
        let wanted: Vec<String> = if self.live.borrow().is_empty() { Vec::new() } else { self.accounts.list().into_iter().map(|a| a.sub).collect() };
        let mut sockets = self.sockets.borrow_mut();
        sockets.retain(|sub, socket| {
            let keep = wanted.contains(sub);
            if !keep {
                socket.task.abort();
                self.status.socket_up(sub);
            }
            keep
        });
        for sub in wanted {
            if sockets.contains_key(&sub) {
                continue;
            }
            let (task, registration) = AbortHandle::new_pair();
            sockets.insert(sub.clone(), Socket { task, state: SocketState::Connecting });
            let follow = Abortable::new(follow_socket(self.me.clone(), sub), registration).map(|_| ());
            self.host.spawn(follow.boxed_local());
        }
    }
    /// Notes a socket's state; answers the one before.
    pub(super) fn socket_state(&self, sub: &str, state: SocketState) -> Option<SocketState> {
        self.sockets.borrow_mut().get_mut(sub).map(|s| std::mem::replace(&mut s.state, state))
    }
    /// Opens an account's events socket with a token good now (refreshed when it is about to expire).
    pub(super) async fn open_socket(&self, sub: &str) -> Result<crate::host::SocketFrames> {
        let token = self.accounts.access_token(sub).await?;
        let origin = self.host.cloud_origin();
        let url = match origin.strip_prefix("https://") {
            Some(rest) => format!("wss://{rest}/v1/events"),
            None => format!("ws://{}/v1/events", origin.strip_prefix("http://").unwrap_or(&origin)),
        };
        Ok(self.host.websocket(url, vec![EVENTS_PROTOCOL.into(), format!("stillfail-token.{token}")]).await?)
    }
    pub(super) fn on_cloud_event(&self, sub: &str, text: &str) {
        let Ok(event) = serde_json::from_str::<Value>(text) else { return };
        match event.get("type").and_then(Value::as_str) {
            Some("workspaces") => {
                let (core, sub) = (self.me.clone(), sub.to_string());
                self.host.spawn(
                    async move {
                        let Some(core) = core.upgrade() else { return };
                        let Some(account) = core.accounts.list().into_iter().find(|a| a.sub == sub) else { return };
                        core.load_me_of(&[account]).await;
                        if core.live.borrow().contains_key(&Topic::Workspaces) {
                            core.store.set(&Topic::Workspaces, Ok(core.workspaces_value()));
                        }
                    }
                    .boxed_local(),
                );
            }
            Some("workspace") => {
                let Some(id) = event.get("id").and_then(Value::as_str) else { return };
                let topic = Topic::Workspace { workspace: id.to_string() };
                if self.live.borrow().contains_key(&topic) {
                    self.spawn_refresh(topic);
                }
            }
            _ => {}
        }
    }
}
