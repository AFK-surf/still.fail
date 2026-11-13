// The parts whose arguments can be changed on the page (a story's Playground, Storybook's controls): each a set of
// controls over the part made with what they say, and the call that makes it so, as it is written.

///|
/// A Playground: its controls made in the first node, the part as they say in the second, and the call that makes it.
struct Play {
  controls : (@view.View) -> Unit
  preview : (@view.View) -> Unit
  code : () -> String
}

///|
/// A control on its row: what it changes, then the control.
fn control(v : @view.View, label : String, make : (@view.View) -> Unit) -> Unit {
  // (side by side where the window has the room, else its name over it)
  let wide = fn() { side_shown(v.window().0) }
  v.box(fn(r) {
    r
    .row(By(wide))
    .gap(By(fn() { if wide() { 12.0 } else { 4.0 } }))
    .lines_up(By(fn() { if wide() { Some(Middle) } else { None } }))
    .min_height(Is(Some(44.0)))
    |> ignore
    r.box(fn(l) {
      l.width(By(fn() { if wide() { Some(96.0) } else { None } })) |> ignore
      @sf.words_node(l, fn() { label }, fn() { @sf.meta }) |> ignore
    })
    |> ignore
    r.box(fn(c) {
      c.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      make(c)
    })
    |> ignore
  })
  |> ignore
}

///|
fn text_control(v : @view.View, label : String, now : @signals.Signal[String]) -> Unit {
  control(v, label, fn(c) {
    c.max_width(Is(Some(420.0))) |> ignore
    @sf.input_node(c, @ui.Field::new(text=@signals.untracked(fn() { now.get() })), small=true, edited=fn(t) { now.set(t) })
    |> ignore
  })
}

///|
fn choice_control(v : @view.View, label : String, names : Array[String], now : @signals.Signal[Int]) -> Unit {
  control(v, label, fn(c) { @sf.seg_node(c, fn() { names }, fn() { now.get() }, fn(i) { now.set(i) }, said=label) |> ignore })
}

///|
fn bool_control(v : @view.View, label : String, now : @signals.Signal[Bool]) -> Unit {
  control(v, label, fn(c) { @sf.switch_node(c, fn() { now.get() }, fn(on) { now.set(on) }, fn() { label }, small=true) })
}

///|
/// Words as a string literal is written.
fn quoted(words : String) -> String {
  "\"" + words.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") + "\""
}

///|
/// The arguments said, each `, name=value`, those at their default left out.
fn said_args(args : Array[(Bool, String)]) -> String {
  args.filter(fn(a) { a.0 }).map(fn(a) { ", " + a.1 }).join("")
}

///|
let tones : Array[(String, @sf.Tone)] = [
  ("Plain", Plain),
  ("Primary", Primary),
  ("Ghost", Ghost),
  ("Danger", Danger),
  ("DangerSolid", DangerSolid),
  ("GhostDanger", GhostDanger),
]

///|
let button_icons : Array[String] = ["", "plus", "refresh", "share", "copy"]

///|
fn button_play() -> Play {
  let label = @signals.signal("保存")
  let tone = @signals.signal(1)
  let icon = @signals.signal(0)
  let busy = @signals.signal(false)
  let disabled = @signals.signal(false)
  let across = @signals.signal(false)
  {
    controls: fn(v) {
      text_control(v, "label", label)
      choice_control(v, "tone", tones.map(fn(t) { t.0 }), tone)
      choice_control(v, "icon", ["无", "plus", "refresh", "share", "copy"], icon)
      bool_control(v, "busy", busy)
      bool_control(v, "disabled", disabled)
      bool_control(v, "across", across)
    },
    preview: fn(v) {
      v.pick(fn() { (tone.get(), icon.get(), across.get()) }, at_once=true, fn(o, k) {
        @sf.button_node(
          o,
          fn() { label.get() },
          fn() {  },
          tone=tones[k.0].1,
          icon=button_icons[k.1],
          across=k.2,
          busy=fn() { busy.get() },
          disabled=fn() { disabled.get() },
        )
        |> ignore
      })
    },
    code: fn() {
      "@sf.button_node(v, fn() { \{quoted(label.get())} }, fn() { … }" +
      said_args([
        (tone.get() != 0, "tone=\{tones[tone.get()].0}"),
        (icon.get() != 0, "icon=\{quoted(button_icons[icon.get()])}"),
        (busy.get(), "busy=fn() { true }"),
        (disabled.get(), "disabled=fn() { true }"),
        (across.get(), "across=true"),
      ]) +
      ")"
    },
  }
}

///|
fn wide_button_play() -> Play {
  let label = @signals.signal("继续")
  let primary = @signals.signal(true)
  let danger = @signals.signal(false)
  let busy = @signals.signal(false)
  let enabled = @signals.signal(true)
  {
    controls: fn(v) {
      text_control(v, "label", label)
      bool_control(v, "primary", primary)
      bool_control(v, "danger", danger)
      bool_control(v, "busy", busy)
      bool_control(v, "enabled", enabled)
    },
    preview: fn(v) {
      v.pick(fn() { (primary.get(), danger.get()) }, at_once=true, fn(o, k) {
        @sf.wide_button_node(o, fn() { label.get() }, fn() {  }, k.0, danger=k.1, busy=fn() { busy.get() }, enabled=fn() {
          enabled.get()
        })
        |> ignore
      })
    },
    code: fn() {
      "@sf.wide_button_node(v, fn() { \{quoted(label.get())} }, fn() { … }, \{primary.get()}" +
      said_args([
        (danger.get(), "danger=true"),
        (busy.get(), "busy=fn() { true }"),
        (!enabled.get(), "enabled=fn() { false }"),
      ]) +
      ")"
    },
  }
}

