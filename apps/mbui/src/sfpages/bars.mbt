// 下方栏, one page for every frame (web/src/mobile/BarSettings.tsx BarSettingsScreen; the web's desktop has no bottom
// bar, so no page of it): this device's bottom bars, each a section of its own (its name, 当前 on the one in view,
// 使用 and 删除 at its end) over a card of its places; a new one made under them. What the core keeps (`bars`) and the
// page's state are the settings' (save_bars, bar_adding, bar_moves: let go of as the page is left). The bar is
// Small's alone, so the settings' row of it is too (settings_list.mbt); the page is laid out at any width all the same
// (one open as the screen grows wider stays).

///|
/// The page (BarSettingsScreen), in the frame it is given: what the bars are for under its title; each bar; 新建一栏;
/// what is kept of them, under all.
pub fn bars_page(c : @ui.Ctx, core : Core, frame : PageFrame) -> Unit {
  let (made, cur) = (core.bars)()
  let sets : Array[Array[String]] = made.copy()
  if @settings.bar_adding.get() {
    sets.push([])
  }
  // a place picked for bar `i` (one past the made ones: the one just made, kept with its first place)
  let pick_for = fn(i : Int, from : @sf.Beside) {
    let (now, _) = (core.bars)()
    let set = now.get(i).unwrap_or([])
    let left = @settings.all_places.filter(fn(p) { !set.contains(p) })
    let choices = left.map(fn(p) { @sf.choice(p, bar_place_name(p), icon=@sfbase.place_icon(p)) })
    @sf.pick(@sf.t("android-misc.bar.pick.title", args=[("n", (i + 1).to_string())]), choices, "", fn(place) {
      let (now, ncur) = (core.bars)()
      if i >= now.length() {
        @settings.bar_adding.set(false)
        @settings.save_bars(core, now + [[place]], ncur)
      } else {
        @settings.save_bars(core, now.mapi(fn(n, s) { if n == i && !s.contains(place) && s.length() < @settings.bar_size { s + [place] } else { s } }), ncur)
      }
    }, from~)
  }
  let blocks : Array[() -> Unit] = []
  for i, set in sets {
    let is_made = i < made.length()
    let n = (i + 1).to_string()
    blocks.push(fn() {
      @sf.section(
        c,
        @sf.t("android-misc.bar.set", args=[("n", n)]),
        actions=fn() {
          // the one in view says so where the others offer to be it
          if is_made && i == cur {
            @sf.pill(c, @sf.t("android-misc.bar.current"), tone=Accented)
          }
          if is_made && i != cur && @sf.action(c, "bar-use/" + i.to_string(), @sf.t("android-misc.bar.use")) {
            @settings.save_bars(core, made, i)
          }
          if sets.length() > 1 &&
            @sf.action(c, "bar-delete/" + i.to_string(), @sf.t("android-misc.bar.delete"), bad=true) {
            if !is_made {
              @settings.bar_adding.set(false)
            } else {
              let left : Array[Array[String]] = []
              for k, x in made {
                if k != i {
                  left.push(x)
                }
              }
              @settings.save_bars(core, left, if cur > i || cur >= left.length() { if cur - 1 < 0 { 0 } else { cur - 1 } } else { cur })
            }
          }
        },
        fn() {
          @sf.group(c, card=true, fn() {
            bar_card(c, core, i, set, made.length() == 1 && set.length() == 1, fn(from) { pick_for(i, from) })
          })
        },
      )
    })
  }
  blocks.push(fn() {
    @sf.group(c, fn() {
      let id = c.id("bar-new")
      if @sf.link_row(c, "bar-new", @sf.t("android-misc.bar.new"), chevron=false, lead=fn() {
          @sf.icon(c, "plus", size=bar_new_mark, color=@sf.link_ink()) |> ignore
        }) {
        @settings.bar_adding.set(true)
        pick_for(made.length(), Of(id))
      }
    })
  })
  blocks.push(fn() {
    @sf.page_note(c, @sf.t(if made.length() > 1 { "android-misc.bar.foot.many" } else { "android-misc.bar.foot.one" }))
  })
  @sf.page(c, on_back=core.pop, frame~, "bars", @sf.t("android-misc.bar.title"), blocks, lead=@sf.t("android-misc.bar.note"), small=@sf.t(
    "android-misc.bar.small",
  ))
}

