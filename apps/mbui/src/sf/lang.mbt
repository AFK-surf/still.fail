// The language the app's words are said in, as still.fail's Android app has it (data/I18n.kt): the core's (its prefs'
// `lang`: as chosen, else as the device is, which it is told: sfcore's client.device `locale`), and until the core
// says, the device's (MBUI_LOCALE, its host's: CoreHost.java, apple_engine.m). Chinese for a locale that is (zh…) or
// none, else English (client/i18n/README.md).

///|
/// What the core said ("zh", "en"; "" before it has), as it changes: what says words reads it (language, t), so what
/// is made once says them again as it is set otherwise.
let lang_said : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// "zh" or "en" for a locale (BCP 47: zh-CN, en-US, …; "" none).
pub fn language_of(locale : String) -> String {
  let l = locale.trim(chars=" ").to_lower()
  if l == "" || l.has_prefix("zh") {
    "zh"
  } else {
    "en"
  }
}

///|
/// The language now: "zh" or "en".
pub fn language() -> String {
  let said = lang_said.get()
  if said != "" {
    said
  } else {
    language_of(@ui.env("MBUI_LOCALE"))
  }
}

///|
/// The core's `lang` (its prefs'), None or anything else: the device's from now on (I18n.kt follow).
pub fn set_language(said : String?) -> Unit {
  lang_said.set(
    match said {
      Some("zh") => "zh"
      Some("en") => "en"
      _ => ""
    },
  )
}
