// The search at the top of the chats' lists with a finger (ember web/src/mobile/Home.tsx SearchField, SearchPage;
// apps/android chat/screens/Search.kt), in every tier (with a mouse ⌘K's panel has it: a finger has no keys to press):
// a field at a list's top; tapped, the lists go up and away with their bar, the field comes up from where it was to
// the top of the lists' box (narrowing as 取消 comes in beside it), and under it what the words find (the finder,
// switcher.mbt: the same as ⌘K's). Back goes from one kind to all of them first; 取消 (or back) puts the field back
// in the list. A row opened goes where the shell has it, the search left open in the lists' box.

///|
/// The search's page as it stands (what it finds is sfpages' finder: switcher.mbt): open (its field off the list: `from`,
/// its top in the window when tapped, and `wide`, its width there), going back (`leaving`); the field to take the
/// focus as it opens. Opened by the keys (⌘K laid out Small: `summoned`), what can be done here among what it finds
/// (`offered`), and whether over another page than the lists (`over`: the shell's, search_over).
priv struct Search {
  mut open : Bool
  mut leaving : Bool
  mut from : Double
  mut wide : Double
  mut focus : Bool
  mut summoned : Bool
  mut over : Bool
  mut offered : Array[Offered]
}

///|
let search : Search = {
  open: false,
  leaving: false,
  from: 0.0,
  wide: 0.0,
  focus: false,
  summoned: false,
  over: false,
  offered: [],
}

///|
/// A search open as the app starts (src/sffix's modes search-results and search-jobs, the Android app's
/// SearchResultsTest twins): the words typed, the kind alone ("" every kind); its field come up, the keyboard away.
let search_at_start : Ref[(String, String)?] = Ref(None)

///|
/// What a fixture mode opens of the search (open_fixture_mode).
pub fn open_search_mode(mode : String) -> Unit {
  if mode == "search-results" || mode == "search-results-dark" {
    search_at_start.val = Some(("登录", ""))
  } else if mode == "search-jobs" || mode == "search-jobs-dark" {
    search_at_start.val = Some(("登录", "job"))
  }
}

///|
/// The search the app starts with, opened as Home first builds.
pub fn search_start(c : @ui.Ctx) -> Unit {
  match search_at_start.val {
    Some((q, k)) => {
      search_at_start.val = None
      search.open = true
      finder_start(q, kind=k)
      search_up(c).snap(1.0)
    }
    None => ()
  }
}

///|
fn search_reset() -> Unit {
  search_at_start.val = None
  search.open = false
  search.leaving = false
  search.from = 0.0
  search.wide = 0.0
  search.focus = false
  search.summoned = false
  search.over = false
  search.offered = []
}

///|
/// How long the field takes to come up (Ease.Arrive) and to go back (Ease.Standard), and how far the list goes up
/// meanwhile (Home.kt, Search.kt).
pub let search_in_ms : Double = 280.0

///|
pub let search_out_ms : Double = 240.0

///|
pub let search_list_rise : Double = 56.0

///|
/// The search's way up: 0 its field in the list, 1 at the top (Search.kt `up`, Home.kt `away`: the same times).
fn search_up(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "search/up", 0.0, global=true)
}

///|
/// How far Home is away under the search (0 none).
pub fn search_away(c : @ui.Ctx) -> Double {
  if search.open && !search.over {
    search_up(c).get()
  } else {
    0.0
  }
}

///|
/// The bottom bar out of the search's way while it is open (Home.kt app.barAway): from the tap until it starts back.
pub fn search_bar_away() -> Bool {
  search.open && !search.leaving && !search.over
}

///|
/// The field at the list's top tapped: the search opens from it (its top in the window, its width).
fn search_open(c : @ui.Ctx, from : Double, wide : Double) -> Unit {
  if search.open {
    return
  }
  search.open = true
  search.leaving = false
  search.from = from
  search.wide = wide
  search.focus = true
  let up = search_up(c)
  up.snap(0.0)
  up.animate(1.0, @motion.tween(search_in_ms, ease=Arrive))
}

