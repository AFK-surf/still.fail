//! Automatic-decision rule drafts live in core, shared by all clients' views.
use std::{cell::RefCell, collections::HashMap, rc::Rc};
use serde_json::{Value,json};
use crate::{protocol::{ClientId,Topic},store::{Store,Watch},error::{Result,CoreError}};
struct Draft { owner:ClientId, value:Value, pending:bool, _watch:Watch }
pub struct Forms { store:Rc<Store>, drafts:RefCell<HashMap<Topic,Draft>> }
impl Forms {
    pub fn new(store:Rc<Store>)->Self { Self {store,drafts:RefCell::default()} }
    pub fn disconnect(&self,owner:ClientId) { self.drafts.borrow_mut().retain(|_,d|d.owner!=owner); }
    pub fn value(&self,topic:&Topic)->Result<Value> {
        let mut drafts=self.drafts.borrow_mut();
        let Some(d)=drafts.get_mut(topic) else {return Ok(Value::Null)};
        if !d.pending && d.value["dirty"] != true {
            let Topic::DecisionForm{station,..}=topic else {unreachable!()};
            let overview=self.store.value(&Topic::Overview{station:station.clone()}).transpose()?.unwrap_or(Value::Null);
            let saved=&overview["automaticDecisions"]["settings"]["completion"];
            if saved.is_object() {
                d.value["enabled"]=json!(saved["enabled"].as_bool().unwrap_or(false));
                d.value["model"]=json!(saved["model"].as_str().unwrap_or(""));
            }
        }
        Ok(d.value.clone())
    }
    pub fn change(&self,topic:&Topic,owner:ClientId,action:&str,patch:&Value)->Result<Value> {
        let Topic::DecisionForm{station,..}=topic else {unreachable!()};
        // Apply newly arrived settings before the first edit; dirty drafts remain owned by their page.
        if action=="edit" { self.value(topic)?; }
        let mut drafts=self.drafts.borrow_mut();
        if drafts.get(topic).is_some_and(|d|d.owner!=owner) {return Err(CoreError::invalid("不是这个页面的自动决策草稿"));}
        if action=="drop" {drafts.remove(topic); self.store.invalidate(topic); return Ok(Value::Null);}
        if !drafts.contains_key(topic) {
            let overview=self.store.value(&Topic::Overview{station:station.clone()}).transpose()?.unwrap_or(Value::Null);
            let saved=&overview["automaticDecisions"]["settings"]["completion"];
            let value=json!({"enabled":saved["enabled"].as_bool().unwrap_or(false),"model":saved["model"].as_str().unwrap_or(""),"dirty":false,"pending":false});
            let (store,form)=(Rc::downgrade(&self.store),topic.clone());
            let watch=self.store.watch(&Topic::Overview{station:station.clone()},Rc::new(move || {
                if let Some(store)=store.upgrade() {store.invalidate(&form);}
            }));
            drafts.insert(topic.clone(),Draft{owner,value,pending:false,_watch:watch});
        }
        let d=drafts.get_mut(topic).unwrap();
        if action=="edit" {
            if d.pending {return Err(CoreError::invalid("请等保存完成"));}
            if let Some(p)=patch.as_object() {
                for (key,value) in p { if ["enabled","model"].contains(&key.as_str()) {d.value[key]=value.clone();} }
                d.value["dirty"]=json!(true);
            }
        }
        self.store.invalidate(topic); Ok(d.value.clone())
    }
    pub fn begin(&self,topic:&Topic,owner:ClientId)->Result<Value> {
        let mut drafts=self.drafts.borrow_mut();
        let d=drafts.get_mut(topic).filter(|d|d.owner==owner).ok_or_else(||CoreError::invalid("自动决策草稿已关闭"))?;
        if d.pending {return Err(CoreError::invalid("正在保存"));}
        let model=d.value["model"].as_str().filter(|m|!m.is_empty());
        if d.value["enabled"]==true && model.is_none() {return Err(CoreError::invalid("请选择用于完成检查的模型"));}
        let input=json!({"completion":{"enabled":d.value["enabled"],"model":model}});
        d.pending=true;d.value["pending"]=json!(true);self.store.invalidate(topic);Ok(input)
    }
    pub fn finish(&self,topic:&Topic,owner:ClientId,result:&Result<Value>) {
        if let Some(d)=self.drafts.borrow_mut().get_mut(topic).filter(|d|d.owner==owner) {
            d.pending=false;d.value["pending"]=json!(false);
            if result.is_ok() { d.value["dirty"]=json!(false); }
        }
        self.store.invalidate(topic);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn late_settings_update_clean_drafts_but_do_not_overwrite_edits() {
        crate::testing::run(async {
            let host=crate::testing::FakeHost::new();
            let store=Store::new(host);let forms=Forms::new(store.clone());
            let form=Topic::DecisionForm{station:"ws/st".into(),form:"late".into()};
            let overview=Topic::Overview{station:"ws/st".into()};
            forms.change(&form,1,"open",&json!({})).unwrap();
            store.set(&overview,Ok(json!({"automaticDecisions":{"settings":{"completion":{"enabled":true,"model":"gpt-6-luna"}}}})));
            let current=forms.value(&form).unwrap();
            assert_eq!(current["enabled"],true);assert_eq!(current["model"],"gpt-6-luna");
            forms.change(&form,1,"edit",&json!({"model":"another"})).unwrap();
            store.set(&overview,Ok(json!({"automaticDecisions":{"settings":{"completion":{"enabled":false,"model":null}}}})));
            assert_eq!(forms.value(&form).unwrap()["model"],"another");
            forms.change(&form,1,"drop",&json!({})).unwrap();
        });
    }
}
