// A page in a panel of its own on the tape (laid out Medium: the frame's pane_round), its head the bar a chat's page has
// there (chat_page.mbt chat_bar), not a phone's large title nor the web's page head over what it shows: as high as a
// chat's, its title in a chat's title's words where a chat's stands, back before it where there is somewhere to go back
// to (a round button, concentric with the panel's top left corner), what the page is for said by a mark beside its
// title, what it does at its end; what it shows right under it (the library's page, @sf.page's `barred`). The tape's
// bars and the sidebar's first row on one line (@sf.tape_bar_over); no room left over the page (the user, 2026-10-25: a
// large title pushed under the corners wasted the room and stood apart from the other pages).

///|
/// A page in a panel of its own: the bar (pane_bar), then `page` (the library's, under it). A page with a head of its
/// own (`head`: a station's, a profile's, its name big there) has what it is of in its bar (`small`: Station, Profile),
/// not its name again; one whose title names no one (an account's 账号) its title.
fn pane_page(
  c : @ui.Ctx,
  back : (String, () -> Unit)?,
  title : String,
  about? : String = "",
  small? : String = "",
  actions? : () -> Unit,
  head? : () -> Unit,
  page : () -> Unit,
) -> Unit {
  c.box(style=pane_page_fill, fn() {
    match head {
      Some(_) if small != "" => pane_bar(c, back, small, about~, actions?)
      _ => pane_bar(c, back, title, about~, small~, actions?)
    }
    c.box(style=pane_page_rest, fn() { page() }) |> ignore
  })
  |> ignore
}

///|
/// The bar of a page in a panel of its own, as a chat's there (chat_bar: its measures, its title's words and place): back
/// (where it goes, said; what it does) a round button before the title in the panel's top left corner; the title,
/// `small` (what the page is of) after it, `about` said by a mark beside them; `actions` at its end.
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
/// All of the panel, its bar over the page.
// kept across runs: a value (no field of it changes)
let pane_page_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// What the bar leaves of it.
// kept across runs: a value (no field of it changes)
let pane_page_rest : @ui.Style = @ui.style(w=Full, h=@sf.grow)

///|
/// What the page is of, after its title in the bar: the secondary words.
// kept across runs: a value (no field of it changes)
let pane_bar_small : @ui.TextStyle = @sf.secondary.then(@ui.text_style(wrap=false))
