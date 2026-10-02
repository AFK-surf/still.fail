//! The Slack connection wizard, shared by desktop, phone web and Android. Only rendering and
//! native file/browser actions remain in the views. Drafts (including tokens) never enter Data.
use crate::{
    choose::Choose,
    error::{CoreError, Result},
    protocol::{ClientId, Topic},
    store::{Store, Watch},
};
use serde_json::{json, Value};
use stillfail_i18n::t;
use std::{
    cell::{Cell, RefCell},
    collections::HashMap,
    rc::Rc,
};

struct Draft {
    owner: ClientId,
    generation: u64,
    pending: bool,
    value: Value,
    _watches: Vec<Watch>,
}
pub struct Flows {
    store: Rc<Store>,
    choose: Rc<Choose>,
    drafts: RefCell<HashMap<Topic, Draft>>,
    next: Cell<u64>,
}
pub fn pick(station: &str, form: &str) -> Topic {
    Topic::Pick {
        station: station.into(),
        of: format!("connect-new:{form}"),
    }
}
pub fn tokens(station: &str, form: &str) -> Topic {
    Topic::SlackTokens {
        station: station.into(),
        form: form.into(),
    }
}
fn address(topic: &Topic) -> (&str, &str) {
    let Topic::ConnectFlow { station, form } = topic else {
        unreachable!()
    };
    (station, form)
}
fn initial(input: &Value) -> Value {
    let name = crate::brand::name();
    json!({"step":if input["resume"].is_string() {"install"} else {"team"}, "resume":input["resume"], "mobile":input["mobile"] == true,
        "team":null, "adding":false, "settings":{"name":name,"displayName":name,"description":format!("Coding agent in your threads ({name})"),"longDescription":"","backgroundColor":"#F3E3D3",
        "groups":{"base":true,"public":true,"dm":true,"customize":true,"files":true,"reactions":true,"channels":true,"people":true,"extras":true,"canvases":true,"lists":true,"topics":true,"usergroups":true,"search":true,"connect":true,"more":true}},
        "icon":null,"iconError":null,"madeId":input["resume"],"config":"","mode":"multi-session","requireMention":true})
}
impl Flows {
    pub fn new(store: Rc<Store>, choose: Rc<Choose>) -> Self {
        Self {
            store,
            choose,
            drafts: RefCell::default(),
            next: Cell::new(0),
        }
    }
    pub fn open(&self, topic: &Topic, owner: ClientId, input: &Value) -> Result<()> {
        if let Some(draft) = self.drafts.borrow().get(topic) {
            return if draft.owner == owner {
                Ok(())
            } else {
                Err(CoreError::invalid(t!("core-misc.connect.not_yours")))
            };
        }
        let (station, form) = address(topic);
        let sources = [
            Topic::Overview {
                station: station.into(),
            },
            pick(station, form),
            tokens(station, form),
        ];
        let watches = sources
            .iter()
            .map(|source| {
                let (store, target) = (Rc::downgrade(&self.store), topic.clone());
                self.store.watch(
                    source,
                    Rc::new(move || {
                        if let Some(store) = store.upgrade() {
                            store.invalidate(&target);
                        }
                    }),
                )
            })
            .collect();
        self.next.set(self.next.get() + 1);
        self.drafts.borrow_mut().insert(
            topic.clone(),
            Draft {
                owner,
                generation: self.next.get(),
                pending: false,
                value: initial(input),
                _watches: watches,
            },
        );
        self.store.invalidate(topic);
        Ok(())
    }
    pub fn drop(&self, topic: &Topic, owner: ClientId) {
        let removed = {
            let mut drafts = self.drafts.borrow_mut();
            if drafts.get(topic).is_some_and(|d| d.owner == owner) {
                drafts.remove(topic)
            } else {
                None
            }
        };
        if removed.is_some() {
            let (station, form) = address(topic);
            let _ = self.choose.set(
                station,
                &format!("connect-new:{form}"),
                &json!({"clear":true}),
            );
        }
        drop(removed);
        self.store.invalidate(topic);
    }
    pub fn disconnect(&self, owner: ClientId) {
        let topics: Vec<_> = self
            .drafts
            .borrow()
            .iter()
            .filter(|(_, d)| d.owner == owner)
            .map(|(t, _)| t.clone())
            .collect();
        for t in topics {
            self.drop(&t, owner);
        }
    }
    pub fn edit(&self, topic: &Topic, owner: ClientId, patch: &Value) -> Result<()> {
        let mut drafts = self.drafts.borrow_mut();
        let d = drafts
            .get_mut(topic)
            .filter(|d| d.owner == owner)
            .ok_or_else(|| CoreError::invalid(t!("core-misc.connect.closed")))?;
        if d.pending {
            return Err(CoreError::invalid(t!("core-misc.connect.busy")));
        }
        if let Some(settings) = patch.get("settings") {
            serde_json::from_value::<stillfail_shapes::ConnectAppSettings>(settings.clone())
                .map_err(|e| CoreError::invalid(t!("core-misc.connect.bad_settings", error = e)))?;
        }
        for field in ["team", "icon", "iconError"] {
            if patch
                .get(field)
                .is_some_and(|v| !v.is_null() && !v.is_string())
            {
                return Err(CoreError::invalid(t!("core-misc.params.not_text")));
            }
        }
        if patch.get("config").is_some_and(|v| !v.is_string()) {
            return Err(CoreError::invalid(t!("core-misc.connect.config_not_text")));
        }
        for field in ["adding", "requireMention"] {
            if patch.get(field).is_some_and(|v| !v.is_boolean()) {
                return Err(CoreError::invalid(t!("core-misc.params.not_bool")));
            }
        }
        if patch
            .get("mode")
            .is_some_and(|v| v != "single-session" && v != "multi-session")
        {
            return Err(CoreError::invalid(t!("core-misc.connect.no_such_mode")));
        }
        for field in [
            "team",
            "adding",
            "settings",
            "icon",
            "iconError",
            "config",
            "mode",
            "requireMention",
        ] {
            if let Some(v) = patch.get(field) {
                d.value[field] = v.clone();
            }
        }
        if let Some(config) = patch["config"].as_str() {
            d.value["config"] = json!(config.trim());
        }
        drop(drafts);
        self.store.invalidate(topic);
        Ok(())
    }
    pub fn go(&self, topic: &Topic, owner: ClientId, to: &str) -> Result<Value> {
        let view = self.value(topic)?;
        let target = if to == "back" {
            view["back"].as_str().unwrap_or("close")
        } else {
            to
        };
        if target == "close" {
            return Ok(json!({"close":true}));
        }
        let step = view["step"].as_str().unwrap_or("team");
        let allowed = to == "back"
            || match (step, target) {
                ("team", "token" | "manual") => true,
                ("team", "app") => !view["chosen"].is_null(),
                ("app" | "manual", "team") => true,
                ("bind", "install" | "manual") => true,
                _ => false,
            };
        if !allowed {
            return Err(CoreError::invalid(t!("core-misc.connect.not_ready")));
        }
        let mut drafts = self.drafts.borrow_mut();
        let d = drafts
            .get_mut(topic)
            .filter(|d| d.owner == owner)
            .ok_or_else(|| CoreError::invalid(t!("core-misc.connect.closed")))?;
        if d.pending {
            return Err(CoreError::invalid(t!("core-misc.connect.busy")));
        }
        d.value["step"] = json!(target);
        drop(drafts);
        self.store.invalidate(topic);
        Ok(json!({}))
    }
    pub fn value(&self, topic: &Topic) -> Result<Value> {
        let mut v = self
            .drafts
            .borrow()
            .get(topic)
            .map(|d| d.value.clone())
            .ok_or_else(|| CoreError::invalid(t!("core-misc.connect.closed")))?;
        let (station, form) = address(topic);
        let overview = self.store.get(&Topic::Overview {
            station: station.into(),
        });
        let teams = overview
            .as_ref()
            .and_then(|o| o["slackTeams"].as_array())
            .cloned()
            .unwrap_or_default();
        let chosen = teams
            .iter()
            .find(|t| t["teamId"] == v["team"])
            .or_else(|| {
                if teams.len() == 1 {
                    teams.first()
                } else {
                    None
                }
            })
            .cloned()
            .unwrap_or(Value::Null);
        let made = overview
            .as_ref()
            .and_then(|o| o["slackApps"].as_array())
            .and_then(|apps| apps.iter().find(|a| a["appId"] == v["madeId"]))
            .cloned()
            .unwrap_or(Value::Null);
        let picked = self
            .choose
            .compute(&pick(station, form))
            .transpose()?
            .unwrap_or(Value::Null);
        let step = v["step"].as_str().unwrap_or("team").to_string();
        let mobile = v["mobile"] == true;
        let title = match step.as_str() {
            "team" if !mobile && teams.is_empty() => "core-misc.connect.title.get_token",
            "team" if !mobile && v["adding"] == true => "core-misc.connect.title.add_token",
            "team" => "core-misc.connect.title.team",
            "token" => "core-misc.connect.title.token",
            "app" => "core-misc.connect.title.app",
            "install" => "core-misc.connect.title.install",
            "manual" => "core-misc.connect.title.manual",
            _ => "core-misc.connect.title.bind",
        };
        let order = if step == "manual" || (step == "bind" && v["madeId"].is_null()) {
            vec!["manual", "bind"]
        } else {
            vec!["team", "app", "install", "bind"]
        };
        let back = match step.as_str() {
            "team" => "close",
            "token" | "app" | "manual" => "team",
            "install" if v["resume"].is_string() => "close",
            "install" => "app",
            _ if v["madeId"].is_string() => "install",
            _ => "manual",
        };
        v["title"] = json!(t!(title));
        v["back"] = json!(back);
        v["number"] = json!(order
            .iter()
            .position(|x| *x == step)
            .map(|i| i + 1)
            .unwrap_or(1));
        v["total"] = json!(order.len());
        v["gettingToken"] =
            json!(step == "team" && !mobile && (teams.is_empty() || v["adding"] == true));
        v["noProfile"] = json!(
            v["resume"].is_null()
                && overview
                    .as_ref()
                    .is_some_and(|o| o["profiles"].as_array().is_some_and(Vec::is_empty))
        );
        v["configReady"] = json!(v["config"]
            .as_str()
            .is_some_and(|s| s.starts_with("xoxe-1-") && s.len() > 20));
        v["configError"] = if v["config"]
            .as_str()
            .is_some_and(|s| s.starts_with("xoxe.xoxp-"))
        {
            json!(t!("core-misc.connect.access_token"))
        } else {
            Value::Null
        };
        v["canMake"] = json!(
            !chosen.is_null()
                && v["settings"]["name"]
                    .as_str()
                    .is_some_and(|s| !s.trim().is_empty())
        );
        v["canCreate"] = json!(!picked["valueOption"].is_null());
        v["teams"] = json!(teams);
        v["chosen"] = chosen;
        v["made"] = made;
        v["pick"] = picked;
        Ok(v)
    }
    /// Capture one operation. Its result can advance only this instance; closing/reopening never adopts an old answer.
    pub fn begin(
        &self,
        topic: &Topic,
        owner: ClientId,
        action: &str,
        token_input: &Value,
        verified: bool,
    ) -> Result<(u64, &'static str, Value)> {
        let v = self.value(topic)?;
        let (station, _) = address(topic);
        let step = v["step"].as_str().unwrap_or("");
        let (name, mut p) = match action {
            "config"
                if (step == "token" || v["gettingToken"] == true) && v["configReady"] == true =>
            {
                ("slack.addConfigToken", json!({"refreshToken":v["config"]}))
            }
            "make" if step == "app" && v["canMake"] == true => (
                "slack.makeApp",
                json!({"team":v["chosen"]["teamId"],"settings":v["settings"],"icon":v["icon"]}),
            ),
            "verify" if step == "install" || step == "manual" => {
                let mut p = token_input.clone();
                p["install"] = v["made"]["state"].clone();
                ("slack.verify", p)
            }
            "create" if step == "bind" && v["canCreate"] == true && verified => {
                let mut slack = token_input.clone();
                if v["made"]["state"].is_string() {
                    slack =
                        json!({"appToken":token_input["appToken"],"install":v["made"]["state"]});
                } else if v["made"]["appId"].is_string() {
                    slack["appId"] = v["made"]["appId"].clone();
                }
                let mut bind = v["pick"]["value"].clone();
                for f in ["model", "effort"] {
                    if bind[f].is_null() {
                        bind[f] = json!("");
                    }
                }
                (
                    "connect.create",
                    json!({"input":{"kind":"slack","mode":v["mode"],"requireMention":v["requireMention"],"bind":bind,"slack":slack}}),
                )
            }
            _ => return Err(CoreError::invalid(t!("core-misc.connect.not_ready"))),
        };
        p["station"] = json!(station);
        let mut drafts = self.drafts.borrow_mut();
        let d = drafts
            .get_mut(topic)
            .filter(|d| d.owner == owner)
            .ok_or_else(|| CoreError::invalid(t!("core-misc.connect.closed")))?;
        if d.pending {
            return Err(CoreError::invalid(t!("core-misc.connect.working")));
        }
        d.pending = true;
        Ok((d.generation, name, p))
    }
    pub fn finish(
        &self,
        topic: &Topic,
        generation: u64,
        action: &str,
        result: &Result<Value>,
    ) -> bool {
        let mut drafts = self.drafts.borrow_mut();
        let Some(d) = drafts.get_mut(topic).filter(|d| d.generation == generation) else {
            return false;
        };
        d.pending = false;
        if let Ok(r) = result {
            match action {
                "config" => {
                    d.value["team"] = r["teamId"].clone();
                    d.value["config"] = json!("");
                    d.value["adding"] = json!(false);
                    d.value["step"] = json!("app");
                }
                "make" => {
                    d.value["madeId"] = r["appId"].clone();
                    d.value["iconError"] = r["iconError"].clone();
                    d.value["step"] = json!("install");
                }
                "create" => d.value["step"] = json!("done"),
                "verify"
                    if !r["identity"].is_null()
                        && r["errors"].as_array().is_some_and(Vec::is_empty) =>
                {
                    d.value["step"] = json!("bind")
                }
                _ => {}
            }
        }
        drop(drafts);
        self.store.invalidate(topic);
        true
    }
}
