//! Which language the station's words are said in (client/i18n). A station serves many people, so there is no one
//! language for it: a request is answered in the one it asks in (the core says so in `stillfail-lang` on each request;
//! a browser in Accept-Language), and what the station says on its own (in Slack, on its machine) is in the station's
//! (config.json `language`). Chinese where nothing says otherwise, as before there were languages. What agents are
//! told is not translated.

use std::future::Future;
use std::sync::atomic::{AtomicU8, Ordering};

pub use stillfail_i18n::{Lang, t, tr};

/// The header a core names its person's language in (client/core/src/station.rs `LANG_HEADER`).
pub const HEADER: &str = "stillfail-lang";

tokio::task_local! {
    static ASKED: Lang;
}

static STATION: AtomicU8 = AtomicU8::new(0);

/// The station's own language: what it says unasked (Slack, its command line, its notices).
pub fn station() -> Lang {
    if STATION.load(Ordering::Relaxed) == 1 { Lang::En } else { Lang::Zh }
}

/// Sets the station's own language, as config.json says (`language`; none: Chinese).
pub fn set_station(language: Option<&str>) {
    let lang = language.map(Lang::from_locale).unwrap_or_default();
    STATION.store(if lang == Lang::En { 1 } else { 0 }, Ordering::Relaxed);
}

/// The language of the request being answered; outside one, the station's own.
pub fn spoken() -> Lang {
    ASKED.try_with(|lang| *lang).unwrap_or_else(|_| station())
}

/// Runs `work` as an answer to a request in `lang`: what it says (errors, words on the pages) is said in it.
pub async fn answering<F: Future>(lang: Lang, work: F) -> F::Output {
    ASKED.scope(lang, work).await
}

/// Does `work` as an answer to a request in `lang` (`answering`, for work that does not wait).
pub fn answering_now<R>(lang: Lang, work: impl FnOnce() -> R) -> R {
    ASKED.sync_scope(lang, work)
}

/// The language a core asks in: its `stillfail-lang`; Chinese for a core from before languages, which says none.
pub fn of_core<'a>(mut headers: impl Iterator<Item = (&'a str, &'a str)>) -> Lang {
    headers.find(|(k, _)| k.eq_ignore_ascii_case(HEADER)).map(|(_, v)| Lang::from_locale(v)).unwrap_or_default()
}

/// The language a browser asks in: as a core's, else its Accept-Language (the first named; `*` names none).
pub fn of_browser<'a>(headers: impl Iterator<Item = (&'a str, &'a str)>) -> Lang {
    let headers: Vec<(&str, &str)> = headers.collect();
    if let Some((_, v)) = headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(HEADER)) {
        return Lang::from_locale(v);
    }
    let accepted = headers.iter().find(|(k, _)| k.eq_ignore_ascii_case("accept-language")).map(|(_, v)| *v).unwrap_or("");
    let first = accepted.split([',', ';']).next().unwrap_or("").trim();
    Lang::from_locale(if first == "*" { "" } else { first })
}

/// A hyper request's headers, as `of_core` and `of_browser` read them.
pub fn headers(map: &hyper::HeaderMap) -> impl Iterator<Item = (&str, &str)> {
    map.iter().filter_map(|(k, v)| v.to_str().ok().map(|v| (k.as_str(), v)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_request_is_answered_in_its_language_and_the_rest_in_the_stations() {
        assert_eq!(of_core([("Stillfail-Lang", "en")].into_iter()), Lang::En);
        assert_eq!(of_core([("accept-language", "en-US")].into_iter()), Lang::Zh);
        assert_eq!(of_browser([("accept-language", "en-US,zh;q=0.8")].into_iter()), Lang::En);
        assert_eq!(of_browser([("accept-language", "zh-CN,en;q=0.8")].into_iter()), Lang::Zh);
        assert_eq!(of_browser(std::iter::empty()), Lang::Zh);
        assert_eq!(answering(Lang::En, async { spoken() }).await, Lang::En);
        assert_eq!(spoken(), station());
    }
}
