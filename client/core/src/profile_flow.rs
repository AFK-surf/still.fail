//! The add-profile pages, shared by desktop, phone web and Android: the picker of providers (Cue's groups and order,
//! providers.rs), how to connect what was picked (a plan to sign in, or a key), and the form with what the profile will
//! be usable for. What is picked, typed and shown lives here (a key never enters the data kept on the device); the views
//! draw it and name what changed (`profile.flow.edit`), and `profile.flow.submit` adds the profile.
use std::{cell::RefCell, collections::HashMap, rc::Rc};

use serde_json::{Value, json};
use stillfail_i18n::t;
use stillfail_shapes::{
    AccessKind,
    providers::{self, GROUPS, SOURCES},
};

use crate::{
    error::{CoreError, Result},
    protocol::{ClientId, Topic},
    store::{Store, Watch},
};

struct Draft {
    owner: ClientId,
    value: Value,
    pending: bool,
    _watch: Watch,
}

pub struct Flows {
    store: Rc<Store>,
    drafts: RefCell<HashMap<Topic, Draft>>,
}

fn station_of(topic: &Topic) -> &str {
    let Topic::ProfileFlow { station, .. } = topic else { unreachable!() };
    station
}

fn names(uses: &providers::Uses) -> Vec<&'static str> {
    [(uses.claude, "claude"), (uses.codex, "codex"), (uses.decision, "decision")].into_iter().filter(|(on, _)| *on).map(|(_, id)| id).collect()
}

fn uses_text(ids: &[&str]) -> String {
    ids.iter()
        .map(|u| match *u {
            "claude" => t!("core-views.present.uses.claude"),
            "codex" => t!("core-views.present.uses.codex"),
            _ => t!("core-views.present.uses.decision"),
        })
        .collect::<Vec<_>>()
        .join(" · ")
}

fn runtime_name(runtime: &str) -> &'static str {
    if runtime == "claude" { "Claude Code" } else { "Codex" }
}

/// What a source can do, at the address and protocol given (an example address where none is yet).
fn uses_of(source: &providers::Source, endpoint: Option<&str>, protocol: Option<&str>) -> Vec<&'static str> {
    let own = source.endpoint_required.then(|| endpoint.map(String::from).or_else(|| providers::example(source.id).map(String::from))).flatten();
    let protocol = protocol.or_else(|| source.protocols.first().map(|p| p.id()));
    providers::endpoints(source, own.as_deref(), protocol.filter(|_| source.endpoint_required)).map(|at| names(&providers::uses(&at))).unwrap_or_default()
}

fn tile_of(source: &providers::Source, has_key: bool, has_plan: bool) -> Value {
    let kind = match source.legacy {
        Some(AccessKind::OpencodeGo) => "opencode-go",
        Some(AccessKind::AnthropicApi) => "anthropic-api",
        _ => "api-provider",
    };
    let runtime = match source.id {
        "openai" => Some("codex"),
        "anthropic" => Some("claude"),
        _ => None,
    };
    let uses = uses_of(source, None, None);
    json!({
        "id": source.id, "name": source.name, "group": source.group.id(), "mark": source.mark, "kind": kind,
        "hasKey": has_key, "hasPlan": has_plan, "runtime": runtime,
        "endpointRequired": source.endpoint_required, "endpointExample": providers::example(source.id),
        "protocols": source.protocols.iter().map(|p| p.id()).collect::<Vec<_>>(),
        "keyOptional": source.key_optional, "uses": uses, "usesText": uses_text(&uses),
    })
}

