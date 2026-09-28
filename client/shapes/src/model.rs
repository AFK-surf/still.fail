//! Models by what they are rather than how a provider spells them: `openai/gpt-6-astra` (OpenRouter),
//! `us.anthropic.claude-opus-5-5-v1:0` (Bedrock), `claude-opus-5-5@20260101` (Vertex) and `claude-haiku-4-5-20251001`
//! are `gpt-6-astra`, `claude-opus-5-5` and `claude-haiku-4-5` (their `key`), and read as GPT-6 Astra, Opus 5.5 and
//! Haiku 4.5 (their `name`). The station picks accounts by key and runs each on its own spelling; the clients show one
//! model per key, by name. What is left as spelled: a `[1m]` context (another price), a `:free` or `:32b` tag.

/// What a model is, however it is spelled: lower case, without its provider's prefix, region, version stamp or date.
pub fn key(id: &str) -> String {
    let id = id.trim().to_lowercase();
    // A context in brackets stays: `[1m]` is another model to pay for.
    let (id, context) = match id.find('[') {
        Some(at) => (&id[..at], &id[at..]),
        None => (id.as_str(), ""),
    };
    // OpenRouter's and other routers' `vendor/model`.
    let mut m = id.rsplit('/').next().unwrap_or(id);
    // Vertex's `model@date`.
    m = m.split('@').next().unwrap_or(m);
    // Bedrock's `us.anthropic.model-v1:0`: region and vendor are words and a dot, a version is not (gpt-5.1).
    while let Some((head, rest)) = m.split_once('.') {
        if head.is_empty() || !head.bytes().all(|b| b.is_ascii_alphabetic()) || rest.is_empty() {
            break;
        }
        m = rest;
    }
    let mut m = m.to_string();
    if let Some(at) = m.rfind("-v").filter(|&at| stamp(&m[at + 2..])) {
        m.truncate(at);
    }
    // A date: -20251001, or -2024-08-06.
    let parts: Vec<&str> = m.split('-').collect();
    let digits = |s: &str, n: usize| s.len() == n && s.bytes().all(|b| b.is_ascii_digit());
    let n = parts.len();
    if n > 1 && digits(parts[n - 1], 8) {
        m = parts[..n - 1].join("-");
    } else if n > 3 && digits(parts[n - 3], 4) && digits(parts[n - 2], 2) && digits(parts[n - 1], 2) {
        m = parts[..n - 3].join("-");
    }
    format!("{m}{context}")
}

/// Bedrock's version stamp after `-v`: `1:0` (not a model's own v4).
fn stamp(s: &str) -> bool {
    let Some((major, minor)) = s.split_once(':') else { return false };
    !major.is_empty() && major.bytes().all(|b| b.is_ascii_digit()) && !minor.is_empty() && minor.bytes().all(|b| b.is_ascii_digit())
}

/// Whether two spellings are one model.
pub fn same(a: &str, b: &str) -> bool {
    a == b || key(a) == key(b)
}

/// A model as people call it: Opus 5.5, Sonnet 3.5, GPT-6 Astra, o4 Mini, DeepSeek V4 Pro, Qwen3 Coder, GLM-4.6. One
/// whose family is not known here reads as it is spelled.
pub fn name(id: &str) -> String {
    let k = key(id);
    let (base, context) = match k.find('[') {
        Some(at) => (&k[..at], k[at + 1..].trim_end_matches(']').to_uppercase()),
        None => (k.as_str(), String::new()),
    };
    let Some(named) = named(base) else { return id.trim().to_string() };
    if context.is_empty() { named } else { format!("{named} {context}") }
}

/// The series a model is of, as people call it (Opus, Sonnet, GPT, o 系列, DeepSeek, Qwen); None when its family is not
/// known here.
pub fn family(id: &str) -> Option<String> {
    let k = key(id);
    let base = k.split('[').next().unwrap_or("");
    named(base)?;
    let words: Vec<&str> = base.split('-').filter(|w| !w.is_empty()).collect();
    let first = *words.first()?;
    if first == "claude" || CLAUDE.contains(&first) {
        return words.iter().find(|w| CLAUDE.contains(w)).map(|w| word(w));
    }
    if first.len() > 1 && first.starts_with('o') && first[1..].bytes().all(|b| b.is_ascii_digit()) {
        return Some("o 系列".into());
    }
    Some(word(first.trim_end_matches(|c: char| c.is_ascii_digit() || c == '.')))
}