///|
/// ⌘K laid out Small (the shell's: sfdesk's keys.mbt): the search open, its field at the top with the keys in it, what
/// can be done here (`offered`) among what it finds; `over` another page than the lists (a chat), drawn over it by the
/// shell (search_over). Open already, closed.
pub fn search_summon(c : @ui.Ctx, offered : Array[Offered], over : Bool) -> Unit {
  if search.open {
    search_close(c)
    return
  }
  finder_cleared()
  search.open = true
  search.leaving = false
  search.from = 0.0
  search.wide = 0.0
  search.focus = true
  search.summoned = true
  search.over = over
  search.offered = offered
  search_up(c).snap(1.0)
}

///|
/// 取消, back or Esc: the keyboard goes and the field goes back to the list (Search.kt close); opened by the keys, there
/// is no field in the list to go back to: gone at once, the page under it as it was.
fn search_close(c : @ui.Ctx) -> Unit {
  if !search.open || search.leaving {
    return
  }
  c.blur()
  if search.summoned {
    search_gone()
    return
  }
  search.leaving = true
  search_up(c).animate(0.0, @motion.tween(search_out_ms, ease=Standard))
}

///|
/// Closed: the field the list's again, what was found let go.
fn search_gone() -> Unit {
  search.open = false
  search.leaving = false
  search.summoned = false
  search.over = false
  search.offered = []
  finder_cleared()
}

///|
/// The search over another page than the lists (⌘K laid out Small in a chat: search_summon), in the box the shell
/// gives it over that page, `inset` from its top; nothing while there is none.
pub fn search_over(c : @ui.Ctx, src : Source, w : Workspace, inset : Double) -> Unit {
  if search.over {
    search_page(c, src, w, inset)
  }
}

///|
/// The page over Home: all of it, nothing under it touched through it.
// kept across runs: a value (no field of it changes)
let search_page_box : @ui.Style = @ui.css("w=Full h=Full")

///|
/// Over another page than the lists (search_over): on the page's ground, nothing of the page under it seen.
// kept across runs: a value (no field of it changes)
let search_over_box : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// Its bar: under the status bar 8 (the home bar's top), 16 either side, 8 under; 取消 12 after the field.
// kept across runs: a value (no field of it changes)
let search_bar_row : @ui.Style = @ui.css("row w=Full pl=S4 pr=S4 pt=S2 pb=S2 gap=S3 align=ACenter")

///|
/// Where the field rests at the top: the room 取消 leaves it.
// kept across runs: a value (no field of it changes)
let search_slot : @ui.Style = @ui.style(w=@sf.grow, h=@sf.search_field_h)

///|
/// The field (Search.kt SearchField, SearchPage's): 38 high, a capsule of the ink at 6%, 12 in, its icon 8 before
/// the words.
// kept across runs: a value (no field of it changes)
let search_field_box : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.search_field_h,
  px=S3,
  gap=S2,
  align=ACenter,
  radius=Full,
  bg=@sf.search_ground,
)