/// The picker's groups: every provider the station can take a key for, those with a plan (ChatGPT, Claude) as ever, then
/// the variables set by hand. `supported`: the ids the station lists (none from a station older than the list: only
/// what it had before it).
pub fn groups(supported: Option<&[String]>) -> Vec<Value> {
    let listed = |id: &str| supported.is_some_and(|s| s.iter().any(|x| x == id));
    let mut out: Vec<Value> = Vec::new();
    for group in GROUPS {
        let mut tiles: Vec<Value> = SOURCES
            .iter()
            .filter(|s| s.group == group)
            .filter_map(|s| {
                let has_key = s.legacy.is_some() || listed(s.id);
                let has_plan = matches!(s.id, "openai" | "anthropic");
                (has_key || has_plan).then(|| tile_of(s, has_key, has_plan))
            })
            .collect();
        if group == providers::Group::Local {
            for runtime in ["claude", "codex"] {
                let uses = if runtime == "claude" { vec!["claude"] } else { vec!["codex"] };
                tiles.push(json!({
                    "id": format!("env-{runtime}"), "name": t!("core-views.flow.env", runtime = runtime_name(runtime)), "group": "local", "kind": "env",
                    "hasKey": false, "hasPlan": false, "runtime": runtime, "endpointRequired": false, "protocols": [], "keyOptional": true,
                    "uses": uses, "usesText": uses_text(&uses),
                }));
            }
        }
        if !tiles.is_empty() {
            let title = t!(&format!("core-views.flow.group.{}", group.id()));
            out.push(json!({ "id": group.id(), "title": title, "providers": tiles }));
        }
    }
    out
}

fn supported(overview: &Value) -> Option<Vec<String>> {
    overview.get("apiProviders").and_then(Value::as_array).map(|list| list.iter().filter_map(|p| p["id"].as_str().map(String::from)).collect())
}

fn find<'a>(groups: &'a [Value], id: &str) -> Option<&'a Value> {
    groups.iter().flat_map(|g| g["providers"].as_array().into_iter().flatten()).find(|p| p["id"] == id)
}

/// A draft's value as the views draw it.
fn view(station: &str, draft: &Value, overview: &Value) -> Value {
    let groups = groups(supported(overview).as_deref());
    let tile = draft["provider"].as_str().and_then(|id| find(&groups, id)).cloned();
    let method = draft["method"].as_str().filter(|m| !m.is_empty()).map(String::from);
    let mut out = json!({
        "step": "pick", "station": station, "title": t!("core-views.flow.pick"), "hint": t!("core-views.flow.pick_hint"),
        "groups": groups, "tile": tile, "method": method, "choices": [], "showEndpoint": false, "endpoint": draft["endpoint"],
        "protocols": [], "showKey": false, "key": draft["key"], "keyLabel": "", "canSubmit": false, "pending": draft["pending"] == true,
        "submitLabel": "", "usesLine": "", "error": draft["error"],
    });
    let Some(tile) = tile else { return out };
    let name = tile["name"].as_str().unwrap_or("").to_string();
    out["title"] = json!(t!("core-views.flow.connect", name = name));
    out["hint"] = json!("");
    let (has_key, has_plan) = (tile["hasKey"] == true, tile["hasPlan"] == true);
    let runtime = tile["runtime"].as_str().unwrap_or("claude");
    // A vendor with both a plan and a key asks which first.
    let Some(method) = method else {
        let plan = if runtime == "claude" { "Claude" } else { "ChatGPT" };
        out["step"] = json!("method");
        out["choices"] = json!([
            { "id": "plan", "title": t!("core-views.flow.plan", plan = plan), "hint": t!(&format!("core-views.flow.plan_hint.{runtime}")) },
            { "id": "key", "title": t!("core-views.flow.key_card"), "hint": t!("core-views.flow.key_card_hint", name = name) },
        ]);
        let _ = (has_key, has_plan);
        return out;
    };
    out["step"] = json!("connect");
    let kind = tile["kind"].as_str().unwrap_or("api-provider");
    if method == "plan" {
        out["usesLine"] = json!(t!("core-views.flow.uses", uses = runtime_name(runtime)));
        return out;
    }
    if kind == "env" {
        out["usesLine"] = json!(t!("core-views.flow.uses", uses = runtime_name(runtime)));
        out["canSubmit"] = json!(draft["pending"] != true);
        out["submitLabel"] = json!(t!("core-views.flow.add"));
        return out;
    }
    let own = tile["endpointRequired"] == true;
    let protocols: Vec<&str> = tile["protocols"].as_array().into_iter().flatten().filter_map(Value::as_str).collect();
    let protocol = own.then(|| draft["protocol"].as_str().filter(|p| protocols.contains(p)).or(protocols.first().copied())).flatten();
    let endpoint = draft["endpoint"].as_str().unwrap_or("").trim();
    let key_optional = tile["keyOptional"] == true;
    out["showEndpoint"] = json!(own);
    out["endpointHint"] = if own { tile["endpointExample"].as_str().map(|e| json!(t!("core-views.flow.endpoint_hint", example = e))).unwrap_or(Value::Null) } else { Value::Null };
    if own && protocols.len() > 1 {
        out["protocols"] = json!(protocols.iter().map(|p| json!({ "id": p, "label": t!(&format!("core-views.flow.protocol.{p}")) })).collect::<Vec<_>>());
    }
    out["protocol"] = protocol.map(Value::from).unwrap_or(Value::Null);
    out["showKey"] = json!(true);
    out["keyLabel"] = json!(if key_optional { t!("core-views.flow.key_optional") } else { t!("core-views.flow.key") });
    out["keyHint"] = json!(t!("core-views.flow.key_notice"));
    let key_ok = key_optional || !draft["key"].as_str().unwrap_or("").trim().is_empty();
    let endpoint_ok = !own || providers::clean_endpoint(endpoint).is_some();
    out["canSubmit"] = json!(draft["pending"] != true && key_ok && endpoint_ok);
    out["submitLabel"] = json!(t!("core-views.flow.verify_add"));
    let uses = providers::find(&tile["id"].as_str().unwrap_or("").to_string()).map(|s| uses_of(s, (!endpoint.is_empty()).then_some(endpoint), protocol)).unwrap_or_default();
    out["usesLine"] = json!(if uses.is_empty() { t!("core-views.flow.uses_none") } else { t!("core-views.flow.uses", uses = uses_text(&uses)) });
    out
}

