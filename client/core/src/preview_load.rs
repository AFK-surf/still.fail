//! Resource progress shared by every preview transport. No response bodies are retained.
use std::{cell::{Cell, RefCell}, collections::HashMap};
use serde_json::{json, Value};
use crate::protocol::Topic;

#[derive(Default)]
pub struct Loads {
    next: Cell<u64>,
    pages: RefCell<HashMap<Topic, Page>>,
}
#[derive(Default)]
struct Page { rows: Vec<Value>, total: u64, finished: u64, failed: u64 }
impl Loads {
    pub fn start(&self, station: &str, port: u16, method: &str, path: &str, headers: &[(String, String)], now: f64) -> (Topic, u64) {
        let topic = Topic::PreviewLoad { station: station.into(), port };
        let id = self.next.get() + 1;
        self.next.set(id);
        let mut pages = self.pages.borrow_mut();
        // Bounded across services, as well as within each resource list.
        if pages.len() >= 32 && !pages.contains_key(&topic) {
            if let Some(key) = pages.keys().next().cloned() { pages.remove(&key); }
        }
        let page = pages.entry(topic.clone()).or_default();
        let header = |name: &str| headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.as_str());
        let document = match header("sec-fetch-dest") {
            Some(dest) => matches!(dest, "document" | "iframe"),
            None => header("accept").is_some_and(|v| v.contains("text/html")),
        };
        if document { *page = Page::default(); }
        page.total += 1;
        // Keep pending requests; discard old completed details first.
        if page.rows.len() >= 200 {
            if let Some(i) = page.rows.iter().position(|r| r["ended"].is_number()) { page.rows.remove(i); }
        }
        page.rows.push(json!({"id": id, "method": method, "path": path, "since": now, "status": null, "ended": null, "error": null}));
        (topic, id)
    }
    pub fn head(&self, key: &(Topic, u64), status: u64) {
        if let Some(page) = self.pages.borrow_mut().get_mut(&key.0) {
            if let Some(row) = page.rows.iter_mut().find(|r| r["id"] == key.1) { row["status"] = json!(status); }
        }
    }
    pub fn end(&self, key: &(Topic, u64), now: f64, error: Option<&str>) {
        if let Some(page) = self.pages.borrow_mut().get_mut(&key.0) {
            if let Some(row) = page.rows.iter_mut().find(|r| r["id"] == key.1 && r["ended"].is_null()) {
                row["ended"] = json!(now);
                row["error"] = json!(error);
                page.finished += 1;
                if error.is_some() || row["status"].as_u64().is_some_and(|s| s >= 400) { page.failed += 1; }
            }
        }
    }
    pub fn value(&self, topic: &Topic) -> Value {
        let pages = self.pages.borrow();
        let Some(page) = pages.get(topic) else { return json!({"percent": 0, "total": 0, "finished": 0, "failed": 0, "resources": []}); };
        json!({"percent": if page.total == 0 { 0 } else { page.finished * 100 / page.total }, "total": page.total, "finished": page.finished, "failed": page.failed, "resources": page.rows})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn counts_failures_and_ignores_old_navigation_completions() {
        let loads = Loads::default();
        let document = vec![("Accept".into(), "text/html".into())];
        let first = loads.start("ws/a", 3000, "GET", "/", &document, 0.0);
        let script = loads.start("ws/a", 3000, "GET", "/app.js", &[], 1.0);
        loads.head(&first, 200);
        loads.end(&first, 2.0, None);
        assert_eq!(loads.value(&first.0)["percent"], 50);
        loads.head(&script, 404);
        loads.end(&script, 3.0, None);
        loads.end(&script, 4.0, None);
        assert_eq!(loads.value(&first.0)["failed"], 1);
        assert_eq!(loads.value(&first.0)["percent"], 100);
        let next = loads.start("ws/a", 3000, "GET", "/next", &document, 5.0);
        loads.end(&script, 6.0, Some("cancelled"));
        assert_eq!(loads.value(&next.0)["total"], 1);
        assert_eq!(loads.value(&next.0)["finished"], 0);
        assert_eq!(loads.value(&Topic::PreviewLoad { station: "other/a".into(), port: 3000 })["total"], 0);
    }
    #[test]
    fn retains_totals_when_old_details_are_trimmed() {
        let loads = Loads::default();
        for n in 0..250 {
            let key = loads.start("ws/a", 3000, "GET", "/data", &[], n as f64);
            loads.end(&key, n as f64 + 1.0, None);
        }
        let value = loads.value(&Topic::PreviewLoad { station: "ws/a".into(), port: 3000 });
        assert_eq!(value["total"], 250);
        assert_eq!(value["percent"], 100);
        assert_eq!(value["resources"].as_array().unwrap().len(), 200);
    }
}