/// How models are listed: by series (Claude's biggest first, the rest by name), then newest first. Compare these.
pub fn order(id: &str) -> (usize, String, std::cmp::Reverse<Vec<u32>>, String) {
    let family = family(id);
    let rank = match family.as_deref().map(str::to_lowercase) {
        Some(f) => CLAUDE.iter().position(|c| *c == f).unwrap_or(CLAUDE.len()),
        None => CLAUDE.len() + 1,
    };
    let k = key(id);
    let base = k.split('[').next().unwrap_or("");
    // Its version, the numbers in it: 5.5 before 5 before 4.8.
    let version: Vec<u32> = base.split(|c: char| !c.is_ascii_digit()).filter_map(|n| n.parse().ok()).collect();
    (rank, family.unwrap_or_default(), std::cmp::Reverse(version), k)
}

/// Claude's series, biggest first.
const CLAUDE: [&str; 4] = ["fable", "opus", "sonnet", "haiku"];

fn named(base: &str) -> Option<String> {
    let words: Vec<&str> = base.split('-').filter(|w| !w.is_empty()).collect();
    let first = *words.first()?;
    // Claude: the family, then its version with dots (claude-opus-4-1, claude-3-5-sonnet, opus).
    if first == "claude" || CLAUDE.contains(&first) {
        let family = words.iter().find(|w| CLAUDE.contains(w))?;
        let version: Vec<&str> = words.iter().copied().filter(|w| w.bytes().all(|b| b.is_ascii_digit())).collect();
        let rest: Vec<String> = words.iter().filter(|w| **w != "claude" && *w != family && !w.bytes().all(|b| b.is_ascii_digit())).map(|w| word(w)).collect();
        let mut out = vec![word(family)];
        if !version.is_empty() {
            out.push(version.join("."));
        }
        out.extend(rest);
        return Some(out.join(" "));
    }
    // Families that join their version with a dash: GPT-5.1, GLM-4.6.
    let dashed = match first {
        "gpt" => Some("GPT"),
        "glm" => Some("GLM"),
        _ => None,
    };
    if let (Some(family), Some(version)) = (dashed, words.get(1)) {
        let rest = words[2..].iter().map(|w| word(w));
        return Some(std::iter::once(format!("{family}-{version}")).chain(rest).collect::<Vec<_>>().join(" "));
    }
    // OpenAI's o-series keeps its small o: o3, o4 Mini.
    let o_series = first.len() > 1 && first.starts_with('o') && first[1..].bytes().all(|b| b.is_ascii_digit());
    let known = ["gpt", "glm", "codex", "deepseek", "qwen", "qwq", "gemini", "gemma", "kimi", "moonshot", "minimax", "grok", "mistral", "devstral", "codestral", "llama", "doubao", "hunyuan", "ernie"];
    let family = first.trim_end_matches(|c: char| c.is_ascii_digit() || c == '.');
    if !o_series && !known.contains(&family) {
        return None;
    }
    Some(words.iter().enumerate().map(|(i, w)| if i == 0 && o_series { w.to_string() } else { word(w) }).collect::<Vec<_>>().join(" "))
}

