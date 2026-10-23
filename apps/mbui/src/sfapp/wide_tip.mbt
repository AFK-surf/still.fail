// Tips in the wide frame (ember web/ui/src/parts.tsx Tip, parts.css.ts tooltip; the page's Tooltip.Provider, 400 ms):
// what a control does, said under it once the pointer has rested on it a moment, and the keys that do the same after
// it, quieter. The only way anything here explains itself on hover. None on a phone.

///|
/// How long the pointer rests on a control before its tip shows (the web's Tooltip.Provider delayDuration).
let tip_delay_ms : Double = 400.0

///|
/// `id`'s tip, saying `text` (nothing when empty); with `action`, the keys set for it after (settings' keymap).
fn wide_tip(c : @ui.Ctx, key : String, id : Int, text : String, action? : String = "") -> Unit {
  if !wide_on.val || text == "" || id == 0 {
    return
  }
  // (the keys set here: the core's prefs, as last drawn)
  let keys = match link_src.val {
    Some(src) if action != "" => @settings.keys_text((src.topic)("prefs", {}).value, action)
    _ => ""
  }
  @kit.tooltip(c, "tip/" + key, id, text, delay=tip_delay_ms, side=Bottom, look=fn(c, _, words) {
    tip_look(c, words, keys)
  })
  |> ignore
}

///|
/// A tip as the web draws it: small words on the primary ink, 5 by 10 in, 8 round, a soft shadow; the keys 8 after the
/// words at 60%.
fn tip_look(c : @ui.Ctx, words : String, keys : String) -> Unit {
  c.box(style=tip_box, fn() {
    c.box(style=tip_line, fn() {
      c.text(words, style=tip_words) |> ignore
      if keys != "" {
        c.box(style=tip_quiet, fn() { c.text(keys, style=tip_keys) |> ignore }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let tip_box : @ui.Style = @ui.style(px=S2_5, py=S1_25, bg=Primary, radius=Lg, max_w=@sf.tip_max, shadow=Md)

///|
// kept across runs: a value (no field of it changes)
let tip_line : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let tip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=OnPrimary)

///|
// kept across runs: a value (no field of it changes)
let tip_keys : @ui.TextStyle = @ui.text_style(size=Xs, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tip_quiet : @ui.Style = @ui.style(opacity=O60)