impl Flows {
    pub fn new(store: Rc<Store>) -> Self {
        Self { store, drafts: RefCell::default() }
    }

    pub fn disconnect(&self, owner: ClientId) {
        self.drafts.borrow_mut().retain(|_, d| d.owner != owner);
    }

    pub fn value(&self, topic: &Topic) -> Result<Value> {
        let station = station_of(topic);
        let drafts = self.drafts.borrow();
        let Some(draft) = drafts.get(topic) else { return Ok(Value::Null) };
        let overview = self.store.value(&Topic::Overview { station: station.into() }).transpose()?.unwrap_or(Value::Null);
        Ok(view(station, &draft.value, &overview))
    }

    /// `open`, `edit` (a patch of what the views change) and `drop`.
    pub fn change(&self, topic: &Topic, owner: ClientId, action: &str, patch: &Value) -> Result<Value> {
        let station = station_of(topic).to_string();
        let mut drafts = self.drafts.borrow_mut();
        if drafts.get(topic).is_some_and(|d| d.owner != owner) {
            return Err(CoreError::invalid(t!("core-views.flow.not_yours")));
        }
        if action == "drop" {
            drafts.remove(topic);
            self.store.invalidate(topic);
            return Ok(Value::Null);
        }
        if !drafts.contains_key(topic) {
            let (store, form) = (Rc::downgrade(&self.store), topic.clone());
            let watch = self.store.watch(
                &Topic::Overview { station: station.clone() },
                Rc::new(move || {
                    if let Some(store) = store.upgrade() {
                        store.invalidate(&form);
                    }
                }),
            );
            let value = json!({ "provider": "", "method": "", "endpoint": "", "protocol": "", "key": "", "error": null, "pending": false });
            drafts.insert(topic.clone(), Draft { owner, value, pending: false, _watch: watch });
        }
        let draft = drafts.get_mut(topic).unwrap();
        if action == "edit" {
            if draft.pending {
                return Err(CoreError::invalid(t!("core-views.flow.wait")));
            }
            let overview = self.store.value(&Topic::Overview { station: station.clone() }).transpose()?.unwrap_or(Value::Null);
            let groups = groups(supported(&overview).as_deref());
            let Some(patch) = patch.as_object() else { return Ok(Value::Null) };
            if let Some(provider) = patch.get("provider").and_then(Value::as_str) {
                if provider.is_empty() {
                    draft.value = json!({ "provider": "", "method": "", "endpoint": "", "protocol": "", "key": "", "error": null, "pending": false });
                } else {
                    let tile = find(&groups, provider).ok_or_else(|| CoreError::invalid(t!("core-views.flow.unknown_provider")))?;
                    // What it can be connected with: both asks which, one goes straight on.
                    let method = match (tile["hasKey"] == true, tile["hasPlan"] == true) {
                        (true, true) => "",
                        (false, true) => "plan",
                        _ => "key",
                    };
                    draft.value = json!({ "provider": provider, "method": method, "endpoint": "", "protocol": "", "key": "", "error": null, "pending": false });
                }
            }
            if let Some(method) = patch.get("method").and_then(Value::as_str) {
                if !["", "plan", "key"].contains(&method) {
                    return Err(CoreError::invalid(t!("core-views.flow.unknown_provider")));
                }
                draft.value["method"] = json!(method);
            }
            if patch.get("back") == Some(&json!(true)) {
                let tile = draft.value["provider"].as_str().and_then(|id| find(&groups, id));
                let both = tile.is_some_and(|t| t["hasKey"] == true && t["hasPlan"] == true);
                if both && draft.value["method"].as_str().is_some_and(|m| !m.is_empty()) {
                    draft.value["method"] = json!("");
                } else {
                    draft.value = json!({ "provider": "", "method": "", "endpoint": "", "protocol": "", "key": "", "error": null, "pending": false });
                }
            }
            for field in ["endpoint", "protocol", "key"] {
                if let Some(v) = patch.get(field).and_then(Value::as_str) {
                    draft.value[field] = json!(v);
                    draft.value["error"] = Value::Null;
                }
            }
        }
        self.store.invalidate(topic);
        Ok(Value::Null)
    }

