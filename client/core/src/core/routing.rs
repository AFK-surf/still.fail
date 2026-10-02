//! Topic routing and derived subscription values.
use super::*;

impl Source for Router {
    fn start(&self, topic: &Topic) {
        // Always kept (status.rs): only computed while shown.
        if matches!(topic, Topic::Status { .. } | Topic::Notices { .. } | Topic::Notify { .. } | Topic::PreviewLoad { .. } | Topic::Doing | Topic::AdbShare | Topic::SlackTokens { .. } | Topic::ConnectFlow { .. } | Topic::DecisionForm { .. } | Topic::ProfileFlow { .. }) {
            if let Some(core) = self.core.upgrade() {
                core.store.invalidate(topic);
            }
            return;
        }
        if let Topic::Connection { .. } = topic {
            return self.pills.start(topic);
        }
        if Choose::handles(topic) {
            return self.choose.start(topic);
        }
        // Kept on the device (data.rs) and nowhere else: what is there goes out, or, with nothing written, empty.
        if matches!(topic, Topic::Draft { .. } | Topic::Prefs) {
            if let Some(core) = self.core.upgrade() {
                core.store.invalidate(topic);
            }
            return;
        }
        if crate::jobs::Polls::owns(topic) {
            self.jobs.start(topic);
            return;
        }
        if crate::changelog::Changelog::owns(topic) {
            return self.changelog.start();
        }
        // Followed by its station (station.rs, below); what it says in words goes out fresh as it changes (jobs.rs).
        if let Topic::JobLog { .. } = topic {
            self.jobs.words(topic);
        }
        if topic.is_view() {
            let (name, station) = match topic {
                Topic::Chat { station, .. } => ("chat.open", Some(station)),
                Topic::ChatJobs { station, .. } => ("jobs.open", Some(station)),
                Topic::LongJobs { .. } => ("jobs.open", None),
                Topic::Chats { .. } => ("chats.open", None),
                Topic::ChatSearch { .. } => ("chats.search", None),
                Topic::Stations { .. } => ("stations.open", None),
                Topic::Archive { .. } => ("archive.open", None),
                Topic::Usage { .. } => ("usage.open", None),
                Topic::WorkspaceMarks { .. } => ("workspaces.marks", None),
                Topic::Decisions { .. } => ("decisions.open", None),
                Topic::AdminList { .. } | Topic::AdminItem { .. } | Topic::AdminOverview { .. } => ("admin.open", None),
                _ => ("connects.open", None),
            };
            let mut span = self.tracer.root(name, Kind::Internal);
            if let Some(station) = station {
                span.set("stillfail.station", station_id(station).to_string());
            }
            let context = span.context();
            self.opening.borrow_mut().insert(topic.clone(), span);
            // The topics it watches start now, inside the trace, and so do their first requests.
            self.tracer.enter(Some(context), || self.views.start(topic));
        } else if topic.station().is_some() {
            self.stations.start(topic);
        } else if let Some(core) = self.core.upgrade() {
            core.start_topic(topic);
        }
    }

    fn stop(&self, topic: &Topic) {
        if matches!(topic, Topic::Status { .. } | Topic::Notices { .. } | Topic::Notify { .. } | Topic::Draft { .. } | Topic::Prefs | Topic::PreviewLoad { .. } | Topic::Doing | Topic::AdbShare | Topic::SlackTokens { .. } | Topic::ConnectFlow { .. } | Topic::DecisionForm { .. } | Topic::ProfileFlow { .. }) {
            return;
        }
        if let Topic::Connection { .. } = topic {
            return self.pills.stop(topic);
        }
        if Choose::handles(topic) {
            return self.choose.stop(topic);
        }
        if crate::jobs::Polls::owns(topic) {
            return self.jobs.stop(topic);
        }
        if crate::changelog::Changelog::owns(topic) {
            return;
        }
        // Followed by its station (station.rs); what it says in words goes out fresh as it changes (jobs.rs).
        if let Topic::JobLog { .. } = topic {
            self.jobs.stop(topic);
        }
        if topic.is_view() {
            // Given up before it had a value: recorded as cancelled.
            let opening = self.opening.borrow_mut().remove(topic);
            drop(opening);
            self.views.stop(topic);
        } else if topic.station().is_some() {
            self.stations.stop(topic);
        } else if let Some(core) = self.core.upgrade() {
            core.live.borrow_mut().remove(topic);
            core.sync_sockets();
        }
    }

