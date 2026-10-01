//! Runtime-reported model capabilities. Missing metadata keeps old stations usable; an explicitly empty
//! list means the model has no adjustable reasoning. Automatic accounts use their common levels.
use std::collections::HashMap;

pub type Catalog = HashMap<String, HashMap<String, Vec<String>>>;

pub fn fallback(runtime: &str) -> &'static [&'static str] {
    match runtime {
        "codex" => &["minimal", "low", "medium", "high", "xhigh"],
        _ => &["low", "medium", "high", "xhigh", "max"],
    }
}

pub fn available(runtime: &str, model: Option<&str>, catalog: Option<&Catalog>) -> Vec<String> {
    if let Some((model, models)) = model.zip(catalog.and_then(|c| c.get(runtime))) {
        if let Some(levels) = models.get(model).or_else(|| models.iter().find(|(id, _)| crate::model::same(id, model)).map(|(_, levels)| levels)) {
            return levels.clone();
        }
    }
    fallback(runtime).iter().map(|s| s.to_string()).collect()
}

pub fn common(mut profiles: impl Iterator<Item = Vec<String>>, runtime: &str) -> Vec<String> {
    let Some(mut levels) = profiles.next() else { return available(runtime, None, None) };
    for other in profiles {
        levels.retain(|level| other.contains(level));
    }
    levels
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reported_levels_aliases_empty_and_legacy() {
        let catalog: Catalog = serde_json::from_value(json!({"codex": {
            "gpt-6-astra": ["low", "medium", "high", "xhigh", "max", "ultra"],
            "gpt-6-luna": ["low", "medium", "high", "xhigh", "max"],
            "no-reasoning": []
        }})).unwrap();
        let astra = available("codex", Some("openai/gpt-6-astra"), Some(&catalog));
        assert!(astra.contains(&"max".into()) && astra.contains(&"ultra".into()));
        assert!(!astra.contains(&"minimal".into()));
        assert!(available("codex", Some("no-reasoning"), Some(&catalog)).is_empty());
        assert_eq!(available("codex", Some("unknown"), Some(&catalog)), fallback("codex"));
        assert_eq!(available("claude", Some("gpt-6-astra"), Some(&catalog)), fallback("claude"));
        let limited = available("codex", Some("gpt-6-luna"), Some(&catalog));
        assert!(!common([astra, limited].into_iter(), "codex").contains(&"ultra".into()));
    }
}
