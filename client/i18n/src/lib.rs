//! The words people read, in their language. Each language's words are in `catalog/<lang>/*.json`, by key: a string,
//! where `{name}` takes the value given as `name`; or, for words that change with a number, `{"one": …, "other": …}`,
//! chosen by the value given as `n` (1: `one`). A key a language lacks is said in Chinese; one neither has is shown as
//! the key. The web app (web/src/i18n.ts) and the Android app (ui/I18n.kt) read the same files the same way.

use std::collections::HashMap;
use std::fmt::Display;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU8, Ordering};

use serde_json::Value;

include!(concat!(env!("OUT_DIR"), "/catalog.rs"));

/// A language the words are kept in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum Lang {
    #[default]
    Zh,
    En,
}

impl Lang {
    /// From a setting or a locale (`zh`, `zh-CN`, `en-US`, …): Chinese for Chinese, English for any other; Chinese when
    /// nothing is said (as everything was before there were languages).
    pub fn from_locale(locale: &str) -> Lang {
        let locale = locale.trim().to_ascii_lowercase();
        if locale.is_empty() || locale.starts_with("zh") { Lang::Zh } else { Lang::En }
    }

    pub fn code(self) -> &'static str {
        match self {
            Lang::Zh => "zh",
            Lang::En => "en",
        }
    }
}

type Catalog = HashMap<Lang, HashMap<String, Value>>;

fn catalog() -> &'static Catalog {
    static CATALOG: OnceLock<Catalog> = OnceLock::new();
    CATALOG.get_or_init(|| {
        let mut all: Catalog = HashMap::new();
        for (lang, text) in FILES {
            let words = all.entry(Lang::from_locale(lang)).or_default();
            if let Ok(Value::Object(map)) = serde_json::from_str::<Value>(text) {
                words.extend(map);
            }
        }
        all
    })
}

static CURRENT: AtomicU8 = AtomicU8::new(0);

/// The language words are said in where no one is asked (the core: its person's, as their prefs say).
pub fn current() -> Lang {
    if CURRENT.load(Ordering::Relaxed) == 1 { Lang::En } else { Lang::Zh }
}

pub fn set_current(lang: Lang) {
    CURRENT.store(if lang == Lang::En { 1 } else { 0 }, Ordering::Relaxed);
}

/// Whether a language has the key itself (not said in Chinese for it).
pub fn has(lang: Lang, key: &str) -> bool {
    catalog().get(&lang).is_some_and(|w| w.contains_key(key))
}

/// The words for `key` in `lang`, with `args` put in.
pub fn tr(lang: Lang, key: &str, args: &[(&str, &dyn Display)]) -> String {
    let found = catalog().get(&lang).and_then(|w| w.get(key)).or_else(|| catalog().get(&Lang::Zh).and_then(|w| w.get(key)));
    let text = match found {
        Some(Value::String(s)) => s.as_str(),
        Some(Value::Object(forms)) => {
            let one = args.iter().find(|(name, _)| *name == "n").is_some_and(|(_, v)| v.to_string().trim() == "1");
            forms.get(if one { "one" } else { "other" }).or_else(|| forms.get("other")).and_then(Value::as_str).unwrap_or(key)
        }
        _ => key,
    };
    fill(text, args)
}

/// The words for `key` in the current language.
pub fn t(key: &str) -> String {
    tr(current(), key, &[])
}

/// The words for `key` in the current language, with `args` put in.
pub fn ta(key: &str, args: &[(&str, &dyn Display)]) -> String {
    tr(current(), key, args)
}

fn fill(text: &str, args: &[(&str, &dyn Display)]) -> String {
    if args.is_empty() || !text.contains('{') {
        return text.to_string();
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(open) = rest.find('{') {
        out.push_str(&rest[..open]);
        let after = &rest[open + 1..];
        match after.find('}') {
            Some(close) if after[..close].chars().all(|c| c.is_ascii_alphanumeric() || c == '_') => {
                let name = &after[..close];
                match args.iter().find(|(n, _)| *n == name) {
                    Some((_, value)) => out.push_str(&value.to_string()),
                    None => out.push_str(&rest[open..open + close + 2]),
                }
                rest = &after[close + 1..];
            }
            _ => {
                out.push('{');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// `t!("key")`, `t!("key", name = value, n = count)`: the words in the current language. `t!(lang; "key", …)` in a
/// given one.
#[macro_export]
macro_rules! t {
    ($lang:expr; $key:expr $(, $name:ident = $value:expr)* $(,)?) => {
        $crate::tr($lang, $key, &[$((stringify!($name), &$value as &dyn ::std::fmt::Display)),*])
    };
    ($key:expr $(, $name:ident = $value:expr)* $(,)?) => {
        $crate::tr($crate::current(), $key, &[$((stringify!($name), &$value as &dyn ::std::fmt::Display)),*])
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fills_and_counts() {
        assert_eq!(fill("{a} and {b}", &[("a", &1), ("b", &"x")]), "1 and x");
        assert_eq!(fill("{missing} {", &[("a", &1)]), "{missing} {");
        assert_eq!(Lang::from_locale("zh-Hant-TW"), Lang::Zh);
        assert_eq!(Lang::from_locale("en-GB"), Lang::En);
        assert_eq!(Lang::from_locale(""), Lang::Zh);
        assert_eq!(tr(Lang::En, "no.such.key", &[]), "no.such.key");
    }

    /// Every key Chinese has, English has too, with the same `{names}`; and the other way round.
    #[test]
    fn languages_agree() {
        let all = catalog();
        let (zh, en) = (&all[&Lang::Zh], &all[&Lang::En]);
        let names = |v: &Value| {
            let texts: Vec<&str> = match v {
                Value::String(s) => vec![s.as_str()],
                Value::Object(m) => m.values().filter_map(Value::as_str).collect(),
                _ => vec![],
            };
            let mut found: Vec<String> = texts.iter().flat_map(|s| s.split('{').skip(1).filter_map(|p| p.split_once('}').map(|(n, _)| n.to_string()))).filter(|n| n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')).collect();
            found.sort();
            found.dedup();
            found
        };
        let mut wrong = Vec::new();
        for (key, value) in zh {
            match en.get(key) {
                None => wrong.push(format!("{key}: no English")),
                Some(other) if names(other) != names(value) => wrong.push(format!("{key}: {:?} vs {:?}", names(value), names(other))),
                _ => {}
            }
        }
        wrong.extend(en.keys().filter(|k| !zh.contains_key(*k)).map(|k| format!("{k}: no Chinese")));
        wrong.sort();
        assert!(wrong.is_empty(), "{}", wrong.join("\n"));
    }
}
