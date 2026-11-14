// What a file's card holds (peeks.mbt's file_card) as nodes of the window's tree, made once: what is over it, opened
// and shut as the pointer rests on the chip that names the file, is the hover card's (sf's), not this; this is what is
// in it, as the core reads the file (`filePeek`, read by whoever holds the card) and as that changes: its head, a few of
// its lines, its picture or its first entries, its foot with its path to copy; in its bones while it is read and its
// picture comes, said why not where it is not read.

///|
/// What a file's card shows (file_card's): its bones while it is read (and the picture it names comes); why not, read
/// and refused; the file as the core read it.
#derive(Eq)
priv enum FileShows {
  Bones
  Refused
  Shown
}

///|
/// What a file's card holds (file_card's) in `parent`: the file `path` (at `line`) that session `session` of station
/// `station` names, as `read` reads it (`filePeek`, held by whoever holds the card): in its bones while it is read and
/// the picture it names comes (@sfbase.file_peek_picture_told: told as it comes, asked as the file is read, never as a
/// binding runs), why not where it is refused, else as it is read.
// a hover card as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn file_card_node(
  parent : @view.View,
  src : Source,
  station : String,
  session : String,
  path : String,
  line : Int?,
  read : @signals.Computed[@sfbase.TopicState],
) -> Unit {
  let value = fn() -> Json? {
    match read.get().value {
      Some(Object(_)) as v => v
      _ => None
    }
  }
  // (the picture it names asked as it is read, as that changes; told to what reads it as it comes)
  parent.reacts(value, fn(v) {
    if v is Some(_) {
      @sfbase.file_peek_picture_ask(src, station, session, path, line, v)
    }
  })
  // (its picture's key: "" while it comes, "!" none)
  let picture_key = fn() {
    match value() {
      Some(_) as v => @sfbase.file_peek_picture_told(src, station, session, path, line, v)
      None => ""
    }
  }
  let shows = fn() {
    if value() is Some(_) && picture_key() != "" {
      Shown
    } else if read.get().error is Some(_) {
      Refused
    } else {
      Bones
    }
  }
  parent.pick(shows, fn(b, s) {
    @sf.style_node(b, fn() { peek_card_part })
    match s {
      Shown => file_shown_node(b, fn() { @sfbase.picture_drawn(picture_key()) }, value)
      // (while it is read: a made-up file's, in its bones)
      Bones => @sf.waiting_node(b, fn(bones) { file_shown_node(bones, fn() { "" }, fn() { file_sample(path) }) })
      Refused =>
        b.box(fn(rich) {
          @sf.style_node(rich, fn() { peek_rich })
          file_head_node(rich, fn() { base_of(path) }, fn() { path.has_suffix("/") }, fn() { path }, fn() { "" })
          @sf.words_node(rich, fn() { text(read.get().error, "message") }, fn() { peek_note }) |> ignore
          file_foot_node(rich, fn() { path }, fn() { "" })
        })
        |> ignore
    }
  })
}

///|
/// The made-up file a file's card's bones are made of while it is read (file_card's): named as `path`, five lines.
fn file_sample(path : String) -> Json? {
  Some({
    "kind": "text",
    "name": Json::string(base_of(path)),
    "path": Json::string(path),
    "size": 1,
    "lines": { "start": 1, "text": Json::array([24, 32, 18, 28, 12].map(fn(n) { Json::string(@sf.sample_words(n)) })) },
  })
}

