// A chat on a device half open on its back half (a laptop's pose, Android's tabletop: @ui.system_tabletop, the hinge
// partly open and its fold across the view, as the system says them): what is read over the fold, what is touched
// under it. Its messages end over the fold (all that keeps clear of the composer keeps clear of the fold and what is
// under it: chat_foot_room); under the fold its composer, and under that the latest chats, one tap to another. The
// keyboard up, the composer rides on it, the chats under it out of the way. The page across the window whatever the size classes (laid out Small: @sf.layout); open flat, upright as
// a book, or closed, it is as on any screen.

///|
/// What a page keeps clear at its foot (over the navigation bar) on a device half open: the fold and all under it. 0
/// otherwise.
fn tabletop_clear(c : @ui.Ctx) -> Double {
  match @ui.system_tabletop() {
    Some((top, _)) => dmax(0.0, c.height - nav_foot() - top)
    None => 0.0
  }
}

///|
/// What a chat keeps clear at its page's foot (over the navigation bar) for its composer (composer_room_for), and on a
/// device half open for the fold and all under it.
fn chat_foot_room(c : @ui.Ctx, r : ChatRef, v : ChatView?) -> Double {
  ignore(v)
  // (never less than an opened composer with one line: a touch on the list lets go of the field, the composer closes
  // to its capsule, and the list's words stay where they were: the page does not jump)
  dmax(
    dmax(@sfpages.composer_open_room(c.width), @sfpages.composer_room(c, draft_key(r), settled=@sfbase.new_chat_made(c, r))),
    tabletop_clear(c),
  )
}

///|
/// A chat's page's foot, over the messages: the composer over the navigation bar; on a device half open the composer
/// at the top of the half under the fold (as far down as the keyboard, up, leaves it room) and the latest chats under
/// it.
fn chat_foot(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView?) -> Unit {
  // the composer takes its place from the foot's bottom (over the keyboard, the page's padding): the keyboard coming up
  // or going moves none of it, it goes with the foot at once (what moves in it of its own: its morph)
  let foot = c.box(style=chat_foot_whole, fn() {
    match @ui.system_tabletop() {
      Some((_, foot)) => {
        let room = @sfpages.composer_room(c, draft_key(r))
        bar_room_box(c, dmax(0.0, dmin(foot, c.height - nav_foot() - room)))
        @sfpages.chat_composer(c, src, w, r, v)
        c.box(style=tabletop_recent, fn() { recent_list(c, src, w, app.nav.top()) }) |> ignore
      }
      None => {
        c.spacer()
        @sfpages.chat_composer(c, src, w, r, v)
      }
    }
    // over the navigation bar (a layer goes on under the page's padding)
    bar_room_box(c, nav_foot())
  })
  @motion.scope(c, foot, bottom=true)
}

///|
/// A chat's foot, all of the layer it is in.
// kept across runs: a value (no field of it changes)
let chat_foot_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// Under a chat's composer on a device half open: the latest chats, as much of them as the half has room for.
// kept across runs: a value (no field of it changes)
let tabletop_recent : @ui.Style = @ui.style(w=Full, h=@sf.grow, clip=true)

///|
/// The latest chats (the list's first six, the one open marked; one picked takes the place of the page open:
/// AppState.open), or what the list says in their place: under a chat's composer on a device half open.
fn recent_list(c : @ui.Ctx, src : Source, w : Workspace, top : Page) -> Unit {
  let (view, error) = chats_of(src, w.id, "all")
  match view {
    None => recent_waiting(c, None, error)
    // no rows: what the list says in their place (the core's `note`), as Home does: its rows to come while read, or
    // what could not be; else that there are none
    Some(v) if v.days.is_empty() =>
      match v.note {
        Some(note) if note.reading || note.failing.length() > 0 => recent_waiting(c, Some(note), None)
        _ => c.text(tr("android-misc.wide.empty"), style=recent_empty) |> ignore
      }
    Some(v) => {
      let items : Array[ChatItem] = []
      for d in v.days {
        for it in d.items {
          if items.length() < recent_chats_most {
            items.push(it)
          }
        }
      }
      recent_rows_of(c, src, items, v.leading, Some(top))
    }
  }
}

///|
/// The latest chats' rows (`items`, whose pictures `lead`), the one open (`top`) marked; one picked takes the place of
/// the page open.
fn recent_rows_of(c : @ui.Ctx, src : Source, items : Array[ChatItem], lead : String, top : Page?) -> Unit {
  c.box(style=recent_rows, fn() {
    for item in items {
      let here = match top {
        Some(Chat(r)) => row_is(item, r)
        _ => false
      }
      c.box(style=if here { recent_row_here } else { recent_row }, fn() {
        @sfpages.chat_row(c, src, item, lead, found=true, opened=fn(r) {
          if !here {
            open_in_place(Chat(r))
          }
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The latest chats read the first time (the library's Waiting): their rows to come in their bones, what is wrong over
/// them in red (the bones then still); what it waits on said only to a screen reader while it reads.
fn recent_waiting(c : @ui.Ctx, note : ListNote?, error : String?) -> Unit {
  @sf.waiting(
    c,
    fn() {
      let items = Array::makei(recent_sample, @sfpages.sample_chat)
      recent_rows_of(c, @sfbase.sample_source, items, "agents", None)
    },
    text=tr("common.reading"),
    error=error.unwrap_or(""),
    note?=match note {
      Some(nt) => Some({ reading: nt.reading, text: nt.text.unwrap_or(""), failing: nt.failing })
      None => None
    },
  )
}

///|
/// How many of the list's chats it has, and how many rows are shown in their bones while they are read.
let recent_chats_most : Int = 6

///|
let recent_sample : Int = 4

///|
// kept across runs: a value (no field of it changes)
let recent_empty : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let recent_rows : @ui.Style = @ui.css("w=Full px=S1_5")

///|
/// A chat's row: concentric with what it is in where that is rounded, a row's of the ladder's where it stands alone
/// (under the fold, on the page's ground).
// kept across runs: a value (no field of it changes)
let recent_row : @ui.Style = @ui.style(w=Full, radius=InnerOr(@sf.row_radius), clip=true)

///|
// kept across runs: a value (no field of it changes)
let recent_row_here : @ui.Style = recent_row.then(@ui.css("bg=AccentBg"))

///|
/// `p` in the place of the page on top, or over Home when it is alone (AppState.open), the sheets and the menu put
/// away.
fn open_in_place(p : Page) -> Unit {
  @sfbase.history_push()
  lower_sheet()
  app.menu.set(false)
  if app.nav.depth() > 1 {
    app.nav.replace(p)
  } else {
    app.nav.push(p)
  }
}
