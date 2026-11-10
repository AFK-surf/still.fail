// One of a few (parts.mbt one_of's) as a node of the window's tree, made once: a few listed where it is, a row each, a
// radio group's (@kit.radio_group's roving keys); more, a select (select_node).

///|
/// One of a few in `parent` (one_of's, as a node), `value` among `options` (each value and its words) as each is now:
/// up to `one_of_listed_most` listed where it is, a row each (the theme's rows' least height and title, a row's corner,
/// the hover's ground under a mouse or a press), the chosen checked at its end (16, the accent); more, a select
/// (select_node). Listed: a radio group named `label` (each row a radio, on or off), one stop of Tab's (the chosen
/// one, else the first), ↑ ↓ moving along it round from its ends and Home, End to the first and the last, each choosing
/// what it comes to; a press or Space choosing the one pressed (`choose` given it; nothing for the one chosen already).
/// While `disabled()`, at 55% and taking no press.
#callsite(autofill(loc))
pub fn one_of_node(
  parent : @view.View,
  value : () -> String,
  options : () -> Array[(String, String)],
  choose : (String) -> Unit,
  label? : () -> String = fn() { "" },
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> Unit {
  let listed = fn() { options().length() <= one_of_listed_most }
  parent.box(made_for=loc, fn(b) {
    b.pick(fn() { listed() }, fn(p, as_list) {
      if !as_list {
        select_node(p, value, options, choose, label~, disabled~)
        return
      }
      p.box(fn(g) {
        // (its rows' nodes by their values, for the focus the arrows move)
        let rows : Map[String, @view.View] = Map([])
        let live = fn() { !disabled() }
        style_node(g, fn() { one_of_list })
        g.says(By(fn() { Some(@view.said(RadioGroup, label=label())) })) |> ignore
        // (a roving group, as @kit.radio_group's: ↑ ↓ to the one after and before, round from the ends, Home and End to
        // the first and the last, each chosen and its focus as it comes; only while one of its rows has the focus)
        g.on_key(fn(k) {
          let keys = @signals.untracked(options).map(fn(o) { o.0 })
          let n = keys.length()
          let at = keys.search_by(fn(v) { rows.get(v).map(fn(r) { r.focused() }).unwrap_or(false) })
          let to = match at {
            None => None
            Some(_) if k.mods != 0 || n == 0 || !@signals.untracked(live) => None
            Some(i) =>
              if k.code == @ui.key_code_down {
                Some((i + 1) % n)
              } else if k.code == @ui.key_code_up {
                Some((i + n - 1) % n)
              } else if k.code == @ui.key_code_home {
                Some(0)
              } else if k.code == @ui.key_code_end {
                Some(n - 1)
              } else {
                None
              }
          }
          match to {
            Some(i) => {
              let v = keys[i]
              if v != @signals.untracked(value) {
                choose(v)
              }
              match rows.get(v) {
                Some(r) => r.ask_focus(visible=true) |> ignore
                None => ()
              }
              true
            }
            None => false
          }
        })
        |> ignore
        g.each(fn() { options().map(fn(o) { o.0 }) }, fn(v) { v }, fn(slot, v) {
          let v = v.untracked()
          let words = fn() {
            match options().iter().find_first(fn(o) { o.0 == v }) {
              Some(o) => o.1
              None => ""
            }
          }
          let on = fn() { value() == v }
          // (Tab's stop: the chosen one, else the first)
          let stop = fn() {
            let all = options()
            on() || (!all.iter().any(fn(o) { o.0 == value() }) && all.get(0).map(fn(o) { o.0 == v }).unwrap_or(false))
          }
          slot.box(fn(r) {
            rows[v] = r
            style_node(r, fn() { one_of_row.then(@ui.style(min_h=Fixed(theme().items.least))) })
            r
            // (one_of_row_hot's hover ground: a mouse over any of it, or it pressed)
            .ground(By(fn() {
              if live() && (hovered_in_node(r) || r.pressed()) {
                @ui.tree_theme().color(Hover)
              } else {
                0L
              }
            }))
            .alpha(By(fn() { if disabled() { one_of_disabled_alpha } else { 1.0 } }))
            .presses(By(live))
            .focusable(By(live), keys=@view.focus_space)
            .tab_stop(By(stop))
            .says(By(fn() { Some(@view.said(Radio, label=words(), check=if on() { On } else { Off })) }))
            .on_press(fn() {
              if @signals.untracked(live) && !@signals.untracked(on) {
                choose(v)
              }
            })
            |> ignore
            let on_it = fn(d : @view.Drag) { r.finger_target(d.wx, d.wy) }
            r.gesture(
              @ui.touch_slop(),
              tap=fn(d) {
                if on_it(d) && @signals.untracked(live) && !@signals.untracked(on) {
                  choose(v)
                }
              },
              drag=fn(d) {
                if d.kind == Up && @ui.pointing() is Mouse && on_it(d) && @signals.untracked(live) && !@signals.untracked(on) {
                  choose(v)
                }
              },
            )
            |> ignore
            words_node(r, words, fn() { theme().rows.title }) |> ignore
            // (its words and its check apart: one_of_row's JBetween, what is left of the row between them)
            r.box(fn(gap) { gap.grow(Is(1.0)) |> ignore }) |> ignore
            r.show(on, at_once=true, fn(k) {
              icon_node(k, "check", one_of_check, By(fn() { theme().p.accent })) |> ignore
            })
          })
          |> ignore
        })
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// one_of's list: its rows one under the other, none apart (radio_group's `gap=0.0`).
// kept across runs: a value (no field of it changes)
let one_of_list : @ui.Style = @ui.css("w=Full")

///|
/// How far a disabled one_of's row is seen (one_of_row's `disabled{opacity=O55}`).
let one_of_disabled_alpha : Double = 0.55