    /// The `profile.add` input of a draft ready to be submitted; the page waits meanwhile.
    pub fn begin(&self, topic: &Topic, owner: ClientId) -> Result<Value> {
        let overview = self.store.value(&Topic::Overview { station: station_of(topic).into() }).transpose()?.unwrap_or(Value::Null);
        let mut drafts = self.drafts.borrow_mut();
        let draft = drafts.get_mut(topic).filter(|d| d.owner == owner).ok_or_else(|| CoreError::invalid(t!("core-views.flow.closed")))?;
        if draft.pending {
            return Err(CoreError::invalid(t!("core-views.flow.wait")));
        }
        let shown = view(station_of(topic), &draft.value, &overview);
        if shown["step"] != "connect" || shown["canSubmit"] != true {
            return Err(CoreError::invalid(t!("core-views.flow.incomplete")));
        }
        let tile = &shown["tile"];
        let kind = tile["kind"].as_str().unwrap_or("api-provider");
        let input = if kind == "env" {
            json!({ "runtime": tile["runtime"], "access": { "kind": "env" } })
        } else {
            let mut access = json!({ "kind": kind });
            let key = draft.value["key"].as_str().unwrap_or("").trim();
            if !key.is_empty() {
                access["key"] = json!(key);
            }
            if kind == "api-provider" {
                access["provider"] = tile["id"].clone();
                if shown["showEndpoint"] == true {
                    access["endpoint"] = json!(draft.value["endpoint"].as_str().unwrap_or("").trim());
                    if let Some(protocol) = shown["protocol"].as_str() {
                        access["protocol"] = json!(protocol);
                    }
                }
            }
            json!({ "access": access })
        };
        draft.pending = true;
        draft.value["pending"] = json!(true);
        draft.value["error"] = Value::Null;
        self.store.invalidate(topic);
        Ok(input)
    }