    fn compute(&self, topic: &Topic) -> Option<Result<Value>> {
        if let Topic::Status { workspace } = topic {
            return Some(Ok(self.status_value(workspace.as_deref())));
        }
        if let Topic::Notices { workspace } = topic {
            return Some(Ok(self.notices.value(workspace.as_deref())));
        }
        if let Topic::Notify { workspace } = topic {
            return Some(Ok(self.attend.value(workspace.as_deref())));
        }
        if let Topic::DecisionForm { .. } = topic {
            return self.core.upgrade().map(|core| core.decision_form.value(topic));
        }
        if let Topic::ProfileFlow { .. } = topic {
            return self.core.upgrade().map(|core| core.profile_flow.value(topic));
        }
        if let Topic::ConnectFlow { .. } = topic {
            return self.core.upgrade().map(|core| core.connect_flow.value(topic));
        }
        if let Topic::SlackTokens { .. } = topic {
            return self.core.upgrade().map(|core| Ok(core.slack_tokens.value(topic)));
        }
        if let Topic::PreviewLoad { station, .. } = topic {
            return Some(Ok(self.workspaces.of_station(station).preview_load.value(topic)));
        }
        if *topic == Topic::AdbShare {
            return self.core.upgrade().map(|core| Ok(core.adb.value()));
        }
        if *topic == Topic::Doing {
            // A write on a station that went quiet is being asked again (station.rs): it says so.
            let rechecking = |params: &std::collections::HashMap<String, String>| {
                params.get("station").is_some_and(|address| {
                    let place = crate::status::Place::Station(address.clone());
                    self.workspaces.of_station(address).status.waits(&place, crate::station::RECHECKING)
                })
            };
            return self.core.upgrade().map(|core| Ok(core.doing.value(&rechecking)));
        }
        if let Topic::Connection { .. } = topic {
            return self.pills.compute(topic).map(Ok);
        }
        if Choose::handles(topic) {
            return self.choose.compute(topic);
        }
        // A draft held has its record's value (data.rs); none is nothing written.
        if let Topic::Draft { .. } = topic {
            return Some(Ok(json!({ "text": "", "quotes": [], "files": [] })));
        }
        // Nothing chosen on this device yet: the defaults (the shape fills them in).
        if *topic == Topic::Prefs {
            return Some(Ok(json!({})));
        }
        if crate::changelog::Changelog::owns(topic) {
            return Some(Ok(self.changelog.value()));
        }
        let Some(context) = self.opening.borrow().get(topic).map(Span::context) else { return self.views.compute(topic).map(|v| self.attended(topic, v)) };
        // Still opening: what it starts now (a chat's agents) is part of it too.
        let value = self.tracer.enter(Some(context), || self.views.compute(topic)).map(|v| self.attended(topic, v));
        let opened = if value.is_some() { self.opening.borrow_mut().remove(topic) } else { None };
        if let Some(mut span) = opened {
            if let Some(Err(error)) = &value {
                span.fail();
                span.set("error.type", error.code.clone());
            }
            span.end();
        }
        value
    }
}

impl Router {
    /// What is waited on: of a workspace, its own waits, its account's socket and the relay opened for no station
    /// (status.rs `Take`); of none, every workspace's and all the device's.
    pub(super) fn status_value(&self, workspace: Option<&str>) -> Value {
        match workspace {
            Some(id) => {
                let of = self.workspaces.of(id);
                let owner: Vec<String> = of.owner().into_iter().collect();
                crate::status::value(&[(&*of.status, Take::All), (&*self.status, Take::For(&owner))])
            }
            None => {
                let all = self.workspaces.all();
                let mut parts: Vec<(&Status, Take)> = all.iter().map(|w| (&*w.status, Take::All)).collect();
                parts.push((&*self.status, Take::All));
                crate::status::value(&parts)
            }
        }
    }

    /// A chat as its UIs attend to it (attend.rs): its unread line; its older page loaded, or it read, when due.
    pub(super) fn attended(&self, topic: &Topic, value: Result<Value>) -> Result<Value> {
        let Topic::Chat { station, session, .. } = topic else { return value };
        let mut value = value?;
        let due = self.attend.chat(station, session.as_deref(), &mut value);
        if due.is_empty() {
            return Ok(value);
        }
        let (Some(core), Ok(addr)) = (self.core.upgrade(), StationAddr::parse(station)) else { return Ok(value) };
        let (station, me) = (station.clone(), Rc::downgrade(&core));
        core.host.spawn(async move {
            for due in due {
                let Some(core) = me.upgrade() else { return };
                let done = match due {
                    Due::Read { thread, seq } => core.stations.read(&addr, thread, seq).await,
                };
                if done.is_err() {
                    core.attend.failed(&station, &due);
                }
            }
        }.boxed_local());
        Ok(value)
    }
}