///|
/// A file as the core read it (`v`, file_shown's) in `parent`: its head; a text's lines, an image's picture (`picture`:
/// its image's key, "" none) or a directory's first entries; its foot.
fn file_shown_node(parent : @view.View, picture : () -> String, v : () -> Json?) -> Unit {
  let kind = fn() { text(v(), "kind") }
  let dir = fn() { kind() == "dir" }
  let lines = fn() { field(v(), "lines") }
  let at = fn() {
    match field(lines(), "at") {
      Some(Number(n, ..)) => Some(n.to_int())
      _ => None
    }
  }
  parent.box(fn(rich) {
    @sf.style_node(rich, fn() { peek_rich })
    file_head_node(
      rich,
      fn() {
        text(v(), "name") +
        (match at() {
          Some(n) => ":" + n.to_string()
          None => ""
        })
      },
      dir,
      fn() { text(v(), "path") },
      fn() { text(field(field(v(), "time"), "mtime"), "ago") },
    )
    // (what it shows of itself: a text's lines, an image's picture, a directory's entries, or none)
    let body = fn() {
      match kind() {
        "text" if items(lines(), "text").length() > 0 => 1
        "image" if picture() != "" => 2
        "dir" if items(v(), "entries").length() > 0 => 3
        _ => 0
      }
    }
    // (none: nothing in its place, not even the room between)
    rich.show(fn() { body() != 0 }, fn(s) {
      s.pick(body, fn(b, k) {
        match k {
          1 => file_lines_node(b, lines, at, fn() { text(v(), "name") })
          // (its picture all in its box, fading in once it is decoded for the room it is given, the hover's ground under
          // it till then: an old view's picture's bg)
          2 =>
            b.by_room(fn(g, room) {
              g
              .height(Is(Some(peek_file_image_h)))
              .radius(Is(peek_file_image_r))
              .ground(By(fn() {
                let w = room.width()
                let side = if w > peek_file_image_h { w } else { peek_file_image_h }
                // (its decode asked as the card is made, a pointer resting on a link opening it: there by the frame
                // after, as drawn; View::image_ask)
                g.image_ask(picture(), side * g.pixel_scale())
                if g.image_ready(picture(), side * g.pixel_scale()) {
                  0L
                } else {
                  @sf.theme().p.hover
                }
              }))
              .image(By(fn() { Some((picture(), "", peek_image_most)) }))
              .image_contains(Is(true))
              .image_fades(Is(true))
              |> ignore
            })
            |> ignore
          3 => file_entries_node(b, fn() { items(v(), "entries") })
          _ => ()
        }
      })
    })
    let what = fn() {
      if dir() {
        @sf.t("web-main.preview.items", args=[("count", count(v(), "count").to_string())])
      } else {
        let size = @sf.file_size(
          match field(v(), "size") {
            Some(Number(n, ..)) => n
            _ => 0.0
          },
        )
        if kind() == "binary" {
          size + " · " + @sf.t("web-main.preview.binary")
        } else {
          size
        }
      }
    }
    file_foot_node(rich, fn() { text(v(), "path") }, what)
  })
  |> ignore
}

///|
/// Its head (file_head's) in `parent`: its mark (14, muted; a folder's where `dir`) 6 from its name (one line, 500; a
/// directory's ending in `/`) and when it was written (muted, at the end, where it says); its whole path under them in
/// the code face, a home directory as `~` (shown_path).
fn file_head_node(
  parent : @view.View,
  name : () -> String,
  dir : () -> Bool,
  path : () -> String,
  ago : () -> String,
) -> Unit {
  parent.box(fn(h) {
    @sf.style_node(h, fn() { peek_file_head })
    h.box(fn(t) {
      @sf.style_node(t, fn() { peek_chat_title })
      @sf.icon_node(t, "file", peek_file_icon, By(fn() { @sf.theme().p.muted }), name_now=fn() {
        if dir() {
          "folder"
        } else {
          "file"
        }
      })
      |> ignore
      t.box(fn(r) {
        @sf.style_node(r, fn() { peek_ref }, in_row=true)
        r.lines_up(Is(Some(@view.Along::Start))) |> ignore
        @sf.words_node(r, fn() { if dir() { name() + "/" } else { name() } }, fn() { peek_title }) |> ignore
      })
      |> ignore
      t.show(fn() { ago() != "" }, fn(a) { @sf.words_node(a, ago, fn() { peek_meta_words }) |> ignore })
    })
    |> ignore
    peek_mono_node(h, fn() { [@ui.span(shown_path(path()), mono=true)] }, peek_file_path)
  })
  |> ignore
}