/// One word of a name: a brand as it writes itself, a version as it is (v4 → V4, k2 → K2), else capitalized.
fn word(w: &str) -> String {
    const BRANDS: [(&str, &str); 14] = [
        ("deepseek", "DeepSeek"), ("minimax", "MiniMax"), ("qwq", "QwQ"), ("glm", "GLM"), ("gpt", "GPT"), ("oss", "OSS"),
        ("moonshot", "Moonshot"), ("devstral", "Devstral"), ("codestral", "Codestral"), ("llama", "Llama"),
        ("ernie", "ERNIE"), ("vl", "VL"), ("r1", "R1"), ("it", "IT"),
    ];
    if let Some((_, brand)) = BRANDS.iter().find(|(k, _)| *k == w) {
        return brand.to_string();
    }
    // A brand with its version on it: qwen3 → Qwen3, gemini2 → Gemini2.
    let mut chars = w.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().chain(chars).collect(),
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spellings_of_one_model_share_a_key() {
        for (id, want) in [
            ("gpt-6-astra", "gpt-6-astra"),
            ("openai/gpt-6-astra", "gpt-6-astra"),
            ("OpenAI/GPT-6-Astra", "gpt-6-astra"),
            ("anthropic/claude-opus-5-5", "claude-opus-5-5"),
            ("us.anthropic.claude-opus-5-5-v1:0", "claude-opus-5-5"),
            ("anthropic.claude-opus-5-5-v1:0", "claude-opus-5-5"),
            ("claude-opus-5-5@20260101", "claude-opus-5-5"),
            ("claude-haiku-4-5-20251001", "claude-haiku-4-5"),
            ("gpt-4o-2024-08-06", "gpt-4o"),
            ("gpt-5.1", "gpt-5.1"),
            ("gpt-5.1-codex", "gpt-5.1-codex"),
            ("claude-sonnet-5[1m]", "claude-sonnet-5[1m]"),
            ("openai/gpt-oss-20b:free", "gpt-oss-20b:free"),
            ("qwen3:32b", "qwen3:32b"),
            ("deepseek-v4-pro", "deepseek-v4-pro"),
            ("deepseek-v4", "deepseek-v4"),
            ("o3", "o3"),
        ] {
            assert_eq!(key(id), want, "{id}");
        }
        assert!(same("openai/gpt-6-astra", "gpt-6-astra"));
        assert!(!same("claude-sonnet-5[1m]", "claude-sonnet-5"));
        assert!(!same("gpt-5", "gpt-5.1"));
    }

    #[test]
    fn models_read_as_people_call_them() {
        for (id, want) in [
            ("claude-opus-5-5", "Opus 5.5"),
            ("claude-sonnet-5", "Sonnet 5"),
            ("claude-fable-5-1", "Fable 5.1"),
            ("claude-haiku-4-5-20251001", "Haiku 4.5"),
            ("us.anthropic.claude-opus-5-5-v1:0", "Opus 5.5"),
            ("claude-3-5-sonnet-latest", "Sonnet 3.5 Latest"),
            ("claude-sonnet-5[1m]", "Sonnet 5 1M"),
            ("opus", "Opus"),
            ("sonnet[1m]", "Sonnet 1M"),
            ("gpt-5", "GPT-5"),
            ("gpt-6-astra", "GPT-6 Astra"),
            ("openai/gpt-6-astra", "GPT-6 Astra"),
            ("gpt-5.1-codex-max", "GPT-5.1 Codex Max"),
            ("gpt-4o-mini", "GPT-4o Mini"),
            ("o3", "o3"),
            ("o4-mini", "o4 Mini"),
            ("deepseek-v4-pro", "DeepSeek V4 Pro"),
            ("deepseek-flash", "DeepSeek Flash"),
            ("qwen3-coder-plus", "Qwen3 Coder Plus"),
            ("glm-4.6", "GLM-4.6"),
            ("kimi-k2", "Kimi K2"),
            ("gemini-2.5-pro", "Gemini 2.5 Pro"),
            ("grok-4", "Grok 4"),
            ("minimax-m2", "MiniMax M2"),
            ("something-else", "something-else"),
            ("my-proxy/Custom-Model", "my-proxy/Custom-Model"),
        ] {
            assert_eq!(name(id), want, "{id}");
        }
    }

    #[test]
    fn models_list_by_series_newest_first() {
        for (id, want) in [("claude-opus-5-5", Some("Opus")), ("sonnet[1m]", Some("Sonnet")), ("gpt-5.1-codex", Some("GPT")), ("o4-mini", Some("o 系列")),
            ("qwen3-coder", Some("Qwen")), ("deepseek-v4-pro", Some("DeepSeek")), ("something", None)] {
            assert_eq!(family(id).as_deref(), want, "{id}");
        }
        let mut ids = ["claude-sonnet-5", "claude-opus-4-8", "claude-haiku-4-5-20251001", "claude-opus-5-5", "claude-fable-5-1", "claude-opus-5", "claude-sonnet-4-6"];
        ids.sort_by_key(|id| order(id));
        assert_eq!(ids, ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]);
    }
}
