// A page in a panel of its own on the tape (laid out Medium: the frame's pane_round), its head the bar a chat's page has
// there (chat_page.mbt chat_bar), not a phone's large title nor the web's page head over what it shows: as high as a
// chat's, its title in a chat's title's words where a chat's stands, back before it where there is somewhere to go back
// to (a round button concentric with the panel's top left corner), what the page is for said by a mark beside its
// title, what it does at its end (its buttons concentric with the panel's top right corner); what it shows right under
// it. The panel's top corners hold the bar's ends, as a chat's do: no room left over the page, and every page in a
// panel starting as a chat's does (the user, 2026-10-25: a large title pushed under the corners wasted the room and stood
// apart from the other pages).

///|
/// `title`'s page holding `content` in a panel of its own (look_page's, laid out by `look`): the bar (pane_bar), then a
/// head of its own (`head`: a station's, a profile's), what it is for (`lead`) and what it holds, a block at a time. A
/// page with a head of its own has its name there, big: its bar says what it is of (`small`: Station, Profile), not the
/// name again.
fn pane_page(
  c : @ui.Ctx,
  core : Core,
  frame : PageFrame,
  look : Look,
  key : String,
  title : String,
  content : Array[() -> Unit],
  lead~ : String,
  about~ : String,
  actions? : () -> Unit,
  head? : () -> Unit,
  small~ : String,
) -> Unit {
  c.box(style=pane_page_fill, fn() {
    let back = frame.back.map(fn(label) { (label, fn() { (core.pop)() }) })
    match head {
      Some(_) => pane_bar(c, back, small, about~, actions?)
      None => pane_bar(c, back, title, about~, small~, actions?)
    }
    let blocks : Array[() -> Unit] = []
    match head {
      Some(h) => blocks.push(fn() { c.box(style=if look == Narrow { pane_head_narrow } else { desk_first }, h) |> ignore })
      None => ()
    }
    if lead != "" {
      blocks.push(fn() {
        c.box(style=if look == Narrow { narrow_lead_box } else { pane_lead_wide }, fn() {
          c.text(lead, style=narrow_lead) |> ignore
        })
        |> ignore
      })
    }
    match look {
      Narrow => {
        for b in content {
          blocks.push(b)
        }
        // 30 under what it shows (the narrow pages' foot), then the frame's room
        let foot = narrow_foot + frame.foot
        blocks.push(fn() { c.box(style=@ui.style(w=Full, h=Fixed(foot)), fn() {  }) |> ignore })
        c.list("settings/" + key, blocks.length(), 80.0, fn(i) { (blocks[i])() }) |> ignore
      }
      Wide => {
        for i, b in content {
          let first = i == 0 && blocks.length() == 0
          blocks.push(fn() { c.box(style=if first { desk_first } else { desk_block }, fn() { b() }) |> ignore })
        }
        desk_lanes(c, key, blocks, foot=frame.foot)
      }
    }
  })
  |> ignore
}

///|
/// The bar of a page in a panel of its own, as a chat's there (chat_bar: its measures, its title's words and place): back
/// (where it goes, said; what it does) a round button before the title in the panel's top left corner, concentric with
/// it; the title, `small` (what the page is of) after it, `about` said by a mark beside them; `actions` at its end.
fn pane_bar(
  c : @ui.Ctx,
  back : (String, () -> Unit)?,
  title : String,
  about? : String = "",
  small? : String = "",
  actions? : () -> Unit,
) -> Unit {
  let (room_l, room_r, ml, mr) = page_bar_room()
  let room = fn(x : Double) { c.box(style=@ui.style(w=Fixed(x), h=Full), fn() {  }) |> ignore }
  c.box(style=chat_bar_row_tape(), moves="page-bar", fn() {
    room(ml)
    c.box(style=chat_bar_box_tape(), fn() {
      match back {
        Some((label, go)) => {
          room(@sf.tape_bar_start(room_l))
          if icon_button(c, "settings-back", "chevron-left", label~) {
            go()
          }
        }
        None => room(room_l)
      }
      c.box(style=chat_bar_title_row, keep=true, fn() {
        c.text(title, style=chat_title_words) |> ignore
        if small != "" {
          c.text(small, style=pane_bar_small) |> ignore
        }
        if about != "" {
          @sf.about(c, "settings-about", about, label=@sf.t("web-main.about"))
        }
      })
      |> ignore
      match actions {
        Some(f) => c.box(style=chat_bar_buttons, fn() { f() }) |> ignore
        None => ()
      }
      room(room_r)
    })
    |> ignore
    room(mr)
  })
  |> ignore
}

///|
/// All of the panel, its bar over what scrolls.
// kept across runs: a value (no field of it changes)
let pane_page_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A head of its own under the bar, laid out narrow: in the page's room as its cards, 8 under the bar.
// kept across runs: a value (no field of it changes)
let pane_head_narrow : @ui.Style = @ui.css("w=Full px=S3 pt=S2 pb=S2_5")

///|
/// What the page is for under the bar, laid out wide: in the column, as its blocks, 16 under the bar.
// kept across runs: a value (no field of it changes)
let pane_lead_wide : @ui.Style = @ui.css("w=Full px=S4 pt=S4")

///|
/// What the page is of, after its title in the bar: the secondary words.
// kept across runs: a value (no field of it changes)
let pane_bar_small : @ui.TextStyle = @sf.secondary.then(@ui.text_style(wrap=false))