///|
/// A place's name (the bar's words for it).
fn bar_place_name(place : String) -> String {
  @sf.t("android-misc.bar.place." + place)
}

///|
/// A bar's places (BarCard), on its group's card: four slots, each its mark over its name with a "−" at its corner
/// (none on the last place of the only bar), one held and moved sideways put where it is let go (by how many slots it
/// went), a screen reader's step moving it one along; with room left, a slot that adds one (`add`, from where it is).
fn bar_card(c : @ui.Ctx, core : Core, i : Int, set : Array[String], only : Bool, add : (@sf.Beside) -> Unit) -> Unit {
  let t = @sf.theme()
  // BarSettingsScreen's onMove: the place at `j` put at `to`
  let move = fn(j : Int, to : Int) {
    let (now, ncur) = (core.bars)()
    if to != j && i < now.length() && j < now[i].length() && to >= 0 && to < now[i].length() {
      let moved = now[i].copy()
      let p = moved.remove(j)
      moved.insert(to, p)
      @settings.save_bars(core, now.mapi(fn(n, s) { if n == i { moved } else { s } }), ncur)
    }
  }
  let moves = @settings.bar_moves
  c.box(style=bar_slots, fn() {
    for j, key in set {
      let id = c.id("bar-slot/" + i.to_string() + "/" + key)
      let held = i.to_string() + "/" + key
      // the finger's (detectHorizontalDragGestures): lifted once it goes sideways past the slop, following it; let go,
      // put by how many slots it went (a slot's width, the row's quarter)
      c.drag_on(id, axis=Horizontal)
      let lifted = match c.drag_of(id) {
        Some(d) => {
          let (dx, _) = d.take_move()
          if d.down && d.moving {
            moves[held] = moves.get(held).unwrap_or(0.0) + dx
          }
          if d.take_end() {
            let went = moves.get(held).unwrap_or(0.0)
            moves.remove(held)
            match c.rect_of(id) {
              Some((_, _, w, _)) if w > 0.0 => {
                let to = j + (went / w).round().to_int()
                move(j, if to < 0 { 0 } else if to >= set.length() { set.length() - 1 } else { to })
              }
              _ => ()
            }
          } else if !d.down {
            moves.remove(held)
          }
          d.down && d.moving
        }
        None => false
      }
      // a screen reader's (BarSettings.kt's actions 左移, 右移): one slot along
      if c.action_asked(id, Decrement) && j > 0 {
        move(j, j - 1)
      }
      if c.action_asked(id, Increment) && j < set.length() - 1 {
        move(j, j + 1)
      }
      // the slot, and its "−" over it beside (not inside) what the finger holds: a press on the "−" is its own
      let slot = c.box(style=if lifted { bar_slot_held } else { bar_slot }, fn() {
        let face = c.box(style=bar_face, id~, fn() {
          c.box(style=bar_face_words, fn() {
            c.box(style=bar_mark_room, fn() { (core.place_icon)(c, key, t.p.text) }) |> ignore
            c.text(bar_place_name(key), style=bar_place_words) |> ignore
          })
          |> ignore
        })
        c.semantics(face, Group, id~, label=bar_place_name(key), actions=[Decrement, Increment])
        if !only {
          c.layer(fn() {
            let rid = c.id("bar-remove/" + i.to_string() + "/" + key)
            if c.clicked(rid) {
              let (now, ncur) = (core.bars)()
              @settings.save_bars(core, now.mapi(fn(n, s) { if n == i { s.filter(fn(p) { p != key }) } else { s } }), ncur)
            }
            // in the slot's top right corner, concentric with it (so with the card's, the last slot's corner in the
            // card's), however wide a slot is
            let said = @sf.t("android-misc.bar.remove", args=[("name", bar_place_name(key))])
            c.box(style=bar_remove_at, fn() {
              let minus = c.box(style=bar_remove, id=rid, label=said, fn() {
                @sf.icon(c, "minus", size=bar_remove_mark, color=t.p.muted) |> ignore
              })
              c.semantics(minus, Button, id=rid, label=said)
            })
            |> ignore
          })
          |> ignore
        }
      })
      // held: where the finger has it, 8% bigger, over the other places (graphicsLayer, zIndex(2f))
      if lifted {
        c.look(slot, @ui.look(dx=moves.get(held).unwrap_or(0.0), scale=1.08))
        c.put_over(slot)
      }
    }
    if set.length() < @settings.bar_size {
      let aid = c.id("bar-add/" + i.to_string())
      if c.clicked(aid) {
        add(Of(aid))
      }
      c.box(style=bar_face, id=aid, fn() {
        c.box(style=bar_face_words, fn() {
          c.box(style=bar_add_ring, fn() {
            @sf.icon(c, "plus", size=bar_add_mark, color=t.p.subtle) |> ignore
          })
          |> ignore
          c.text(@sf.t("android-misc.bar.add"), style=bar_add_words) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    for _ in 0..<(@settings.bar_size - set.length() - 1) {
      c.box(style=bar_slot, fn() {  }) |> ignore
    }
  })
  |> ignore
}

// ── styles (BarSettings.kt) ─────────────────────────────────────────────

///|
/// The slots side by side, each a quarter of the card, as far apart as they go where it is wider than four slots.
// kept across runs: a value (no field of it changes)
let bar_slots : @ui.Style = @ui.css("row w=Full justify=JBetween")

///|
/// A slot: its corner round its "−" in its corner (Around: concentric with it at whatever room its card leaves).
// kept across runs: a value (no field of it changes)
let bar_slot : @ui.Style = @ui.style(w=@sf.grow, max_w=Fixed(bar_slot_most), radius=Around)

///|
/// A slot's widest: as wide as a phone's quarter of its card, its "−" by its mark wherever the card is wider.
let bar_slot_most : Double = 88.0

///|
/// A slot held: on the card's ground, raised (shadow(6), black at 14% both).
// kept across runs: a value (no field of it changes)
let bar_slot_held : @ui.Style = bar_slot.then(@ui.style(bg=Card, shadow=@sf.held_raised.cast()))

///|
/// What a slot shows, 12 over and 10 under it, in its middle.
// kept across runs: a value (no field of it changes)
let bar_face : @ui.Style = @ui.style(w=@sf.grow, max_w=Fixed(bar_slot_most), pt=S3, pb=S2_5, align=ACenter)

///|
/// Its mark over its name, 6 apart.
// kept across runs: a value (no field of it changes)
let bar_face_words : @ui.Style = @ui.css("gap=S1_5 align=ACenter")

///|
/// The mark's room, 30 high.
// kept across runs: a value (no field of it changes)
let bar_mark_room : @ui.Style = @ui.style(h=Fixed(bar_side), justify=JCenter)

///|
let bar_side : Double = 30.0

///|
// kept across runs: a value (no field of it changes)
let bar_place_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let bar_add_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
/// The "−" that takes a place out: 20 round, on the neutral wash, in from its slot's top right corner as far as makes
/// it concentric with its card's corner where the slot is the last (capsule_in: the group's corner less its half, less
/// the card's list_pad the slot is in; the slot round it there: bar_slot).
// kept across runs: a value (no field of it changes)
let bar_remove : @ui.Style = @ui.css("w=S5 h=S5 radius=Full bg=Neutral align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let bar_remove_at : @ui.Style = @ui.style(
  w=Full,
  p=@sf.room_of(@sf.capsule_in(@sf.group_corner, bar_remove_side) - @sf.list_pad),
  align=AEnd,
)

///|
let bar_remove_side : Double = 20.0

///|
let bar_remove_mark : Double = 12.0

///|
/// The add slot's ring: 30 round, its line 1.5.
// kept across runs: a value (no field of it changes)
let bar_add_ring : @ui.Style = @ui.style(
  w=Fixed(bar_side),
  h=Fixed(bar_side),
  radius=Full,
  border=B1_5,
  border_color=Line,
  align=ACenter,
  justify=JCenter,
)

///|
let bar_add_mark : Double = 22.0

///|
/// 新建一栏's mark.
let bar_new_mark : Double = 20.0
