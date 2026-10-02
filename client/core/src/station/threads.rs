//! Thread windows, persisted entries and read positions.
use super::*;

impl Stations {
    // ── threads ──

    /// Keeps entries read of a thread: with what is kept where they join it, else held loose.
    pub(super) fn keep_entries(&self, station: &str, id: u64, entries: Vec<Value>) {
        let Some(first) = entries.first().and_then(n_of) else { return };
        let (this, station) = (self.rc(), station.to_string());
        self.host.spawn(async move {
            if this.kept.join(&Log::thread(&station, id), first, entries.clone()).await {
                return;
            }
            let mut loose = this.loose.borrow_mut();
            let held = loose.entry((station, id)).or_default();
            // Far more than a window moves through: what was held goes.
            if held.len() as u64 + entries.len() as u64 > 4 * WINDOW {
                held.clear();
            }
            held.extend(entries.into_iter().filter_map(|e| Some((n_of(&e)?, e))));
        }.boxed_local());
    }
    /// Entries `from ..= to` of a thread, if all of them are on the device (kept, or held loose).
    pub(super) async fn have(&self, station: &str, id: u64, from: u64, to: u64) -> Option<Vec<Value>> {
        if from > to {
            return None;
        }
        if let Some(entries) = self.kept.range(&Log::thread(station, id), from, to).await {
            return Some(entries);
        }
        let loose = self.loose.borrow();
        let held = loose.get(&(station.to_string(), id))?;
        (from..=to).map(|n| held.get(&n).cloned()).collect()
    }
    /// Up to `count` entries just before `before`, if they are on the device: kept (as far as it goes), or held loose.
    pub(super) async fn have_before(&self, station: &str, id: u64, before: u64, count: u64) -> Option<Vec<Value>> {
        if let Some(entries) = self.kept.before(&Log::thread(station, id), before, count).await {
            return Some(entries);
        }
        self.have(station, id, before.saturating_sub(count).max(1), before.checked_sub(1)?).await
    }
    /// Opens a `thread` topic where the chat is to be read, whole from the first value on (nothing is filled in under
    /// the reader afterwards): at the first entry not read while something is unread, else where it was left (not at
    /// its end: `place`), else at its end. Then the page on either side is brought onto the device ahead.
    pub(super) async fn open_thread(&self, station: &str, id: u64) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        if self.sink.get(&topic).is_some() {
            return self.reload(&topic).await;
        }
        // Where reading stopped, as the station's list says: while it is being read (the app just opened), once it is;
        // with no list read, asked for this one.
        let threads = Topic::Threads { station: station.into() };
        let mut summary = self.summary(station, id);
        let mut waited = 0;
        while summary.is_none() && self.is_live(&threads) && self.sink.get(&threads).is_none() && self.reachable(station) && waited < LIST_WAIT_MS {
            self.host.sleep(50).await;
            waited += 50;
            summary = self.summary(station, id);
        }
        if summary.is_none()
            && self.reachable(station)
            && let Some(addr) = self.addr(station)
            && let Ok(view) = self.call(&addr, "GET", &format!("/threads/{id}"), Vec::new(), Vec::new()).await
        {
            self.put_thread(station, &view);
            summary = Some(view);
        }
        let unread = summary.as_ref().and_then(|t| t.get("unread")?.as_u64()).unwrap_or(0);
        let read = summary.as_ref().and_then(|t| t.get("read")?.as_u64());
        let place = self.place_of(station, id).await;
        let (at, offset) = match read {
            Some(read) if unread > 0 => (Some(read + 1), None),
            _ => (place.map(|p| p.at), place.and_then(|p| p.offset)),
        };
        let Some((mut value, asked)) = self.window(station, id, at).await else { return };
        // Opened where it was left: where that entry's top was, too.
        if let Some(offset) = offset
            && value.get("at").is_some()
        {
            value["atOffset"] = json!(offset);
        }
        if !self.is_live(&topic) || self.sink.get(&topic).is_some() {
            return;
        }
        self.sink.set(&topic, Ok(value));
        // Said while it was being read, kept meanwhile: onto it, as said.
        if let Some(last) = self.sink.get(&topic).filter(at_end).and_then(|v| v.get("last")?.as_u64())
            && let Some(held) = self.kept.held_of(&Log::thread(station, id)).await
            && held.last > last
            && let Some(told) = self.kept.range(&Log::thread(station, id), last + 1, held.last).await
        {
            self.put_entries(station, id, told, true);
        }
        self.ahead(station, id);
        // Opened from the device alone: what came after it is asked once.
        if !asked {
            self.confirm_end(station, id).await;
        }
    }
    /// A thread opened at its end from what the device has, asked what came after it: an event this device missed (a
    /// stream that died unnoticed while the app was away) is not told again, and the station's list it was found
    /// current by may be as old.
    pub(super) async fn confirm_end(&self, station: &str, id: u64) {
        if self.reachable(station) {
            self.reload(&Topic::Thread { station: station.into(), thread: id }).await;
        }
    }
    /// A thread's latest entry, as the station's list says (it follows its events, a moment behind), or as far as what
    /// is kept goes past it (events carry on what is kept at once); unknown while the list is not read.
    pub(super) async fn latest_known(&self, station: &str, id: u64) -> Option<u64> {
        let listed = self.summary(station, id).and_then(|t| t.get("last")?.as_u64())?;
        let kept = self.kept.held_of(&Log::thread(station, id)).await.map_or(0, |h| h.last);
        Some(listed.max(kept))
    }
    /// The window a chat shows around entry `at` (a page before it and a page from it on), or its latest page: from
    /// what is kept when all of it is and it is known to be current, else read from the station (and kept). Offline,
    /// the latest page kept is all there is. None while nothing can be had; else with whether the station was asked (what
    /// is kept, and the list it was found current by, may be behind what was said while no stream told this device).
    pub(super) async fn window(&self, station: &str, id: u64, at: Option<u64>) -> Option<(Value, bool)> {
        let log = Log::thread(station, id);
        let held = self.kept.held_of(&log).await;
        let summary = self.summary(station, id);
        let latest = self.latest_known(station, id).await;
        let (thread, title) = held.as_ref().map_or((Value::Null, Value::Null), |h| (h.thread.clone(), h.title.clone()));
        let thread = summary.clone().unwrap_or(thread);
        let reachable = self.reachable(station);
        let addr = self.addr(station).filter(|_| reachable);
        if let Some(at) = at.filter(|&at| latest.is_none_or(|l| at <= l)) {
            let from = at.saturating_sub(PAGE).max(1);
            let to = latest.map_or(at + PAGE - 1, |l| l.min(at + PAGE - 1));
            let placed = |mut value: Value| {
                value["at"] = json!(at);
                value
            };
            if let Some(latest) = latest
                && let Some(entries) = self.have(station, id, from, to).await
            {
                return Some((placed(thread_value(from, entries, thread, title, to >= latest)), false));
            }
            if let Some(addr) = &addr
                && let Ok(answer) = self.call(addr, "GET", &format!("/threads/{id}/entries?from={from}&to={to}"), Vec::new(), Vec::new()).await
            {
                let entries = entries_in(&answer, from, to);
                let last = answer.get("last").and_then(Value::as_u64).unwrap_or(to);
                if let Some(first) = entries.first().and_then(n_of) {
                    self.keep_entries(station, id, entries.clone());
                    let end = first + entries.len() as u64 > last;
                    return Some((placed(thread_value(first, entries, thread, title, end)), true));
                }
            }
        }
        // At its end.
        if let Some(h) = &held
            && latest.is_some_and(|l| l == h.last)
            && let Some((held, entries)) = self.kept.open(&log, PAGE).await
        {
            return Some((thread_value(held.first, entries, thread, title, true), false));
        }
        if let Some(addr) = &addr {
            // What came after what is kept, when that is less than a page; else the latest page.
            let near = held.as_ref().filter(|h| latest.is_none_or(|l| l.saturating_sub(h.last) < PAGE));
            let path = match near {
                Some(h) => format!("/threads/{id}/entries?after={}", h.last),
                None => format!("/threads/{id}/entries?limit={PAGE}"),
            };
            let answer = match self.call(addr, "GET", &path, Vec::new(), Vec::new()).await {
                Ok(answer) => answer,
                Err(error) => {
                    // An old link can point at a removed or inaccessible thread. Tell the chat instead of
                    // leaving its first load pending forever; transient failures can still reconnect.
                    let topic = Topic::Thread { station: station.into(), thread: id };
                    if self.is_live(&topic) && self.sink.get(&topic).is_none() && error.status.is_some_and(|s| (400..500).contains(&s)) {
                        self.sink.set(&topic, Err(error));
                    }
                    return None;
                }
            };
            {
                let mut entries = answer.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
                let last = answer.get("last").and_then(Value::as_u64).unwrap_or(0);
                if let Some(h) = near {
                    entries.retain(|e| n_of(e).is_some_and(|n| n > h.last));
                    if let Some(first) = entries.first().and_then(n_of) {
                        self.kept.write(&log, first, entries.clone(), false, summary.clone()).await;
                    }
                    let (held, kept) = self.kept.open(&log, PAGE).await?;
                    return Some((thread_value(held.first, kept, thread, title, true), true));
                }
                let first = entries.first().and_then(n_of).unwrap_or(last + 1);
                if !entries.is_empty() {
                    self.host.spawn(self.kept.write(&log, first, entries.clone(), false, summary.clone()));
                }
                return Some((thread_value(first, entries, thread, title, true), true));
            }
        }
        // Offline: its latest page kept, as it was.
        let (held, entries) = self.kept.open(&log, PAGE).await?;
        Some((thread_value(held.first, entries, thread, title, true), false))
    }
    /// What a thread shows is on the device; so is the page on either side of it, for when the reader goes on.
    pub(super) fn ahead(&self, station: &str, id: u64) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        let Some(value) = self.sink.get(&topic) else { return };
        if let Some(first) = value.get("first").and_then(Value::as_u64) {
            self.prefetch_before(station, id, first);
        }
        if !at_end(&value) && let Some(last) = value.get("last").and_then(Value::as_u64) {
            self.prefetch_after(station, id, last);
        }
    }
    /// New entries (an event, or `?after=`) onto a live thread topic, and kept. Those it has are skipped; entries
    /// past a gap wait while the gap is read. `told`: as they were said (an event, and the gap it showed), not caught
    /// up on by reading (see `thread_value`).
    pub(super) fn put_entries(&self, station: &str, id: u64, entries: Vec<Value>, told: bool) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        // A chat not shown, or its window still being read, or short of its end: what is said carries on what is kept,
        // where the window takes it from when it comes down to it (or opens).
        let value = self.sink.get(&topic);
        let Some(last) = value.as_ref().filter(|v| at_end(v)).and_then(|v| v.get("last")?.as_u64()) else {
            if told && let Some(first) = entries.first().and_then(n_of) {
                self.host.spawn(self.kept.extend(&Log::thread(station, id), first, entries));
                self.catch_up_kept(station, id, first);
            }
            return;
        };
        let fresh: Vec<Value> = entries.into_iter().filter(|e| n_of(e).is_some_and(|n| n > last)).collect();
        let Some(first) = fresh.first().and_then(n_of) else { return };
        {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(state) = stations.get_mut(station) else { return };
            if let Some(waiting) = state.gaps.get_mut(&id) {
                waiting.extend(fresh);
                return;
            }
            if first > last + 1 {
                state.gaps.insert(id, fresh);
                drop(stations);
                let (this, station) = (self.rc(), station.to_string());
                self.spawn(async move { this.fill_gap(&station, id, last + 1, first - 1).await });
                return;
            }
        }
        // The run that follows `last`; what lies past a hole in it comes after, as entries past a gap.
        let mut run: Vec<Value> = Vec::new();
        let mut past = Vec::new();
        for entry in fresh {
            match n_of(&entry) {
                Some(n) if n == last + 1 + run.len() as u64 => run.push(entry),
                Some(n) if n > last + run.len() as u64 => past.push(entry),
                _ => {}
            }
        }
        self.sink.update(&topic, &mut |value| {
            if value.get("last").and_then(Value::as_u64) != Some(last) {
                return;
            }
            if let Some(list) = value.get_mut("entries").and_then(Value::as_array_mut) {
                list.extend(run.iter().cloned());
            }
            value["last"] = json!(last + run.len() as u64);
            if !told {
                value["caught"] = value["last"].clone();
            }
        });
        self.host.spawn(self.kept.write(&Log::thread(station, id), last + 1, run, false, self.summary(station, id)));
        if !past.is_empty() {
            self.put_entries(station, id, past, told);
        }
    }
    /// Reads the entries `from ..= to` an event showed missing, then places them with those that came meanwhile.
    pub(super) async fn fill_gap(&self, station: &str, id: u64, from: u64, to: u64) {
        let addr = self.addr(station);
        let answer = match addr {
            Some(addr) => self.call(&addr, "GET", &format!("/threads/{id}/entries?from={from}&to={to}"), Vec::new(), Vec::new()).await.ok(),
            None => None,
        };
        let waiting = self.of(station).stations.borrow_mut().get_mut(station).and_then(|s| s.gaps.remove(&id)).unwrap_or_default();
        let mut entries = answer.and_then(|a| a.get("entries").and_then(Value::as_array).cloned()).unwrap_or_default();
        entries.extend(waiting);
        entries.sort_by_key(|e| n_of(e).unwrap_or(0));
        entries.dedup_by_key(|e| n_of(e));
        // A missing range is history, even when an event revealed it. Do not replay its entrance animations.
        self.put_entries(station, id, entries, false);
    }
    /// The thread's summary as a live topic lists it.
    pub(super) fn summary(&self, station: &str, id: u64) -> Option<Value> {
        let find = |list: Option<&Value>| list?.as_array()?.iter().find(|t| t.get("id").and_then(Value::as_u64) == Some(id)).cloned();
        let lists = self.live_topics(station, |t| matches!(t, Topic::Threads { .. } | Topic::Session { .. }));
        lists.iter().find_map(|topic| {
            let value = self.sink.get(topic)?;
            match topic {
                Topic::Session { .. } => find(value.get("threads")),
                _ => find(Some(&value)),
            }
        })
    }
    /// Keeps the summaries and sidebar titles of the station's open threads as the lists and rows have them now (a
    /// chat opens with them).
    pub(super) fn keep_summaries(&self, station: &str) {
        let rows = self.sink.get(&Topic::ChatRows { station: station.into() });
        for topic in self.live_topics(station, |t| matches!(t, Topic::Thread { .. })) {
            let Topic::Thread { thread, .. } = topic else { continue };
            let title = rows.as_ref().and_then(|rows| rows.as_array()?.iter().find(|r| r.get("thread").and_then(Value::as_u64) == Some(thread))?.get("title").cloned());
            let summary = self.summary(station, thread);
            if summary.is_some() || title.is_some() {
                self.host.spawn(self.kept.summary(&Log::thread(station, thread), summary, title));
            }
        }
    }
    /// A row of the viewer's sidebar, new or changed, into the station's rows.
    pub(super) fn put_row(&self, station: &str, row: &Value) {
        let Some(id) = row.get("id").and_then(Value::as_str) else { return };
        self.sink.update(&Topic::ChatRows { station: station.into() }, &mut |rows| {
            let Some(rows) = rows.as_array_mut() else { return };
            match rows.iter().position(|r| r.get("id").and_then(Value::as_str) == Some(id)) {
                Some(i) => rows[i] = row.clone(),
                None => rows.push(row.clone()),
            }
        });
        self.keep_summaries(station);
    }
    /// A thread's summary into every live topic that lists it: `threads`, and the `session` topics of the
    /// sessions taking part (a session that left it loses it).
    pub(super) fn put_thread(&self, station: &str, view: &Value) {
        let Some(id) = view.get("id").and_then(Value::as_u64) else { return };
        let members: Vec<&str> = view.get("sessions").and_then(Value::as_array).into_iter().flatten().filter_map(|m| m.get("session")?.as_str()).collect();
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| {
            if let Some(list) = list.as_array_mut() {
                upsert_thread(list, view);
            }
        });
        for topic in self.live_topics(station, |t| matches!(t, Topic::Session { .. })) {
            let Topic::Session { key, .. } = &topic else { continue };
            let member = members.contains(&key.as_str());
            self.sink.update(&topic, &mut |detail| {
                let Some(threads) = detail.get_mut("threads").and_then(Value::as_array_mut) else { return };
                if member {
                    upsert_thread(threads, view);
                } else {
                    threads.retain(|t| t.get("id").and_then(Value::as_u64) != Some(id));
                }
            });
        }
        self.keep_summaries(station);
    }
    pub(super) fn remove_thread(&self, station: &str, id: u64) {
        let drop_it = |list: &mut Value| {
            if let Some(list) = list.as_array_mut() {
                list.retain(|t| t.get("id").and_then(Value::as_u64) != Some(id));
            }
        };
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| drop_it(list));
        for topic in self.live_topics(station, |t| matches!(t, Topic::Session { .. })) {
            self.sink.update(&topic, &mut |detail| {
                if let Some(threads) = detail.get_mut("threads") {
                    drop_it(threads);
                }
            });
        }
    }
    /// The viewer read a thread up to entry `n`: its read position moves there, and nothing is unread once it
    /// covers the last entry (otherwise the count is read again).
    pub(super) fn put_read(&self, station: &str, thread: u64, n: u64) {
        let stale = std::cell::Cell::new(false);
        let apply = |list: &mut Value| {
            for t in list.as_array_mut().into_iter().flatten() {
                if t.get("id").and_then(Value::as_u64) != Some(thread) || t.get("read").and_then(Value::as_u64).is_some_and(|read| read >= n) {
                    continue;
                }
                t["read"] = json!(n);
                if t.get("last").and_then(Value::as_u64).is_none_or(|last| n >= last) {
                    t["unread"] = json!(0);
                } else {
                    stale.set(true);
                }
            }
        };
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| apply(list));
        // Its row is read once the read covers its last message; the station's `chat` event says the same.
        self.sink.update(&Topic::ChatRows { station: station.into() }, &mut |rows| {
            for row in rows.as_array_mut().into_iter().flatten() {
                if row.get("thread").and_then(Value::as_u64) == Some(thread) && row.get("last").and_then(|l| l.get("seq")?.as_u64()).is_none_or(|last| n >= last) {
                    row["unread"] = json!(false);
                }
            }
        });
        for topic in self.live_topics(station, |t| matches!(t, Topic::Session { .. })) {
            self.sink.update(&topic, &mut |detail| {
                if let Some(threads) = detail.get_mut("threads") {
                    apply(threads);
                }
            });
        }
        if stale.get() {
            self.mark_dirty(station, thread);
        }
        self.keep_summaries(station);
    }
    /// How far the viewer has read a thread, as a live topic lists it.
    pub(super) fn read_position(&self, station: &str, thread: u64) -> Option<u64> {
        let find = |list: Option<&Value>| {
            list?.as_array()?.iter().find(|t| t.get("id").and_then(Value::as_u64) == Some(thread))?.get("read")?.as_u64()
        };
        let lists = self.live_topics(station, |t| matches!(t, Topic::Threads { .. } | Topic::Session { .. }));
        lists.iter().filter_map(|topic| {
            let value = self.sink.get(topic)?;
            match topic {
                Topic::Session { .. } => find(value.get("threads")),
                _ => find(Some(&value)),
            }
        }).max()
    }
    /// Reads a thread's summary again once the burst of events is over, if a live topic lists threads.
    pub(super) fn mark_dirty(&self, station: &str, thread: u64) {
        let schedule = {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            if !s.topics.iter().any(|t| matches!(t, Topic::Threads { .. } | Topic::Session { .. })) {
                return;
            }
            s.dirty.insert(thread);
            !std::mem::replace(&mut s.flushing, true)
        };
        if schedule {
            let this = self.rc();
            let station = station.to_string();
            let sleep = self.host.sleep(EVENTS_COALESCE_MS);
            self.spawn(async move {
                sleep.await;
                this.flush_threads(&station).await;
            });
        }
    }
    pub(super) async fn flush_threads(&self, station: &str) {
        let (dirty, addr) = {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            s.flushing = false;
            (std::mem::take(&mut s.dirty), s.addr.clone())
        };
        join_all(dirty.into_iter().map(|id| {
            let addr = addr.clone();
            async move {
                match self.call(&addr, "GET", &format!("/threads/{id}"), Vec::new(), Vec::new()).await {
                    Ok(view) => self.put_thread(station, &view),
                    Err(error) if error.status == Some(404) => self.remove_thread(station, id),
                    Err(_) => {}
                }
            }
        }))
        .await;
    }
    // ── chats ──

    /// A person's message into a thread. Answers its entry number once the thread's topic, where live, holds it.
    pub async fn post(&self, station: &StationAddr, thread: u64, message: Value) -> Result<u64> {
        let answer = self.json(station, "POST", &format!("/threads/{thread}/messages"), Some(message)).await?;
        let n = answer.get("n").and_then(Value::as_u64).ok_or_else(|| CoreError::new("bad_response", t!("station.core.noMessageNumber")))?;
        let topic = Topic::Thread { station: station.to_string(), thread };
        // Sent from a window short of its end: the reader goes to the end, where it is.
        if self.sink.get(&topic).is_some_and(|v| !at_end(&v)) {
            let _ = self.latest(station, thread).await;
        }
        if self.sink.get(&topic).and_then(|v| v.get("last")?.as_u64()).is_some_and(|last| last < n) {
            self.reload(&topic).await;
        }
        Ok(n)
    }
    /// The page of entries before those loaded, into the thread's topic: from what is kept, else from the station
    /// (and kept). Answers whether still older ones exist.
    pub async fn older(&self, station: &StationAddr, thread: u64) -> Result<bool> {
        let name = station.to_string();
        let topic = Topic::Thread { station: name.clone(), thread };
        let Some(before) = self.sink.get(&topic).and_then(|v| v.get("first")?.as_u64()) else { return Ok(false) };
        if before <= 1 {
            return Ok(false);
        }
        let older = match self.have_before(&name, thread, before, PAGE).await {
            Some(older) => older,
            None => {
                let page = self.json(station, "GET", &format!("/threads/{thread}/entries?before={before}&limit={PAGE}"), None).await?;
                let older: Vec<Value> = page.get("entries").and_then(Value::as_array).into_iter().flatten().filter(|e| n_of(e).is_some_and(|n| n < before)).cloned().collect();
                self.keep_entries(&name, thread, older.clone());
                older
            }
        };
        let Some(first) = older.first().and_then(n_of) else { return Ok(false) };
        let mut still = false;
        self.sink.update(&topic, &mut |value| {
            let loaded = value.get("first").and_then(Value::as_u64);
            // Another page came first: this one is not next to what is loaded any more.
            if loaded != Some(before) || older.len() as u64 != before - first {
                still = loaded.is_some_and(|f| f > 1);
                return;
            }
            let Some(list) = value.get_mut("entries").and_then(Value::as_array_mut) else { return };
            list.splice(0..0, older.iter().cloned());
            // As many go at the other end: the window is short of its end from then on.
            let over = list.len().saturating_sub(WINDOW as usize);
            if over > 0 {
                list.truncate(WINDOW as usize);
                let last = first + WINDOW - 1;
                value["last"] = json!(last);
                value["end"] = json!(false);
            }
            value["first"] = json!(first);
            still = first > 1;
        });
        // A page ahead again, for the next time.
        if still {
            self.prefetch_before(&name, thread, first);
        }
        Ok(still)
    }
    /// The page of entries after those loaded, into the thread's topic: from what is kept, else from the station (and
    /// kept); as many go at its start. Answers whether still newer ones exist (the window is short of the end).
    pub async fn newer(&self, station: &StationAddr, thread: u64) -> Result<bool> {
        let name = station.to_string();
        let topic = Topic::Thread { station: name.clone(), thread };
        let Some(value) = self.sink.get(&topic) else { return Ok(false) };
        if at_end(&value) {
            return Ok(false);
        }
        let Some(after) = value.get("last").and_then(Value::as_u64) else { return Ok(false) };
        let latest = self.latest_known(&name, thread).await;
        let (from, to) = (after + 1, after + PAGE);
        let have = match latest {
            Some(latest) => self.have(&name, thread, from, latest.min(to)).await,
            None => None,
        };
        let (newer, last) = match have {
            Some(newer) => (newer, latest.unwrap_or(to)),
            None => {
                let answer = self.json(station, "GET", &format!("/threads/{thread}/entries?from={from}&to={to}"), None).await?;
                let newer = entries_in(&answer, from, to);
                self.keep_entries(&name, thread, newer.clone());
                (newer, answer.get("last").and_then(Value::as_u64).unwrap_or(to))
            }
        };
        let mut still = false;
        self.sink.update(&topic, &mut |value| {
            // Another page came first: this one does not follow what is loaded any more.
            if value.get("last").and_then(Value::as_u64) != Some(after) || at_end(value) {
                still = !at_end(value);
                return;
            }
            let Some(list) = value.get_mut("entries").and_then(Value::as_array_mut) else { return };
            list.extend(newer.iter().cloned());
            let over = list.len().saturating_sub(WINDOW as usize);
            list.drain(..over);
            let first = value.get("first").and_then(Value::as_u64).unwrap_or(1) + over as u64;
            let now = after + newer.len() as u64;
            value["first"] = json!(first);
            value["last"] = json!(now);
            // Read, not said: it shows at once.
            value["caught"] = json!(now);
            value["end"] = json!(now >= last);
            still = now < last;
        });
        if still {
            self.prefetch_after(&name, thread, after + newer.len() as u64);
        }
        Ok(still)
    }
    /// The thread's latest page in place of its window (the reader goes to its end), read as `open_thread` reads it.
    pub async fn latest(&self, station: &StationAddr, thread: u64) -> Result<()> {
        let name = station.to_string();
        let topic = Topic::Thread { station: name.clone(), thread };
        if self.sink.get(&topic).is_some_and(|v| at_end(&v)) {
            return Ok(());
        }
        let (value, asked) = self.window(&name, thread, None).await.ok_or_else(|| CoreError::new("offline", t!("station.core.offline")))?;
        if self.is_live(&topic) {
            self.sink.set(&topic, Ok(value));
            self.ahead(&name, thread);
            if !asked {
                self.confirm_end(&name, thread).await;
            }
        }
        Ok(())
    }
    /// Where the reader leaves a chat: at entry `at`, short of its end (it opens there next, while nothing is unread),
    /// its top `offset` below the top of the list, or at its end (none). Kept on the device as well.
    pub fn place(&self, station: &str, thread: u64, at: Option<u64>, offset: Option<f64>) {
        let place = at.map(|at| LeftAt { at, offset: offset.filter(|o| o.is_finite()) });
        let was = self.places.borrow_mut().insert((station.to_string(), thread), place);
        if was == Some(place) {
            return;
        }
        // What is written is the latest: a write that finishes after a later one does not put an older place back.
        let (this, station) = (self.rc(), station.to_string());
        self.host.spawn(
            async move {
                let Some(place) = this.places.borrow().get(&(station.clone(), thread)).copied() else { return };
                let key = place_key(&station, thread);
                let _ = match place {
                    Some(p) => this.host.storage_set(&key, serde_json::to_vec(&json!({ "at": p.at, "offset": p.offset })).unwrap_or_default()).await,
                    None => this.host.storage_delete(&key).await,
                };
            }
            .boxed_local(),
        );
    }
    /// Where a chat was left (`place`): as told since this core started, else as kept on the device.
    pub(super) async fn place_of(&self, station: &str, thread: u64) -> Option<LeftAt> {
        let key = (station.to_string(), thread);
        if let Some(place) = self.places.borrow().get(&key) {
            return *place;
        }
        let kept = self.host.storage_get(&place_key(station, thread)).await.ok().flatten().and_then(|bytes| {
            let v: Value = serde_json::from_slice(&bytes).ok()?;
            Some(LeftAt { at: v.get("at")?.as_u64()?, offset: v.get("offset").and_then(Value::as_f64) })
        });
        // Told meanwhile: that is newer.
        *self.places.borrow_mut().entry(key).or_insert(kept)
    }
    /// Measures the ways to the station now (its card's 重新测量); its `net` topic shows what was found.
    pub async fn measure(&self, station: &StationAddr) -> Result<()> {
        self.wire.measure(station).await
    }
    /// The page of a session's transcript before what its `live` topic has, into it: from what is kept, else from the
    /// station (and kept). Answers whether still older entries exist.
    pub async fn history_older(&self, station: &StationAddr, key: &str) -> Result<bool> {
        let name = station.to_string();
        let topic = Topic::Live { station: name.clone(), key: key.to_string() };
        let log = Log::transcript(&name, key);
        let Some(before) = self.sink.get(&topic).map(|v| first_of(&v)) else { return Ok(false) };
        if before == 0 {
            return Ok(false);
        }
        let older = match self.kept.before(&log, before, TRANSCRIPT_PAGE).await {
            Some(older) => older,
            None => {
                let page = self.json(station, "GET", &format!("/sessions/{}/timeline?before={before}&limit={TRANSCRIPT_PAGE}", encode(key)), None).await?;
                let start = page.get("start").and_then(Value::as_u64).unwrap_or(0);
                let older: Vec<Value> = page.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
                // None, or not the entries just before (the transcript was written anew meanwhile: the stream says).
                if older.is_empty() || start + older.len() as u64 != before {
                    return Ok(false);
                }
                self.host.spawn(self.kept.write(&log, start, older.clone(), false, None));
                older
            }
        };
        let first = before - older.len() as u64;
        let mut still = false;
        self.sink.update(&topic, &mut |live| {
            let loaded = first_of(live);
            // Another page came first, or the timeline started anew: this one is not next to it any more.
            if loaded != before {
                still = loaded > 0;
                return;
            }
            let Some(timeline) = live.get_mut("timeline").and_then(Value::as_array_mut) else { return };
            timeline.splice(0..0, older.iter().cloned());
            live["first"] = json!(first);
            still = first > 0;
        });
        Ok(still)
    }
    /// Keeps a page ahead of what a thread shows: the page before entry `before`, brought onto the device if it is not
    /// there, so the next `older` has it at once. Nothing when the thread starts there, or its station is offline.
    pub(super) fn prefetch_before(&self, station: &str, thread: u64, before: u64) {
        if before <= 1 || !self.reachable(station) {
            return;
        }
        let Ok(addr) = StationAddr::parse(station) else { return };
        let (this, name) = (self.rc(), station.to_string());
        self.spawn(async move {
            if this.have_before(&name, thread, before, PAGE).await.is_some() {
                return;
            }
            let Ok(page) = this.json(&addr, "GET", &format!("/threads/{thread}/entries?before={before}&limit={PAGE}"), None).await else { return };
            let older: Vec<Value> = page.get("entries").and_then(Value::as_array).into_iter().flatten().filter(|e| n_of(e).is_some_and(|n| n < before)).cloned().collect();
            this.keep_entries(&name, thread, older);
        });
    }
    /// Keeps a page ahead after what a thread shows, as `prefetch_before` does before it.
    pub(super) fn prefetch_after(&self, station: &str, thread: u64, after: u64) {
        if !self.reachable(station) {
            return;
        }
        let Ok(addr) = StationAddr::parse(station) else { return };
        let (this, name) = (self.rc(), station.to_string());
        self.spawn(async move {
            let latest = this.latest_known(&name, thread).await;
            let to = latest.map_or(after + PAGE, |l| l.min(after + PAGE));
            if to <= after || this.have(&name, thread, after + 1, to).await.is_some() {
                return;
            }
            let Ok(page) = this.json(&addr, "GET", &format!("/threads/{thread}/entries?from={}&to={}", after + 1, after + PAGE), None).await else { return };
            this.keep_entries(&name, thread, entries_in(&page, after + 1, after + PAGE));
        });
    }
    /// Records how far the viewer has read a thread (an entry number); nothing is sent when it is read that far
    /// already.
    pub async fn read(&self, station: &StationAddr, thread: u64, n: u64) -> Result<()> {
        let name = station.to_string();
        if self.read_position(&name, thread).is_some_and(|read| read >= n) {
            return Ok(());
        }
        let answer = self.json(station, "PUT", &format!("/threads/{thread}/read"), Some(json!({ "n": n }))).await?;
        self.put_read(&name, thread, answer.get("n").and_then(Value::as_u64).unwrap_or(n));
        Ok(())
    }
    // ── live ──

    /// One message of the live stream into the topic; false when its entries leave a gap.
    pub(super) fn on_live(&self, station: &str, key: &str, message: &Value) -> bool {
        let topic = Topic::Live { station: station.into(), key: key.into() };
        let now = self.host.now_ms();
        let kind = message.get("type").and_then(Value::as_str).unwrap_or("");
        let mut entries_came = false;
        if kind == "timeline" {
            let start = message.get("start").and_then(Value::as_u64).unwrap_or(0);
            let entries = message.get("entries").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();
            let mut placed = false;
            self.sink.update(&topic, &mut |live| {
                let first = first_of(live);
                let Some(timeline) = live.get_mut("timeline").and_then(Value::as_array_mut) else { return };
                if (first..=first + timeline.len() as u64).contains(&start) {
                    timeline.truncate((start - first) as usize);
                    timeline.extend(entries.iter().cloned());
                } else {
                    // Not next to what is here: past it (only the latest page was sent), or before it (the transcript
                    // written anew): these start the timeline.
                    *timeline = entries.to_vec();
                    live["first"] = json!(start);
                }
                live["usage"] = message.get("usage").cloned().unwrap_or(Value::Null);
                placed = true;
            });
            if !placed {
                return false;
            }
            self.host.spawn(self.kept.write(&Log::transcript(station, key), start, entries.to_vec(), true, None));
            entries_came = !entries.is_empty();
        }
        let view = {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(view) = stations.get_mut(station).and_then(|s| s.lives.get_mut(key)) else { return true };
            match kind {
                // Ended steps stay until the entries that record them arrive.
                "timeline" if entries_came => view.steps.retain(|s| s.get("ended") != Some(&Value::Bool(true))),
                "steps" => {
                    view.steps = message.get("steps").and_then(Value::as_array).cloned().unwrap_or_default();
                    view.phase = message.get("phase").filter(|p| !p.is_null()).map(|p| {
                        let elapsed = p.get("elapsedMs").and_then(Value::as_f64).unwrap_or(0.0);
                        json!({ "phase": p.get("phase").cloned().unwrap_or(Value::Null), "since": (now - elapsed).round() as i64 })
                    });
                }
                "clear" => *view = LiveView::default(),
                // How fast the model writes now; the rest of the view is as it was.
                "rate" => {}
                "step" => {
                    let Some(event) = message.get("event") else { return true };
                    apply_step(view, event, now);
                }
                _ => return true,
            }
            view.clone()
        };
        let rate = message.get("tokensPerSecond").and_then(Value::as_u64);
        self.sink.update(&topic, &mut |live| {
            live["steps"] = json!(view.steps);
            live["phase"] = json!(view.phase);
            match kind {
                "rate" => live["rate"] = json!(rate.unwrap_or(0)),
                // Writing stops with the step or the turn; the rate comes again with more output.
                "clear" => live["rate"] = json!(0),
                _ => {}
            }
            // What the chat shows of it (activity.rs), from all of the above.
            live["activity"] = crate::activity::present(live);
            // The stream sends the steps right after the entries it has: the transcript is all here.
            if kind == "steps" {
                live["loaded"] = json!(true);
            }
        });
        true
    }
}
