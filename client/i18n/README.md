# Words in each language

`catalog/<lang>/<part>.json`: the words people read, by key, in Chinese (`zh`) and English (`en`). Every part has the
same keys in both languages (`cargo test -p stillfail-i18n` checks it, and that `{names}` agree).

- A value is a string, `{name}` taking the value given as `name`; or, for words that change with a number,
  `{"one": "1 chat", "other": "{n} chats"}`, chosen by `n`.
- Keys start with their part's name: `web-mobile.home.title` is in `web-mobile.json`. `common.*` are shared words.
- Read as `t!("key", n = 3)` in Rust (core, station), `t("key", { n: 3 })` on the web (web/src/i18n.ts),
  `t("key", "n" to 3)` on Android (ui/I18n.kt).
- What agents are told (station instructions, migrations) and what people wrote stay as they are.
