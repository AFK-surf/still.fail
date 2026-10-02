//! Station event subscriptions, reconnection and event application.
use super::*;

impl Stations {
    // ── the events stream ──

    /// Opens the station's `/events` if it is not open, or opens it anew when a `host` topic starts or stops
    /// (host samples are asked for with `?host=1` when the stream opens).
    pub(super) fn sync_events(&self, station: &str) {
        self.open_events(station, false)
    }
    /// Opens the station's `/events` for what its topics want now (unless its stream already is, or `anew`): the
    /// new stream opens first, and the old one goes once it has, so nothing falls between.
    pub(super) fn open_events(&self, station: &str, anew: bool) {
        if !self.reachable(station) {
            return;
        }
        // A session is followed once its live topic has what was kept of it: the stream asks from there.
        let mut live: Vec<String> = self
            .live_topics(station, |t| matches!(t, Topic::Live { .. }))
            .into_iter()
            .filter(|t| self.sink.get(t).is_some())
            .filter_map(|t| match t {
                Topic::Live { key, .. } => Some(key),
                _ => None,
            })
            .collect();
        live.sort();
        let mut logs: Vec<(String, u64)> = self
            .live_topics(station, |t| matches!(t, Topic::JobLog { .. }))
            .into_iter()
            .filter_map(|t| match t {
                Topic::JobLog { job, lines, .. } => Some((job, lines)),
                _ => None,
            })
            .collect();
        logs.sort();
        let (addr, wants, generation) = {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            let wants = EventsFor { host: s.wants_host(), live, logs };
            if !anew && s.events.as_ref().is_some_and(|(_, asks)| *asks == wants) {
                return;
            }
            // Replacing a stream gone quiet: it may have died unnoticed (the app away, the link gone), and what was said
            // meanwhile is read again once its successor opens, as after a drop.
            let now = self.host.now_ms();
            if s.events.is_some() && s.heard.is_some_and(|h| now - h > STREAM_QUIET_MS as f64) {
                s.stale = true;
            }
            if let Some((old, _)) = s.events.take()
                && let Some(older) = s.replaced.replace(old)
            {
                older.abort();
            }
            s.generation += 1;
            (s.addr.clone(), wants, s.generation)
        };
        // The first try belongs to whoever asked for the stream (a chat opening); later ones are traces of their own.
        let task = self.spawn_in(None, self.rc().follow_events(station.to_string(), addr, wants.clone(), generation, self.tracer.current()));
        if let Some(s) = self.of(station).stations.borrow_mut().get_mut(station) {
            s.events = Some((task, wants));
        }
    }
    /// The path of an `/events` stream for `wants`, each session asked for from the entries its topic has.
    pub(super) fn events_path(&self, station: &str, wants: &EventsFor) -> String {
        let mut query: Vec<String> = Vec::new();
        if wants.host {
            query.push("host=1".into());
        }
        for key in &wants.live {
            let topic = Topic::Live { station: station.into(), key: key.clone() };
            let from = self.sink.get(&topic).and_then(|v| Some(first_of(&v) + v.get("timeline")?.as_array()?.len() as u64)).unwrap_or(0);
            // No more than the latest page: a station older than `last` sends all from `from`.
            query.push(format!("live={}&from={from}&last={TRANSCRIPT_PAGE}", encode(key)));
        }
        // A station older than `job` leaves it out (and its log is read again instead, see `follow_log`).
        for (job, lines) in &wants.logs {
            query.push(format!("job={}&lines={lines}", encode(job)));
        }
        if query.is_empty() { "/events".into() } else { format!("/events?{}", query.join("&")) }
    }
    /// Whether this stream is the station's newest; if so, the one it replaces goes now.
    pub(super) fn took_over(&self, station: &str, generation: u64) -> bool {
        let workspace = self.of(station);
        let mut stations = workspace.stations.borrow_mut();
        let Some(s) = stations.get_mut(station) else { return false };
        if s.generation != generation {
            return false;
        }
        if let Some(old) = s.replaced.take() {
            old.abort();
        }
        true
    }
    /// The current stream gave something now (`open`), or is no longer open.
    pub(super) fn heard(&self, station: &str, generation: u64, open: bool) {
        let now = self.host.now_ms();
        if let Some(s) = self.of(station).stations.borrow_mut().get_mut(station)
            && s.generation == generation
        {
            s.heard = open.then_some(now);
        }
    }
    pub(super) fn is_current(&self, station: &str, generation: u64) -> bool {
        self.of(station).stations.borrow().get(station).is_some_and(|s| s.generation == generation)
    }
    pub(super) fn set_stale(&self, station: &str, stale: bool) -> bool {
        self.of(station).stations.borrow_mut().get_mut(station).map(|s| std::mem::replace(&mut s.stale, stale)).unwrap_or(false)
    }
    /// Holds the station's `/events` open while any of its topics is live; its events keep the topics current.
    pub(super) async fn follow_events(self: Rc<Self>, station: String, addr: StationAddr, wants: EventsFor, generation: u64, mut parent: Option<SpanContext>) {
        let mut first = true;
        // How the last stream ended and how long it lasted: on the reconnect's span, so a stream that keeps ending shows why.
        let mut previous: Option<(String, f64)> = None;
        // Tries in a row that did not reach it, and whether it was reached before: a station that was up and dropped
        // is coming back (`reconnecting`) for a few tries; one not reached for MISSES, or never, is down (`offline`).
        let mut misses: u32 = 0;
        let mut reached = false;
        loop {
            // Replaced before it opened: its successor asks instead.
            if !self.is_current(&station, generation) {
                return;
            }
            let name = if std::mem::replace(&mut first, false) { "station.connect" } else { "station.reconnect" };
            let mut span = self.tracer.enter(parent.take(), || self.tracer.span(name, Kind::Internal));
            span.set("stillfail.station", station.clone());
            if let Some((why, lasted)) = previous.take() {
                span.set("stillfail.previous.end", why);
                span.set("stillfail.previous.lasted_ms", lasted.round() as i64);
            }
            // Asked anew each time: a session is followed from what its topic has by then.
            let path = self.events_path(&station, &wants);
            let opening = self.tracer.instrument(Some(span.context()), self.open_stream(&addr, &path));
            // Still opening when the UI came back from being away since before: on a way taken for gone, tried anew now.
            // (A wire that races its links asks again on the new one itself.)
            let sent = self.host.now_ms();
            let races = self.wire.races();
            let dropped = {
                let this = self.clone();
                let station = station.clone();
                async move {
                    loop {
                        let wake = wake::woken_for(this.host.clone(), move |w| w.suspects_connections() || w.drops_request(sent)).await;
                        if !races && wake.drops_request(sent) {
                            return;
                        }
                        // Tried again beside this try (mesh.rs `hedge`), as a person tapped 重试: said at once.
                        this.retrying(&station);
                    }
                }
            };
            pin_mut!(opening, dropped);
            let opened = match futures::future::select(opening, dropped).await {
                Either::Left((opened, _)) => opened,
                Either::Right(_) => {
                    self.wire.reset(&addr);
                    span.fail();
                    span.end();
                    previous = Some((wake::GONE.to_string(), 0.0));
                    self.set_stale(&station, true);
                    continue;
                }
            };
            if !self.took_over(&station, generation) {
                return;
            }
            match opened {
                Ok(mut body) => {
                    misses = 0;
                    reached = true;
                    self.heard(&station, generation, true);
                    self.set_link(&station, json!({ "state": "online" }));
                    // Down for a while: what changed meanwhile was not told.
                    if self.set_stale(&station, false) {
                        self.refetch_all(&station, span);
                    } else {
                        span.end();
                    }
                    let mut parser = SseParser::default();
                    let opened_at = self.host.now_ms();
                    let mut why = "ended".to_string();
                    let mut heard = opened_at;
                    // The way it came is replaced by another (a link that lost to a new one, mesh.rs `race`): opened
                    // again at once on the new one, the old one not waited on.
                    let replaced = self.wire.replaced(&addr).shared();
                    loop {
                        // Nothing on it while the UI was away (not even the keepalive): taken for gone, and the link with
                        // it. A wire that races its links finds out itself, sooner: its link is replaced, or kept.
                        let gone = wake::woken_for(self.host.clone(), move |w| !races && w.drops_stream(heard)).boxed_local();
                        let ended = futures::future::select(gone, replaced.clone());
                        pin_mut!(ended);
                        let chunk = match futures::future::select(body.next(), ended).await {
                            Either::Left((Some(chunk), _)) => chunk,
                            Either::Left((None, _)) => break,
                            Either::Right((Either::Left(_), _)) => {
                                self.wire.reset(&addr);
                                why = wake::GONE.to_string();
                                break;
                            }
                            Either::Right((Either::Right(_), _)) => {
                                why = replaced();
                                break;
                            }
                        };
                        heard = self.host.now_ms();
                        self.heard(&station, generation, true);
                        match chunk {
                            Ok(bytes) => {
                                for (name, data) in parser.feed(&bytes) {
                                    self.on_event(&station, &name, &data);
                                }
                            }
                            Err(error) => {
                                why = error.message;
                                break;
                            }
                        }
                    }
                    let woke = why == wake::GONE || why == wake::NETWORK || why == replaced();
                    if !self.is_current(&station, generation) {
                        return;
                    }
                    previous = Some((why.clone(), self.host.now_ms() - opened_at));
                    self.heard(&station, generation, false);
                    self.set_stale(&station, true);
                    self.set_link(&station, json!({ "state": "reconnecting", "message": if why == "ended" { t!("station.core.disconnected") } else { why } }));
                    // Taken for gone as the UI came back: opened again at once.
                    if woke {
                        continue;
                    }
                }
                Err(error) => {
                    failed(&mut span, &error);
                    span.end();
                    previous = Some((format!("open failed: {}", error.message), 0.0));
                    self.set_stale(&station, true);
                    misses += 1;
                    // It answered, but no (refused, failing): it is there. Not reached at all: coming back, or down.
                    let state = if error.status.is_some() { "error" } else if reached && misses < MISSES { "reconnecting" } else { "offline" };
                    self.set_link(&station, json!({ "state": state, "message": error.message }));
                }
            }
            // Not reached: less and less often, up to RECONNECT_MAX_MS.
            let wait = RECONNECT_MS.saturating_mul(1u64 << misses.saturating_sub(1).min(8)).min(RECONNECT_MAX_MS);
            // A UI back after being away wants it now: no more waiting.
            if let Either::Right(_) = futures::future::select(self.host.sleep(wait), self.host.woken()).await {
                self.retrying(&station);
            }
        }
    }
    /// Down, and tried again now (a person tapped 重试, the UI came back, the network changed): `reconnecting` until
    /// the try ends, so what shows the link shows it is being tried rather than still down.
    pub(super) fn retrying(&self, station: &str) {
        let link = self.of(station).stations.borrow().get(station).map(|s| s.link.clone());
        let Some(link) = link else { return };
        if matches!(link.get("state").and_then(Value::as_str), Some("offline" | "error")) {
            self.set_link(station, json!({ "state": "reconnecting", "message": link.get("message").cloned().unwrap_or(Value::Null) }));
        }
    }
    pub(super) fn on_event(&self, station: &str, name: &str, data: &str) {
        let Ok(data) = serde_json::from_str::<Value>(data) else { return };
        match name {
            "session" => self.on_session(station, &data),
            "session-removed" => {
                let Some(key) = data.get("key").and_then(Value::as_str) else { return };
                self.on_session_removed(station, key);
            }
            "thread" => {
                let Some(id) = data.get("id").and_then(Value::as_u64) else { return };
                let entries = data.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
                // How far the thread goes, at once (a chat opens whole by it: `latest_known`); the rest of its summary
                // is read below.
                if let Some(newest) = entries.iter().filter_map(n_of).max() {
                    self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| {
                        for t in list.as_array_mut().into_iter().flatten() {
                            if t.get("id").and_then(Value::as_u64) == Some(id) && t.get("last").and_then(Value::as_u64).is_some_and(|l| l < newest) {
                                t["last"] = json!(newest);
                            }
                        }
                    });
                }
                self.put_entries(station, id, entries, true);
                // The summaries (last message, unread) are not in the event.
                self.mark_dirty(station, id);
            }
            "thread-removed" => {
                let Some(id) = data.get("id").and_then(Value::as_u64) else { return };
                self.remove_thread(station, id);
                self.host.spawn(self.kept.forget(&Log::thread(station, id)));
                let topic = Topic::Thread { station: station.into(), thread: id };
                if self.is_live(&topic) {
                    self.sink.set(&topic, Err(CoreError::new("http_404", t!("station.core.noChat")).with_status(404)));
                }
            }
            "read" => {
                let (Some(thread), Some(n)) = (data.get("thread").and_then(Value::as_u64), data.get("n").and_then(Value::as_u64)) else { return };
                self.put_read(station, thread, n);
            }
            "chat" => self.put_row(station, &data),
            "live" => {
                let Some(key) = data.get("key").and_then(Value::as_str) else { return };
                if !self.is_live(&Topic::Live { station: station.into(), key: key.into() }) {
                    return;
                }
                if !self.on_live(station, key, &data) {
                    // Entries with no timeline to go in: that session from its latest page, on a stream opened anew.
                    let topic = Topic::Live { station: station.into(), key: key.into() };
                    if let Some(s) = self.of(station).stations.borrow_mut().get_mut(station).and_then(|s| s.lives.get_mut(key)) {
                        *s = LiveView::default();
                    }
                    self.host.spawn(self.kept.forget(&Log::transcript(station, key)));
                    self.sink.set(&topic, Ok(live_start()));
                    self.open_events(station, true);
                }
            }
            "chat-removed" => {
                let Some(id) = data.get("id").and_then(Value::as_str) else { return };
                self.sink.update(&Topic::ChatRows { station: station.into() }, &mut |rows| {
                    if let Some(rows) = rows.as_array_mut() {
                        rows.retain(|r| r.get("id").and_then(Value::as_str) != Some(id));
                    }
                });
            }
            "job" => self.on_job(station, &data),
            // A job that was over, cleared: out of its session's jobs.
            "job-removed" => {
                let (Some(id), Some(key)) = (data.get("id").and_then(Value::as_str), data.get("session").and_then(Value::as_str)) else { return };
                self.sink.update(&Topic::Session { station: station.into(), key: key.into() }, &mut |detail| {
                    if let Some(jobs) = detail.get_mut("jobs").and_then(Value::as_array_mut) {
                        jobs.retain(|j| j.get("id").and_then(Value::as_str) != Some(id));
                    }
                });
            }
            // A followed job's log, at first and as it grows.
            "job-log" => {
                let (Some(id), Some(lines)) = (data.get("id").and_then(Value::as_str), data.get("lines").and_then(Value::as_u64)) else { return };
                self.set_live(Topic::JobLog { station: station.into(), job: id.into(), lines }, job_log(&data));
            }
            "overview" => self.set_live(Topic::Overview { station: station.into() }, data),
            "host" => self.set_live(Topic::Host { station: station.into() }, data),
            // It recorded more of what its agents spent (about once a minute while they work).
            "usage" => self.refetch(&Topic::StationUsage { station: station.into() }),
            "footprint" => self.set_live(Topic::Footprint { station: station.into() }, data),
            _ => {}
        }
    }
    /// A session's summary changed: it replaces the one in `sessions` and in its `session` topic. The detail's
    /// turns are read again only when the summary says they changed.
    pub(super) fn on_session(&self, station: &str, summary: &Value) {
        let Some(key) = summary.get("key").and_then(Value::as_str) else { return };
        // `/sessions` lists the shown ones.
        let shown = summary.get("archivedAt").is_none_or(Value::is_null);
        self.sink.update(&Topic::Sessions { station: station.into() }, &mut |list| {
            let Some(list) = list.as_array_mut() else { return };
            match (list.iter().position(|s| s.get("key").and_then(Value::as_str) == Some(key)), shown) {
                (Some(i), true) => list[i] = summary.clone(),
                (Some(i), false) => {
                    list.remove(i);
                }
                (None, true) => list.insert(0, summary.clone()),
                (None, false) => {}
            }
        });
        let topic = Topic::Session { station: station.into(), key: key.into() };
        let mut turns_changed = false;
        self.sink.update(&topic, &mut |detail| {
            turns_changed = !same_turns(detail.get("turns"), summary);
            detail["session"] = summary.clone();
        });
        if turns_changed {
            self.refetch(&topic);
        }
    }
    /// A job as it is now (its event, or the answer to stopping it): in place in its session's jobs, and among the
    /// station's open ones while it is open (running, or a service being started again).
    pub(super) fn on_job(&self, station: &str, job: &Value) {
        let (Some(id), Some(key)) = (job.get("id").and_then(Value::as_str), job.get("session").and_then(Value::as_str)) else { return };
        // Shown by itself (a service's page, jobs.rs): as it is now.
        self.sink.update(&Topic::Job { station: station.into(), id: id.into() }, &mut |shown| *shown = job.clone());
        self.sink.update(&Topic::Session { station: station.into(), key: key.into() }, &mut |detail| {
            // A station yet to list jobs with a session has none to put it in.
            let Some(jobs) = detail.get_mut("jobs").and_then(Value::as_array_mut) else { return };
            match jobs.iter().position(|j| j.get("id").and_then(Value::as_str) == Some(id)) {
                Some(i) => jobs[i] = job.clone(),
                None => jobs.insert(0, job.clone()),
            }
        });
        let open = job.get("state").and_then(Value::as_str) == Some("running")
            || (job.get("state").and_then(Value::as_str) == Some("exited") && job.get("port").is_some_and(|p| !p.is_null()));
        let topic = Topic::Jobs { station: station.into() };
        let mut unknown = false;
        self.sink.update(&topic, &mut |list| {
            let Some(list) = list.as_array_mut() else { return };
            match (list.iter().position(|j| j.get("id").and_then(Value::as_str) == Some(id)), open) {
                // What chat it is in stays as the station said.
                (Some(i), true) => {
                    let chat = list[i].get("chat").cloned();
                    list[i] = job.clone();
                    if let Some(chat) = chat {
                        list[i]["chat"] = chat;
                    }
                }
                (Some(i), false) => {
                    list.remove(i);
                }
                // A new one: which chat it is in is the station's to say.
                (None, true) => unknown = true,
                (None, false) => {}
            }
        });
        if unknown {
            self.refetch(&topic);
        }
    }
    pub(super) fn on_session_removed(&self, station: &str, key: &str) {
        self.sink.update(&Topic::Sessions { station: station.into() }, &mut |list| {
            if let Some(list) = list.as_array_mut() {
                list.retain(|s| s.get("key").and_then(Value::as_str) != Some(key));
            }
        });
        let topic = Topic::Session { station: station.into(), key: key.into() };
        if self.is_live(&topic) {
            self.sink.set(&topic, Err(CoreError::new("http_404", t!("station.core.sessionDeleted")).with_status(404)));
        }
        self.host.spawn(self.kept.forget(&Log::transcript(station, key)));
        // Its threads lose it; those left with nobody went with it.
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| {
            let Some(list) = list.as_array_mut() else { return };
            for thread in list.iter_mut() {
                if let Some(members) = thread.get_mut("sessions").and_then(Value::as_array_mut) {
                    members.retain(|m| m.get("session").and_then(Value::as_str) != Some(key));
                }
            }
            list.retain(|t| t.get("sessions").and_then(Value::as_array).is_some_and(|m| !m.is_empty()));
        });
    }
    /// A `jobLog` topic: read once; after that the station's events keep it current, or, for a station that does not
    /// follow jobs' logs (nor has said yet), it is read again now and then: soon while it grows, less often while not.
    pub(super) async fn follow_log(self: Rc<Self>, topic: Topic) {
        let Some(station) = topic.station().map(str::to_string) else { return };
        let mut wait = LOG_READ_MS;
        loop {
            let before = self.sink.get(&topic);
            self.reload(&topic).await;
            let follows = self.of(&station).stations.borrow().get(&station).and_then(|s| s.follows_logs);
            if !self.is_live(&topic) || follows == Some(true) {
                return;
            }
            wait = if self.sink.get(&topic) == before { (wait * 2).min(LOG_READ_MAX_MS) } else { LOG_READ_MS };
            self.host.sleep(wait).await;
        }
    }
}
