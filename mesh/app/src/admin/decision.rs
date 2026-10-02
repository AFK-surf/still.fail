use super::{AdminApi, Input, http_error};
use crate::{access::Viewer, decision::{AutomaticDecisions, profiles::resolved_model}, pool::usable};
use anyhow::Result;
use serde_json::{Value, json};
use std::{collections::BTreeMap, sync::Arc};

impl AdminApi {
    fn decision_models(&self) -> Vec<Value> {
        let mut models: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for profile in &self.config().profiles {
            let health = self.deps.hub.health_of(&profile.id);
            if !usable(&health) { continue; }
            let Some(capability) = health.check.as_ref().and_then(|c| c.decision.as_ref()) else { continue };
            let names = capability.models.iter().chain(capability.model.iter());
            for model in names {
                if resolved_model(profile, capability, Some(model)).is_none() { continue; }
                let profiles=models.entry(model.clone()).or_default();
                if !profiles.contains(&profile.name) { profiles.push(profile.name.clone()); }
            }
        }
        models.into_iter().map(|(model,profiles)| json!({"id":model,"name":stillfail_shapes::model::name(&model),"profiles":profiles})).collect()
    }
    pub(super) fn put_automatic_decisions(&self, input: &Input, viewer: &Viewer) -> Result<Value> {
        if !viewer.manages() { return Err(http_error(403, "只有 workspace 管理员能配置自动决策")); }
        let config: AutomaticDecisions = serde_json::from_value(Value::Object(input.0.clone()))
            .map_err(|_| http_error(400, "自动决策配置格式不正确"))?;
        if config.completion.enabled && !self.decision_models().iter().any(|m| m["id"].as_str() == config.completion.model.as_deref()) {
            return Err(http_error(400, "请选择现有 Profile 中已验证可用的决策模型"));
        }
        self.save(viewer, "automatic decisions", |raw| { raw.automatic_decisions = Some(config); Ok(()) })
    }
    pub(super) async fn refresh_decision_models(self: &Arc<Self>, viewer: &Viewer) -> Result<Value> {
        if !viewer.manages() { return Err(http_error(403, "只有 workspace 管理员能刷新决策模型")); }
        use futures_util::{stream, StreamExt};
        let ids: Vec<_> = self.config().profiles.iter().map(|p|p.id.clone()).collect();
        let results = stream::iter(ids).map(|id| async move { self.check(&id).await }).buffer_unordered(4).collect::<Vec<_>>().await;
        for result in results { result?; }
        Ok(self.overview(viewer))
    }
    pub(super) fn automatic_decisions_view(&self, viewer: &Viewer) -> Value {
        if !viewer.manages() { return json!({"canEdit":false,"settings":{},"models":[],"recent":[]}); }
        let rows = self.deps.store.recent_decisions().unwrap_or_default();
        let recent: Vec<_> = rows.iter().map(|row| {
            let d=&row["detail"];
            let status=d["result"]["selected"].as_str().unwrap_or("unavailable");
            let label=match status {"complete"=>"没有后续事项，推荐归档", "agent_work"=>"还有工作可以继续", "human_needed"=>"仍需人处理", "uncertain"=>"证据不足，不推荐", _=>"检查失败"};
            let session=row["session"].as_str().unwrap_or("");
            let title=self.deps.store.get_session(session).ok().flatten().and_then(|s| s.title).unwrap_or_else(|| session.into());
            json!({"id":row["id"],"session":session,"title":title,"at":row["at"],"label":label,
                "accepted":d["accepted"],"model":d["model"],"profile":d["profile"],
                "elapsedMs":d["elapsedMs"],"error":d["error"]})
        }).collect();
        json!({"canEdit":true,"settings":self.config().automatic_decisions,"models":self.decision_models(),"recent":recent})
    }
}