///|
fn switch_play() -> Play {
  let label = @signals.signal("通知")
  let on = @signals.signal(true)
  let small = @signals.signal(false)
  let disabled = @signals.signal(false)
  {
    controls: fn(v) {
      text_control(v, "label", label)
      bool_control(v, "on", on)
      bool_control(v, "small", small)
      bool_control(v, "disabled", disabled)
    },
    preview: fn(v) {
      v.pick(fn() { small.get() }, at_once=true, fn(o, small) {
        @sf.switch_node(o, fn() { on.get() }, fn(now) { on.set(now) }, fn() { label.get() }, small~, disabled=fn() {
          disabled.get()
        })
      })
    },
    code: fn() {
      "@sf.switch_node(v, fn() { on.get() }, fn(now) { on.set(now) }, fn() { \{quoted(label.get())} }" +
      said_args([(small.get(), "small=true"), (disabled.get(), "disabled=fn() { true }")]) +
      ")"
    },
  }
}

///|
fn input_play() -> Play {
  let field = @ui.Field::new()
  let placeholder = @signals.signal("搜索对话")
  let label = @signals.signal("")
  let secret = @signals.signal(false)
  let small = @signals.signal(false)
  let disabled = @signals.signal(false)
  {
    controls: fn(v) {
      text_control(v, "placeholder", placeholder)
      text_control(v, "label", label)
      bool_control(v, "secret", secret)
      bool_control(v, "small", small)
      bool_control(v, "disabled", disabled)
    },
    preview: fn(v) {
      v.pick(fn() { (label.get(), secret.get(), small.get()) }, at_once=true, fn(o, k) {
        @sf.input_node(o, field, placeholder_by=fn() { placeholder.get() }, label=k.0, secret=k.1, small=k.2, disabled=fn() {
          disabled.get()
        })
        |> ignore
      })
    },
    code: fn() {
      "@sf.input_node(v, @ui.Field::new()" +
      said_args([
        (placeholder.get() != "", "placeholder=\{quoted(placeholder.get())}"),
        (label.get() != "", "label=\{quoted(label.get())}"),
        (secret.get(), "secret=true"),
        (small.get(), "small=true"),
        (disabled.get(), "disabled=fn() { true }"),
      ]) +
      ")"
    },
  }
}

///|
let pill_tones : Array[(String, @sf.PillTone)] = [
  ("Neutral", Neutral),
  ("Green", Green),
  ("Blue", Blue),
  ("Amber", Amber),
  ("Red", Red),
  ("Accented", Accented),
]

///|
let pill_icons : Array[String] = ["", "star", "check", "bot", "zap"]

///|
fn pill_play() -> Play {
  let words = @signals.signal("测试版")
  let tone = @signals.signal(2)
  let icon = @signals.signal(0)
  {
    controls: fn(v) {
      text_control(v, "words", words)
      choice_control(v, "tone", pill_tones.map(fn(t) { t.0 }), tone)
      choice_control(v, "icon", ["无", "star", "check", "bot", "zap"], icon)
    },
    preview: fn(v) {
      v.pick(fn() { (tone.get(), icon.get()) }, at_once=true, fn(o, k) {
        @sf.pill_node(o, fn() { words.get() }, tone=pill_tones[k.0].1, icon=pill_icons[k.1]) |> ignore
      })
    },
    code: fn() {
      "@sf.pill_node(v, fn() { \{quoted(words.get())} }" +
      said_args([
        (tone.get() != 0, "tone=\{pill_tones[tone.get()].0}"),
        (icon.get() != 0, "icon=\{quoted(pill_icons[icon.get()])}"),
      ]) +
      ")"
    },
  }
}

///|
let parts_said : Array[Double?] = [Some(0.0), Some(0.25), Some(0.5), Some(0.75), Some(1.0), None]

///|
fn progress_play() -> Play {
  let part = @signals.signal(2)
  {
    controls: fn(v) { choice_control(v, "part", ["0", "25%", "50%", "75%", "100%", "不定"], part) },
    preview: fn(v) {
      let t = @sf.theme
      @sf.progress_node(v, fn() { parts_said[part.get()] }, fn() { t().p.line }, fn() { t().p.accent }) |> ignore
      side_by_side(v, fn(r) {
        @sf.progress_ring_node(r, 24.0, fn() { parts_said[part.get()].unwrap_or(0.3) }, fn() { t().p.accent }) |> ignore
        @sf.progress_spinner_node(r, fn() { parts_said[part.get()] }) |> ignore
      })
    },
    code: fn() {
      let said = match parts_said[part.get()] {
        Some(p) => "Some(\{p})"
        None => "None"
      }
      "@sf.progress_node(v, fn() { \{said} }, fn() { @sf.theme().p.line }, fn() { @sf.theme().p.accent })"
    },
  }
}