    pub fn finish(&self, topic: &Topic, owner: ClientId, result: &Result<Value>) {
        if let Some(draft) = self.drafts.borrow_mut().get_mut(topic).filter(|d| d.owner == owner) {
            draft.pending = false;
            draft.value["pending"] = json!(false);
            // A refusal is said under the key.
            if let Err(e) = result {
                draft.value["error"] = json!(e.to_string());
            }
        }
        self.store.invalidate(topic);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flow() -> (Rc<Store>, Flows, Topic) {
        let store = Store::new(crate::testing::FakeHost::new());
        let flows = Flows::new(store.clone());
        (store, flows, Topic::ProfileFlow { station: "ws/st".into(), form: "t".into() })
    }

    #[test]
    fn the_picker_has_cues_groups_in_its_order_and_only_what_the_station_takes() {
        crate::testing::run(async {
            let (store, flows, topic) = flow();
            flows.change(&topic, 1, "open", &json!({})).unwrap();
            store.set(&Topic::Overview { station: "ws/st".into() }, Ok(json!({ "apiProviders": [{"id": "deepseek"}, {"id": "groq"}, {"id": "custom"}, {"id": "openai"}] })));
            let view = flows.value(&topic).unwrap();
            serde_json::from_value::<stillfail_shapes::ProfileFlowView>(view.clone()).unwrap();
            let ids: Vec<(String, Vec<String>)> = view["groups"].as_array().unwrap().iter()
                .map(|g| (g["id"].as_str().unwrap().into(), g["providers"].as_array().unwrap().iter().map(|p| p["id"].as_str().unwrap().into()).collect())).collect();
            assert_eq!(ids[0], ("labs".to_string(), vec!["openai".to_string(), "anthropic".to_string()]));
            assert_eq!(ids[1], ("china".to_string(), vec!["deepseek".to_string()]));
            assert_eq!(ids[2], ("gateways".to_string(), vec!["opencode-go".to_string()]));
            assert_eq!(ids[3].0, "inference");
            assert_eq!(ids[4], ("local".to_string(), vec!["custom".to_string(), "env-claude".to_string(), "env-codex".to_string()]));
            assert_eq!(view["step"], "pick");
            // A station from before the list: OpenAI is its plan alone, Anthropic and OpenCode Go as ever.
            store.set(&Topic::Overview { station: "ws/st".into() }, Ok(json!({})));
            let old = flows.value(&topic).unwrap();
            let all: Vec<&str> = old["groups"].as_array().unwrap().iter().flat_map(|g| g["providers"].as_array().unwrap()).map(|p| p["id"].as_str().unwrap()).collect();
            assert_eq!(all, ["openai", "anthropic", "opencode-go", "env-claude", "env-codex"]);
            let openai = &old["groups"][0]["providers"][0];
            assert_eq!((openai["hasKey"].as_bool(), openai["hasPlan"].as_bool()), (Some(false), Some(true)));
        });
    }

    #[test]
    fn a_vendor_with_a_plan_and_a_key_asks_which_and_one_with_a_key_goes_straight_to_the_form() {
        crate::testing::run(async {
            let (store, flows, topic) = flow();
            flows.change(&topic, 1, "open", &json!({})).unwrap();
            store.set(&Topic::Overview { station: "ws/st".into() }, Ok(json!({ "apiProviders": [{"id": "openai"}, {"id": "deepseek"}, {"id": "azure-openai"}, {"id": "custom"}] })));
            flows.change(&topic, 1, "edit", &json!({ "provider": "anthropic" })).unwrap();
            let view = flows.value(&topic).unwrap();
            assert_eq!((view["step"].as_str(), view["title"].as_str()), (Some("method"), Some("连接 Anthropic")));
            assert_eq!(view["choices"][0]["title"], "订阅 · Claude");
            // Back goes to the picker, a choice to the form.
            flows.change(&topic, 1, "edit", &json!({ "method": "key" })).unwrap();
            let view = flows.value(&topic).unwrap();
            assert_eq!((view["step"].as_str(), view["usesLine"].as_str()), (Some("connect"), Some("添加后可用于：Claude Code")));
            flows.change(&topic, 1, "edit", &json!({ "back": true })).unwrap();
            assert_eq!(flows.value(&topic).unwrap()["step"], "method");
            flows.change(&topic, 1, "edit", &json!({ "back": true })).unwrap();
            assert_eq!(flows.value(&topic).unwrap()["step"], "pick");
            // Chat completions only: it serves the automatic decisions.
            flows.change(&topic, 1, "edit", &json!({ "provider": "deepseek" })).unwrap();
            let view = flows.value(&topic).unwrap();
            assert_eq!((view["step"].as_str(), view["usesLine"].as_str(), view["canSubmit"].as_bool()), (Some("connect"), Some("添加后可用于：自动决策"), Some(false)));
            flows.change(&topic, 1, "edit", &json!({ "key": " sk-1 " })).unwrap();
            assert_eq!(flows.value(&topic).unwrap()["canSubmit"], true);
            let input = flows.begin(&topic, 1).unwrap();
            assert_eq!(input, json!({ "access": { "kind": "api-provider", "key": "sk-1", "provider": "deepseek" } }));
            assert!(flows.begin(&topic, 1).is_err(), "not twice");
            flows.finish(&topic, 1, &Err(CoreError::invalid("DeepSeek 拒绝了这个 key（401）")));
            assert_eq!(flows.value(&topic).unwrap()["error"], "DeepSeek 拒绝了这个 key（401）");
            flows.change(&topic, 1, "edit", &json!({ "key": "sk-2" })).unwrap();
            assert!(flows.value(&topic).unwrap()["error"].is_null(), "typing again clears it");
        });
    }

    #[test]
    fn an_address_of_the_readers_own_and_its_protocol_are_asked_and_decide_what_it_can_do() {
        crate::testing::run(async {
            let (store, flows, topic) = flow();
            flows.change(&topic, 1, "open", &json!({})).unwrap();
            store.set(&Topic::Overview { station: "ws/st".into() }, Ok(json!({ "apiProviders": [{"id": "azure-openai"}, {"id": "custom"}, {"id": "ollama"}] })));
            // Azure: an address, one protocol (nothing to choose), a key.
            flows.change(&topic, 1, "edit", &json!({ "provider": "azure-openai", "key": "k" })).unwrap();
            let view = flows.value(&topic).unwrap();
            assert_eq!((view["showEndpoint"].as_bool(), view["protocols"].as_array().unwrap().len(), view["canSubmit"].as_bool()), (Some(true), 0, Some(false)));
            flows.change(&topic, 1, "edit", &json!({ "endpoint": "https://r.openai.azure.com/openai/v1" })).unwrap();
            assert_eq!(flows.value(&topic).unwrap()["usesLine"], "添加后可用于：Codex");
            // Custom: three protocols asked, a key optional; what it is usable for follows the protocol.
            flows.change(&topic, 1, "edit", &json!({ "provider": "custom", "endpoint": "http://127.0.0.1:4000/v1" })).unwrap();
            let view = flows.value(&topic).unwrap();
            assert_eq!((view["protocols"].as_array().unwrap().len(), view["protocol"].as_str(), view["canSubmit"].as_bool(), view["keyLabel"].as_str()), (3, Some("chat_completions"), Some(true), Some("API key（可选）")));
            flows.change(&topic, 1, "edit", &json!({ "protocol": "anthropic" })).unwrap();
            assert_eq!(flows.value(&topic).unwrap()["usesLine"], "添加后可用于：Claude Code");
            let input = flows.begin(&topic, 1).unwrap();
            assert_eq!(input, json!({ "access": { "kind": "api-provider", "provider": "custom", "endpoint": "http://127.0.0.1:4000/v1", "protocol": "anthropic" } }));
            flows.finish(&topic, 1, &Ok(json!({})));
            // Ollama speaks chat completions only; variables by hand are for a runtime.
            flows.change(&topic, 1, "edit", &json!({ "provider": "ollama" })).unwrap();
            assert_eq!(flows.value(&topic).unwrap()["protocols"].as_array().unwrap().len(), 0);
            flows.change(&topic, 1, "edit", &json!({ "provider": "env-codex" })).unwrap();
            let view = flows.value(&topic).unwrap();
            assert_eq!((view["step"].as_str(), view["canSubmit"].as_bool(), view["showKey"].as_bool()), (Some("connect"), Some(true), Some(false)));
            assert_eq!(flows.begin(&topic, 1).unwrap(), json!({ "runtime": "codex", "access": { "kind": "env" } }));
            // Someone else's page is not for another device.
            assert!(flows.change(&topic, 2, "edit", &json!({})).is_err());
            assert!(flows.change(&topic, 1, "edit", &json!({ "provider": "nope" })).is_err());
        });
    }
}
