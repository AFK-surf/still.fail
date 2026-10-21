// A form (Radix's Form): fields, each its label over its control and, once it is wrong, why, and a button that hands
// them on. A field is checked as the web's constraints check one (needed, an email, a number, the view's own check);
// what is wrong shows once the field has been left after typing in it or a hand-on was tried, and goes as soon as it
// is right. Handing on with something wrong hands nothing on and puts the focus on the first wrong field. Enter in a
// field hands on as the button does.

///|
/// What a form field takes: words, an email, a password (dots), a number.
pub(all) enum FieldKind {
  Words
  Email
  Secret
  Number
} derive(Eq, Show)

///|
/// A form's field: its name (its value's key), its label, what it takes, whether it is needed, its placeholder, and
/// the view's own check (what is wrong with the words given, "" nothing).
pub(all) struct FormField {
  name : String
  label : String
  kind : FieldKind
  required : Bool
  placeholder : String
  check : (String) -> String
}

///|
/// A form field `name`, labelled `label`.
pub fn form_field(
  name : String,
  label : String,
  kind? : FieldKind = Words,
  required? : Bool = false,
  placeholder? : String = "",
  check? : (String) -> String = fn(_) { "" },
) -> FormField {
  { name, label, kind, required, placeholder, check }
}

///|
/// What a form says when a field is wrong (still.fail's Chinese by default).
pub(all) struct FormWords {
  missing : String
  email : String
  number : String
}

///|
// kept across runs: a constant: its fields are not mut, nothing changes it
pub let form_words : FormWords = { missing: "请填写此项", email: "请输入有效的邮箱地址", number: "请输入数字" }

///|
/// What a form reports: its fields' words by name, whether they were handed on this frame (all right), and what is
/// wrong with each (shown or not yet).
pub(all) struct FormResult {
  values : Map[String, String]
  submitted : Bool
  errors : Map[String, String]
}

///|
/// A form's state between frames: whether a hand-on was tried, which fields have been left after typing, which had
/// the focus last frame.
priv struct FormState {
  mut tried : Bool
  touched : Map[String, Bool]
  focused : Map[String, Bool]
  /// each field's words, by its name (its editor shows them)
  fields : Map[String, @ui.Field]
}

///|
/// What is wrong with `text` in `f` ("" nothing).
pub fn field_error(f : FormField, text : String, words? : FormWords = form_words) -> String {
  let s = text.trim().to_string()
  if s == "" {
    return if f.required { words.missing } else { "" }
  }
  match f.kind {
    Email => {
      let at = s.find("@")
      let ok = match at {
        Some(i) => i > 0 && s.view(start_offset=i + 1).contains(".") && !s.contains(" ")
        None => false
      }
      if !ok {
        return words.email
      }
    }
    Number => if !is_number(s) { return words.number }
    _ => ()
  }
  (f.check)(text)
}

///|
/// `key`'s form (see the file's head) of `fields`, its button saying `submit`, named `named` for the semantics tree.
pub fn form(
  c : @ui.Ctx,
  key : String,
  fields : Array[FormField],
  submit? : String = "提交",
  named? : String = "",
  words? : FormWords = form_words,
  w? : @ui.Size = Fill(1.0),
) -> FormResult {
  let t = c.theme()
  let id = c.id(key)
  install()
  let st = match kit.val.forms.get(id) {
    Some(s) => s
    None => {
      let s = { tried: false, touched: {}, focused: {}, fields: {} }
      kit.val.forms[id] = s
      s
    }
  }
  let values : Map[String, String] = {}
  let errors : Map[String, String] = {}
  let mut entered = false
  let mut pressed = false
  let fi = c.box(w~, gap=16.0, fn() {
    for f in fields {
      let ek = key + "/" + f.name
      let field = match st.fields.get(f.name) {
        Some(x) => x
        None => {
          let x = @ui.Field::new()
          st.fields[f.name] = x
          x
        }
      }
      // known from last frame: what is wrong decides the field's edge as it is built
      let shown_error = (st.tried || st.touched.contains(f.name)) &&
        field_error(f, field.text(), words~) != ""
      c.box(gap=6.0, fn() {
        label(c, f.label, for_id=c.id(ek), field=true, size=t.font, weight=500) |> ignore
        let mut got = ""
        pill_field(
          c,
          ek,
          Fill(1.0),
          false,
          f.kind == Secret,
          f.placeholder,
          fn(e) {
            got = e.text
            if e.submitted is Some(_) {
              entered = true
            }
          },
          fn() {  },
          invalid=shown_error,
          field~,
        )
        values[f.name] = got
        let wrong = field_error(f, got, words~)
        errors[f.name] = wrong
        // left after typing in it: what is wrong with it shows from now on
        let now_focused = c.editor_focused(ek)
        if st.focused.get(f.name).unwrap_or(false) && !now_focused && got != "" {
          st.touched[f.name] = true
        }
        st.focused[f.name] = now_focused
        if (st.tried || st.touched.contains(f.name)) && wrong != "" {
          c.text(wrong, size=t.font_sm, color=t.danger, line=18.0) |> ignore
        }
      })
      |> ignore
    }
    c.box(dir=Row, pt=4.0, fn() {
      if button(c, submit, key=key + "/submit").clicked {
        pressed = true
      }
    })
    |> ignore
  })
  c.semantics(fi, Form, label=named)
  let mut submitted = false
  if pressed || entered {
    st.tried = true
    match fields.search_by(fn(f) { errors.get(f.name).unwrap_or("") != "" }) {
      Some(k) => c.focus_on(c.id(key + "/" + fields[k].name), visible=true)
      None => submitted = true
    }
  }
  { values, submitted, errors }
}

///|
/// Whether `s` is a number as a number field takes one: a sign, digits, at most one point among them.
fn is_number(s : String) -> Bool {
  let mut digits = 0
  let mut points = 0
  for i, ch in s {
    if ch >= '0' && ch <= '9' {
      digits += 1
    } else if ch == '.' {
      points += 1
    } else if !((ch == '-' || ch == '+') && i == 0) {
      return false
    }
  }
  digits > 0 && points <= 1
}
