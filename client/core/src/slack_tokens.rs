//! A Slack token form's draft and verification, shared by the views. Secrets stay in memory only, until its UI
//! disconnects or drops the form. A result for an older edit cannot verify newer tokens or advance the form.
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use serde_json::{Value, json};
use stillfail_i18n::t;
use crate::error::{CoreError, Result};
use crate::protocol::{ClientId, Topic};

#[derive(Default)]
struct Draft {
    owner: ClientId,
    revision: u64,
    checking: bool,
    input: Value,
    verified: Value,
    errors: Vec<String>,
}

#[derive(Default)]
pub struct Tokens(RefCell<HashMap<Topic, Draft>>, Cell<u64>);

impl Tokens {
    pub fn edit(&self, topic: &Topic, owner: ClientId, patch: &Value) -> Result<Value> {
        let mut drafts = self.0.borrow_mut();
        let draft = drafts.entry(topic.clone()).or_insert_with(|| Draft { owner, input: json!({"appToken": "", "botToken": "", "connect": null, "install": null}), ..Draft::default() });
        if draft.owner != owner { return Err(CoreError::invalid(t!("core-misc.token.not_yours"))); }
        let old = draft.input.clone();
        let mut next = old.clone();
        for field in ["appToken", "botToken", "connect", "install"] {
            if let Some(value) = patch.get(field) {
                if !value.is_null() && !value.is_string() { return Err(CoreError::invalid(t!("core-misc.token.not_text"))); }
                next[field] = value.clone();
            }
        }
        draft.input = next;
        if draft.revision == 0 || draft.input != old || patch.get("clear").and_then(Value::as_bool) == Some(true) {
            self.1.set(self.1.get() + 1);
            draft.revision = self.1.get();
            draft.checking = false;
            draft.verified = Value::Null;
            draft.errors.clear();
        }
        Ok(shown(draft))
    }

    pub fn value(&self, topic: &Topic) -> Value {
        self.0.borrow().get(topic).map(shown).unwrap_or_else(|| json!({"appToken":"", "botToken":"", "verified":null, "errors":[], "ready":false}))
    }

    pub fn input(&self, topic: &Topic, owner: ClientId) -> Result<(Value, bool)> {
        let drafts = self.0.borrow();
        let d = drafts.get(topic).filter(|d| d.owner == owner).ok_or_else(|| CoreError::invalid(t!("core-misc.token.closed")))?;
        Ok((d.input.clone(), !d.verified.is_null()))
    }

    pub fn begin(&self, topic: &Topic, owner: ClientId) -> Result<(u64, Value, bool)> {
        let mut drafts = self.0.borrow_mut();
        let draft = drafts.get_mut(topic).filter(|d| d.owner == owner).ok_or_else(|| CoreError::invalid(t!("core-misc.token.closed")))?;
        if draft.checking { return Err(CoreError::invalid(t!("core-misc.token.checking"))); }
        let verified = !draft.verified.is_null();
        draft.checking = !verified;
        Ok((draft.revision, draft.input.clone(), verified))
    }

    pub fn finish(&self, topic: &Topic, revision: u64, answer: &Result<Value>) -> bool {
        let mut drafts = self.0.borrow_mut();
        let Some(draft) = drafts.get_mut(topic).filter(|d| d.revision == revision) else { return false };
        draft.checking = false;
        match answer {
            Ok(answer) => {
                draft.errors = answer["errors"].as_array().into_iter().flatten().filter_map(Value::as_str).map(str::to_string).collect();
                draft.verified = if draft.errors.is_empty() { answer["identity"].clone() } else { Value::Null };
            }
            Err(error) => { draft.errors = vec![error.message.clone()]; draft.verified = Value::Null; }
        }
        answer.is_ok() && draft.errors.is_empty() && !draft.verified.is_null()
    }

    pub fn drop(&self, topic: &Topic, owner: ClientId) {
        self.0.borrow_mut().retain(|t, d| t != topic || d.owner != owner);
    }

    pub fn disconnect(&self, owner: ClientId) -> Vec<Topic> {
        let mut removed = Vec::new();
        self.0.borrow_mut().retain(|topic, draft| {
            if draft.owner == owner { removed.push(topic.clone()); false } else { true }
        });
        removed
    }
}

fn shown(draft: &Draft) -> Value {
    let has = |field: &str| draft.input[field].as_str().is_some_and(|s| !s.is_empty());
    json!({
        "appToken": draft.input["appToken"].as_str().unwrap_or(""),
        "botToken": draft.input["botToken"].as_str().unwrap_or(""),
        "verified": draft.verified, "errors": draft.errors,
        "ready": has("appToken") || (!has("install") && has("botToken")) || has("connect"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn topic(station: &str) -> Topic { Topic::SlackTokens { station: station.into(), form: "form".into() } }
    #[test]
    fn edits_and_install_changes_invalidate_verification_and_late_answers() {
        let forms = Tokens::default(); let t = topic("w/s");
        forms.edit(&t, 1, &json!({"appToken":"old"})).unwrap();
        let (revision, _, _) = forms.begin(&t, 1).unwrap();
        forms.edit(&t, 1, &json!({"appToken":"new"})).unwrap();
        let ok = Ok(json!({"identity":{"team":"team"},"errors":[]}));
        assert!(!forms.finish(&t, revision, &ok));
        assert!(forms.value(&t)["verified"].is_null());
        let (revision, _, _) = forms.begin(&t, 1).unwrap();
        assert!(forms.finish(&t, revision, &ok));
        forms.edit(&t, 1, &json!({"install":"another-app"})).unwrap();
        assert!(forms.value(&t)["verified"].is_null());
    }
    #[test]
    fn saved_tokens_and_installs_have_the_same_rules_in_every_view() {
        let forms = Tokens::default(); let t = topic("w/s");
        assert_eq!(forms.edit(&t, 1, &json!({"connect":"c"})).unwrap()["ready"], true);
        assert_eq!(forms.edit(&t, 1, &json!({"connect":null,"botToken":"bot"})).unwrap()["ready"], true);
        assert_eq!(forms.edit(&t, 1, &json!({"install":"oauth"})).unwrap()["ready"], false);
        assert_eq!(forms.edit(&t, 1, &json!({"appToken":"app"})).unwrap()["ready"], true);
        assert!(forms.begin(&t, 2).is_err());
        forms.edit(&topic("other/s"), 2, &json!({"appToken":"other"})).unwrap();
        forms.disconnect(1);
        assert!(forms.begin(&t, 1).is_err());
        assert!(forms.begin(&topic("other/s"), 2).is_ok());
    }
    #[test]
    fn a_closed_and_reopened_form_does_not_take_the_old_result() {
        let forms = Tokens::default(); let t = topic("w/s");
        forms.edit(&t, 1, &json!({"appToken":"old"})).unwrap();
        let (revision, _, _) = forms.begin(&t, 1).unwrap();
        assert!(forms.begin(&t, 1).is_err(), "one verification at a time");
        forms.drop(&t, 1);
        forms.edit(&t, 1, &json!({"appToken":"new"})).unwrap();
        assert!(!forms.finish(&t, revision, &Ok(json!({"identity":{"team":"old"},"errors":[]}))));
        assert!(forms.value(&t)["verified"].is_null());
    }

}