///|
/// Its lines (file_lines's) in `parent`: each numbered from `lines`' start (34 wide, muted, 8 before the line), the one
/// at `at` on the accent's pale ground, each one line, cut; in the code face at the caption's size, in the colours the
/// core says of the language `name`'s (code.ink, as a preview colours it: code_ink_node), plain till it has.
fn file_lines_node(parent : @view.View, lines : () -> Json?, at : () -> Int?, name : () -> String) -> Unit {
  @sf.style_node(parent, fn() { peek_file_lines })
  let words = fn() {
    items(lines(), "text").map(fn(l) {
      match l {
        String(t) => t
        _ => ""
      }
    })
  }
  let lang = fn() {
    let (_, _, lang) = @sfbase.preview_kind(name())
    lang
  }
  // (coloured as a whole, then cut at its lines; a file of no language as it is, nothing asked)
  let all = fn() { words().join("\n") }
  let colored = if @signals.untracked(lang) == "" {
    fn() { [] }
  } else {
    let ink = @sf.code_ink_node(parent, all, lang)
    fn() {
      match ink() {
        Some(Some(i)) => @sfbase.runs_by_line(@sf.ink_runs(all(), i, @sf.theme().dark))
        _ => []
      }
    }
  }
  parent.each(fn() { Array::makei(words().length(), fn(k) { k }) }, fn(k) { k }, fn(row, k) {
    let n = fn() { count(lines(), "start") + k.get() }
    @sf.style_node(row, fn() { if at() == Some(n()) { peek_file_line_at } else { peek_file_line } })
    row.box(fn(no) {
      @sf.style_node(no, fn() { peek_file_line_no }, in_row=true)
      peek_mono_node(no, fn() { [@ui.span(n().to_string(), mono=true)] }, peek_file_no)
    })
    |> ignore
    row.box(fn(r) {
      @sf.style_node(r, fn() { peek_ref }, in_row=true)
      peek_mono_node(
        r,
        fn() {
          match colored().get(k.get()) {
            Some(runs) if runs.length() > 0 => runs
            _ => {
              let t = words().get(k.get()).unwrap_or("")
              [@ui.span(if t != "" { t } else { " " }, mono=true)]
            }
          }
        },
        peek_file_code,
      )
    })
    |> ignore
  })
}

///|
/// A directory's first entries (file_entries's) in `parent`, two to a row, each its mark (12, muted; a folder's for a
/// name ending in `/`) and its name in the code face (without its `/`), cut.
fn file_entries_node(parent : @view.View, entries : () -> Array[Json]) -> Unit {
  @sf.style_node(parent, fn() { peek_file_entries })
  let name = fn(k : Int) {
    match entries().get(k) {
      Some(String(t)) => t
      _ => ""
    }
  }
  parent.each(fn() { Array::makei((entries().length() + 1) / 2, fn(r) { r }) }, fn(r) { r }, fn(row, r) {
    @sf.style_node(row, fn() { peek_file_entry_row })
    row.each(
      fn() {
        let r = r.get()
        Array::makei(if 2 * r + 2 <= entries().length() { 2 } else { entries().length() - 2 * r }, fn(i) { 2 * r + i })
      },
      fn(k) { k },
      fn(e, k) {
        let dir = fn() { name(k.get()).has_suffix("/") }
        @sf.style_node(e, fn() { peek_file_entry }, in_row=true)
        @sf.icon_node(e, "file", peek_file_entry_icon, By(fn() { @sf.theme().p.muted }), name_now=fn() {
          if dir() {
            "folder"
          } else {
            "file"
          }
        })
        |> ignore
        e.box(fn(b) {
          @sf.style_node(b, fn() { peek_ref }, in_row=true)
          peek_mono_node(
            b,
            fn() {
              let n = name(k.get())
              [@ui.span(if dir() { n.exact_view(end=n.length() - 1).to_owned() } else { n }, mono=true)]
            },
            peek_file_code,
          )
        })
        |> ignore
      },
    )
  })
}