///|
/// The field at the list's top: 16 either side, 6 under it.
// kept across runs: a value (no field of it changes)
let search_field_line : @ui.Style = @ui.css("w=Full pl=S4 pr=S4 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let search_field_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let search_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let search_cancel : @ui.TextStyle = @ui.text_style(size=Xl, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let search_list_box : @ui.Style = @ui.style(w=Full, h=@sf.grow)

// ── Home's field ───────────────────────────────────────────────────────

///|
/// The search at the list's top (Search.kt SearchField): a quiet field; tapped, the search opens from it. Not seen
/// while the search's field is it (one field at a time, flying from and back to here).
fn search_field(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  let id = c.id("home-search")
  if c.clicked(id) {
    match c.rect_of(id) {
      Some((_, y, w, _)) => search_open(c, y, w)
      None => ()
    }
  }
  c.box(style=search_field_line, fn() {
    let f = c.box(style=search_field_box, id~, fn() {
      @sf.icon(c, "search", size=17.0, color=t.p.muted) |> ignore
      c.text(@sf.t("android-chat.search.field"), style=search_field_words) |> ignore
    })
    if search.open {
      c.look(f, { ..@ui.still_look, alpha: 0.0 })
    }
  })
  |> ignore
}

// ── the page ───────────────────────────────────────────────────────────

///|
/// The search over Home (Search.kt SearchPage), while it is open.
fn search_page(c : @ui.Ctx, src : Source, w : Workspace, inset : Double) -> Unit {
  if !search.open {
    return
  }
  let up = search_up(c)
  // back (and Esc): from one kind to every kind first, then the search away
  if !search.leaving && (app.nav.depth() == 1 || search.over) {
    c.take_back(fn() { if !finder_back() { search_close(c) } })
    if c.key_pressed(@ui.key_escape) || c.key_pressed(@ui.key_escape, in_field=true) {
      if !finder_back() {
        search_close(c)
      }
    }
  }
  if !search.open {
    return
  }
  let u = up.get()
  // gone back: the field is the list's again
  if search.leaving && !up.moving() {
    search_gone()
    return
  }
  // a row opened from over another page: the search goes as its page comes (as ⌘K's panel does)
  let close = fn() { if search.over { search_gone() } }
  let t = @sf.theme()
  c.layer(fn() {
    c.box(style=if search.over { search_over_box } else { search_page_box }, id=c.id("search/page"), fn() {
      // under what is over the lists' box (a phone's status bar: Search.kt windowInsetsPadding(statusBars); the
      // sidebar's top row)
      if inset > 0.0 {
        c.box(style=@ui.style(w=Full, h=Fixed(inset)), fn() {  }) |> ignore
      }
      c.box(style=search_bar_row, fn() {
        // as wide as the list's while there, narrowing to its room as it comes up (and back as it goes): 取消 comes
        // in with its right edge, not the field jumping between the two widths
        let slot = c.id("search/slot")
        let (room, rest_y) = match c.laid_rect(slot) {
          Some((_, y, rw, _)) => (rw, y)
          None => (search.wide, search.from)
        }
        c.box(style=search_slot, id=slot, fn() {
          c.layer(fn() {
            let now = dmax(if search.wide > 0.0 { search.wide + (room - search.wide) * u } else { room }, 0.0)
            let f = c.box(style=search_field_box.then(@ui.style(w=Fixed(now))), fn() {
              @sf.icon(c, "search", size=17.0, color=t.p.muted) |> ignore
              c.box(style=search_grow, fn() {
                let res = c.editor(
                  "search-field",
                  placeholder=@sf.t("android-chat.search.field"),
                  font_size=16.0,
                  max_lines=1,
                  // the keyboard's search key (Search.kt: ImeAction.Search); a keyboard's Enter opens the line chosen
                  ime_action=@hostapi.ime_action_search,
                  enter_sends=!@sf.touch_system(),
                  plain=true,
                  color=t.p.text,
                  placeholder_color=t.p.muted,
                  caret_color=t.p.accent,
                  field=finder_field(),
                )
                match res.submitted {
                  Some(typed) => {
                    finder_typed(typed)
                    finder_enter(close)
                  }
                  None => finder_typed(res.text)
                }
                if search.focus {
                  search.focus = false
                  c.focus_on(c.id("search-field"))
                }
              })
              |> ignore
            })
            c.look(f, { ..@ui.still_look, dy: (search.from - rest_y) * (1.0 - u) })
          })
          |> ignore
        })
        |> ignore
        let cancel = c.id("search/cancel")
        if c.clicked(cancel) && !search.leaving {
          search_close(c)
        }
        let cw = match c.laid_rect(cancel) {
          Some((_, _, cw, _)) => cw
          None => 0.0
        }
        let cb = c.box(id=cancel, fn() {
          c.text(@sf.t("android-chat.search.cancel"), style=search_cancel) |> ignore
        })
        c.look(cb, { ..@ui.still_look, alpha: u, dx: (cw + 12.0) * (1.0 - u) })
      })
      |> ignore
      // what the words find (sfpages' finder): a row opened, its page over this one, back to it
      let lb = c.box(style=search_list_box, fn() {
        finder_list(c, src, w, search.offered, close, idle_chats=search.summoned)
      })
      c.look(lb, { ..@ui.still_look, alpha: u })
    })
    |> ignore
  })
  |> ignore
}


///|
/// Whether the search is open over the lists (and whether it is going back to its field).
pub fn search_opened() -> Bool {
  search.open
}

///|
pub fn search_leaving() -> Bool {
  search.leaving
}
