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

///|
/// The product the core's cloud is (its prefs' `product`: still.fail, or monoid on monoid's cloud; "" before it has
/// said), as it changes: the words read it (branded).
let product_said : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// The core's `product` (its prefs'): its name in the words from now on.
pub fn set_product(said : String) -> Unit {
  product_said.set(said)
}

///|
/// The product's name: the core's; until it says, the build's (its variant's MBUI_PRODUCT: monoid's apps), else
/// still.fail.
pub fn product() -> String {
  match (product_said.get(), @ui.env("MBUI_PRODUCT")) {
    ("", "") => "still.fail"
    ("", built) => built
    (p, _) => p
  }
}

///|
fn name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-'
}

///|
/// `text` with still.fail's name standing alone the product's (client/i18n/brand.ts branded): not a host's part or an
/// address (app.still.fail, https://still.fail, noreply@still.fail, still.fail.app).
pub fn branded(text : String) -> String {
  let name = product()
  if name == "still.fail" || !text.contains("still.fail") {
    return text
  }
  let chars = text.to_array()
  let word = "still.fail".to_array()
  let out = StringBuilder::new()
  let mut i = 0
  while i < chars.length() {
    let at = i + word.length() <= chars.length() &&
      (for k = 0; k < word.length(); k = k + 1 {
        if chars[i + k] != word[k] {
          break false
        }
      } else {
        true
      })
    let before_ok = i == 0 || !(name_char(chars[i - 1]) || chars[i - 1] == '.' || chars[i - 1] == '/' || chars[i - 1] == '@')
    let j = i + word.length()
    let after_ok = j >= chars.length() ||
      !(name_char(chars[j]) || (chars[j] == '.' && j + 1 < chars.length() && name_char(chars[j + 1]) && chars[j + 1] != '-'))
    if at && before_ok && after_ok {
      out.write_string(name)
      i = j
    } else {
      out.write_char(chars[i])
      i += 1
    }
  }
  out.to_string()
}