///|
/// Its foot (file_foot's) in `parent`: what it is in words (`what`, muted), and its path to copy (复制路径, saying 已复制
/// copied_ms from the moment it was pressed) in the card's bottom end corner, concentric with it.
fn file_foot_node(parent : @view.View, path : () -> String, what : () -> String) -> Unit {
  parent.box(fn(f) {
    @sf.style_node(f, fn() { peek_file_foot })
    f.box(fn(r) {
      @sf.style_node(r, fn() { peek_ref }, in_row=true)
      r.lines_up(Is(Some(@view.Along::Start))) |> ignore
      @sf.words_node(r, what, fn() { peek_meta_words }) |> ignore
    })
    |> ignore
    path_copy_node(f, path)
  })
  |> ignore
}

///|
/// A file's path to copy, on its card (file_foot's) in `parent`: 复制路径 to press, 已复制 for copied_ms once copied
/// (from the moment it was pressed: pressed again while it says so, from then). By the path, as file_foot's mark is: a
/// card of it made again while that lasts says 已复制 till its end.
fn path_copy_node(parent : @view.View, path : () -> String) -> Unit {
  let copied = @signals.signal(false, same=fn(a, b) { a == b })
  let off : Ref[() -> Unit] = Ref(fn() {  })
  // (said so from `at`, the moment it was copied, till copied_ms on; off as of then)
  let said_from = fn(at : Double) {
    (off.val)()
    if parent.cause_at() < at + @sf.copied_ms {
      copied.set(true)
      off.val = parent.at_moment(at + @sf.copied_ms, fn() { copied.set(false) })
    } else {
      copied.set(false)
    }
  }
  // (made while it says so from the last copy of the path, on another card of it: till that one's end)
  parent.reacts(fn() { () }, fn(_) {
    match path_copied_at.get(@signals.untracked(path)) {
      Some(at) => said_from(at)
      None => ()
    }
  })
  @sf.panel_button_node(
    parent,
    fn() { @sf.t(if copied.get() { "common.copied" } else { "web-main.preview.copyPath" }) },
    fn() {
      let p = @signals.untracked(path)
      @ui.clipboard_set(p)
      let at = parent.cause_at()
      path_copied_at[p] = at
      said_from(at)
    },
    tone=Quiet,
  )
  |> ignore
  parent.owns(fn() { (off.val)() }) |> ignore
}

///|
/// When each file's path was last copied from its card (path_copy_node's), by the path: what a card of it made again
/// says, as file_foot's mark by the path is kept.
// kept across runs: let go as the app begins anew (its init)
let path_copied_at : Map[String, Double] = Map([])

///|
fn init {
  @ui.on_reset(fn() { path_copied_at.clear() })
}

///|
/// Words in the code face (mono's) in `parent`: `runs`, as `style` says them otherwise (its size, ink, one line and cut
/// where it says so).
fn peek_mono_node(parent : @view.View, runs : () -> Array[@ui.Run], style : @ui.TextStyle) -> Unit {
  // (cut where its line has not the room, else as wide as it is, as an old view's words in a column are: not stretched
  // across it)
  if @ui.style_cut(style) {
    parent.lines_up(Is(Some(@view.Along::Start))) |> ignore
  }
  parent.box(fn(w) {
    w
    .words_runs(By(runs))
    .words_look(Is(@ui.style_words(style)))
    .ink(By(fn() { @ui.style_ink(style) }))
    |> ignore
    if @ui.style_cut(style) {
      w.cuts(Is(true)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
    } else if @ui.style_fills(style) && !@ui.style_words(style).wrap {
      w.allow_ellipsis(Is(true)) |> ignore
    }
  })
  |> ignore
}
