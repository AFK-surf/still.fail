// A film or a song played as it comes (web/ui viewer/Player.tsx, Player.css.ts): how it plays is mbui's player's
// (@kit.Media: the system's player in a native view, its bytes asked a part at a time of the file's `stream`, never
// fetched whole first). Opened where it was left on this device (viewer_file.mbt place; from its start again when it
// was left within 5 s of its end), where it is kept every 5 s while it plays and as it is left (keep_place); the
// subtitle beside it (E01.srt for E01.mp4: names.mbt side_subtitle) read and shown; the folder's others of its kind,
// in their names' order, its playlist.
//
// With a mouse it is a desktop's (`player_view`): over the window, on the page's canvas, in the theme's colours. The
// bar every file opened has (viewer_bar.mbt) along its top: back by name, the file's name, which of the folder's and
// its size, 选集 where there are others, 下载; gone with the controls as it plays on. The picture fitted in the window
// (a song: its mark and its name in the middle). The controls float over its foot (media.mbt), as wide as 1080 allows
// less 16 either side: where it is along the timeline (what has come lighter on it, the time under the pointer), then
// the one before, 15 s back, play, 15 s on, the one after, the time, the sound, the speed, the subtitle, full screen.
// They fade once the pointer rests while it plays and come back as it moves; a click on the picture plays or pauses, ←
// and → jump 15 s, Space plays or pauses. 选集 docks the folder's others at the right under the bar, 320 wide, the
// picture and the controls kept clear of it.

///|
/// `m:ss`, or `h:mm:ss` past an hour (Player.tsx clock: to the second).
pub fn clock(ms : Double) -> String {
  let total = ((if ms < 0.0 { 0.0 } else { ms }) + 500.0).to_int64() / 1000L
  let h = total / 3600L
  let m = total % 3600L / 60L
  let s = total % 60L
  if h > 0L {
    "\{h}:\{two_digits(m)}:\{two_digits(s)}"
  } else {
    "\{m}:\{two_digits(s)}"
  }
}

///|
fn two_digits(n : Int64) -> String {
  if n < 10L {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// A speed as it is shown: 1×, 1.5×, 0.75×.
pub fn speed_label(speed : Double) -> String {
  let whole = speed.floor()
  (if whole == speed { whole.to_int().to_string() } else { speed.to_string() }) +
  "×"
}

///|
/// A player for a page (`key` keeps its widgets apart from another's), its waits said once they have waited later_ms.
pub fn new_media(key : String) -> @kit.Media {
  @kit.Media::new(key~, wait_ms=later_ms)
}

///|
/// A file played, kept while its page is open: its player, whether it was opened, the subtitle asked for (its name),
/// the places kept (each next one player_keep_ms after it).
pub(all) struct Playing {
  media : @kit.Media
  /// the file as last given (where it is is kept with it)
  mut file : ViewerFile?
  mut opened : Bool
  mut subtitle_of : String
  mut keeps : Int
}

///|
/// The files played, by their key (let go of as their page goes: player_let_go).
let playings : Map[String, Playing] = Map([])

///|
/// The file played as `key` (a new player the first time).
pub fn playing_for(key : String) -> Playing {
  match playings.get(key) {
    Some(p) => p
    None => {
      let p : Playing = { media: new_media("drive-play"), file: None, opened: false, subtitle_of: "", keeps: 0 }
      playings[key] = p
      p
    }
  }
}

///|
/// How long where a file was left is waited on before it plays from the start.
pub let player_place_ms : Double = 1000.0

///|
/// How often where it is is kept while it plays.
pub let player_keep_ms : Double = 5000.0

///|
/// Left this near its end, it plays from its start again (Player.tsx resume).
let player_near_end_ms : Double = 5000.0

///|
/// A subtitle bigger than this is not read (useSubtitle).
let player_subtitle_most : Double = 8.0 * 1024.0 * 1024.0

///|
/// The file played as `key` this frame (useSource, resume, useSubtitle, keepPlace): opened once where it was left is
/// known (or waited on player_place_ms), the subtitle beside it read once the folder names one, where it is kept every
/// player_keep_ms while it plays. Its player.
pub fn player_media(c : @ui.Ctx, key : String, file : ViewerFile, siblings : Array[ViewerEntry]) -> @kit.Media {
  let pl = playing_for(key)
  pl.file = Some(file)
  // where it was left, held on this device: waited on a moment at most from when it is first drawn (`after` asks for
  // the frame it is up on)
  let waited = @kit.after(c, "play-place", !pl.opened, player_place_ms)
  if !pl.opened {
    let start = match (file.place)() {
      LeftAt(at, of) =>
        // left near its end: from the start again
        Some(if at > 0.0 && (of <= 0.0 || at < of - player_near_end_ms) { at } else { 0.0 })
      NeverLeft => Some(0.0)
      NotKnown => if waited { Some(0.0) } else { None }
    }
    match start {
      Some(start) => {
        pl.opened = true
        pl.media.open({ name: file.name, mime: file.mime, audio: file.kind == "audio", read: player_read(file) }, start~)
      }
      None => ()
    }
  }
  // the subtitle beside it, once the folder names one
  match (side_subtitle(file.name, siblings.filter(fn(e) { !e.dir }).map(fn(e) { e.name })), file.beside) {
    (Some(sub), Some(beside)) if sub != pl.subtitle_of =>
      match siblings.iter().find_first(fn(e) { e.name == sub && !e.dir }) {
        Some(side) if side.size <= player_subtitle_most => {
          // (asked once by the folder as it lists it: the same in each build of the frame)
          pl.subtitle_of = sub
          pl.media.set_subtitle(true, [])
          beside(side, fn(r) {
            match r {
              Ok(bytes) => {
                let cues = @codec.parse_subtitles(sub, bytes)
                @ui.log("player: subtitle \{sub}: \{cues.length()} lines")
                pl.media.set_subtitle(true, cues)
              }
              Err(e) => @ui.log("player: subtitle \{sub} not read: \{e}")
            }
          })
        }
        _ => ()
      }
    _ => ()
  }
  // where it is, kept every 5 s while it is open
  // (the place kept now and then: nothing shown waits for it; the next wait starts in the frame this one ends)
  if pl.media.started() && pl.media.duration() > 0.0 {
    let kept = fn() { @kit.after(c, "play-keep/" + key + "/\{pl.keeps}", true, player_keep_ms, later=true) }
    if kept() {
      // (once the frame's builds are over: a build let go of keeps nothing)
      c.after_build("play-keep", fn() {
        player_keep(pl, file)
        pl.keeps = pl.keeps + 1
        kept() |> ignore
      })
    }
  }
  pl.media
}

///|
/// How the player reads `file` a part at a time: as it streams, or from its bytes here already, or (neither) read
/// whole once and answered from that.
fn player_read(file : ViewerFile) -> (Double, Int, (Bytes, Double) -> Unit) -> Unit {
  match (file.stream, file.bytes) {
    (Some(stream), _) => stream
    (None, Some(b)) => fn(offset, length, answer) { answer(player_slice(b, offset, length), b.length().to_double()) }
    (None, None) => {
      let whole : Ref[Bytes?] = Ref(None)
      let waiting : Array[(Double, Int, (Bytes, Double) -> Unit)] = []
      let asked = Ref(false)
      fn(offset, length, answer) {
        match whole.val {
          Some(b) => answer(player_slice(b, offset, length), b.length().to_double())
          None => {
            waiting.push((offset, length, answer))
            if !asked.val {
              asked.val = true
              (file.read)(-1, fn(_) {  }, fn(r) {
                match r {
                  Ok(b) => {
                    whole.val = Some(b)
                    for w in waiting {
                      (w.2)(player_slice(b, w.0, w.1), b.length().to_double())
                    }
                  }
                  Err(_) =>
                    for w in waiting {
                      (w.2)(b"", -2.0)
                    }
                }
                waiting.clear()
              })
            }
          }
        }
      }
    }
  }
}

///|
/// `length` bytes of `b` from `offset` (none past its end).
fn player_slice(b : Bytes, offset : Double, length : Int) -> Bytes {
  let from = offset.to_int()
  let to = if from + length < b.length() { from + length } else { b.length() }
  if from >= to {
    b""
  } else {
    b[from:to].to_bytes()
  }
}

///|
/// Where it is, kept with its file (its time and its length, in ms).
fn player_keep(pl : Playing, file : ViewerFile) -> Unit {
  let pos = pl.media.position()
  let dur = pl.media.duration()
  if dur <= 0.0 {
    return
  }
  (file.keep_place)(pos.round(), dur.round())
}

///|
/// The page playing `key` gone: where it was kept, its player stopped and let go of.
pub fn player_let_go(key : String) -> Unit {
  match playings.get(key) {
    Some(pl) => {
      match pl.file {
        Some(f) if pl.media.started() => player_keep(pl, f)
        _ => ()
      }
      // (its view's 选集 stays open for the next one played in its place: the same player's key)
      pl.media.close()
    }
    None => ()
  }
  playings.remove(key)
}

///|
/// The folder's others of its kind, in their names' order: the playlist (Player.tsx list).
pub fn playlist_for(file : ViewerFile, siblings : Array[ViewerEntry]) -> Array[String] {
  playlist_of(siblings.filter(fn(e) { !e.dir && e.kind == file.kind }).map(fn(e) { e.name }), fn(_) { true })
}

///|
/// A file played on a desktop as `key` (Player with a mouse): its player made ready (player_media), drawn over the
/// window (player_view).
pub fn player(
  c : @ui.Ctx,
  key : String,
  file : ViewerFile,
  siblings : Array[ViewerEntry],
  back_label~ : String,
  on_back~ : () -> Unit,
  on_go~ : (String) -> Unit,
) -> Unit {
  let m = player_media(c, key, file, siblings)
  player_view(c, m, file, playlist_for(file, siblings), back_label~, on_back~, on_go~)
}

// ── a desktop's ─────────────────────────────────────────────────────────

///|
/// Whether 选集 is open, by the player's key (each player's own).
let desk_listing : Map[String, Bool] = Map([])

///|
/// Where the pointer was, by the player's key: its moves wake the controls.
let desk_moves : Map[String, (Double, Double)] = Map([])

///|
/// The players that made the window fill the screen, by key: back as it was when they are left.
let desk_fulled : Map[String, Bool] = Map([])

///|
/// What a player's view held of its own, by its player's key, let go (the player closed).
pub fn player_view_let_go(key : String) -> Unit {
  desk_listing.remove(key)
  desk_moves.remove(key)
  desk_fulled.remove(key)
}

///|
/// Every player let go of (the app begun again).
fn players_reset() -> Unit {
  playings.clear()
  desk_listing.clear()
  desk_moves.clear()
  desk_fulled.clear()
}

///|
/// The player `p` of `file` over the whole window, as a desktop's (see the file's head): `list` the folder's others it
/// steps through (in order, the one playing among them), `on_go` another of them opened, back to `back_label`.
pub fn player_view(
  c : @ui.Ctx,
  p : @kit.Media,
  file : ViewerFile,
  list : Array[String],
  back_label~ : String,
  on_back~ : () -> Unit,
  on_go~ : (String) -> Unit,
) -> Unit {
  let f = p.frame(c)
  let s = f.status
  let pal = theme().p
  let key = p.key()
  let name = file.name
  let index = list.search(name).unwrap_or(-1)
  let next = next_in(name, list)
  let prev = if index > 0 { list.get(index - 1) } else { None }
  let many = list.length() > 1
  let listing = many && desk_listing.get(key).unwrap_or(false)
  let panel = if listing { desk_panel_w } else { desk_none }
  // the pointer's moves wake the controls, as a mouse's do (Player.tsx onPointerMove)
  let (px, py, _) = c.pointer()
  let moved = desk_moves.get(key)
  if moved is Some((x, y)) && (x != px || y != py) {
    p.wake()
  }
  desk_moves[key] = (px, py)
  // the keys: Space plays or pauses, ← → 15 s back or on, Esc back
  if c.key_pressed(@ui.key_space) {
    p.play_pause()
    p.wake()
  }
  if c.key_pressed(@ui.key_code_left) {
    p.seek_by(-p.nudge_ms())
    p.wake()
  }
  if c.key_pressed(@ui.key_code_right) {
    p.seek_by(p.nudge_ms())
    p.wake()
  }
  if c.key_pressed(@ui.key_escape) {
    if listing {
      desk_listing[key] = false
    } else {
      desk_leave(c, key, on_back)
    }
  }
  let go = fn(other : String) {
    p.pause()
    on_go(other)
  }
  let ink = page_viewer_ink()
  c.box(style=desk_play_ground, fn() {
    // the picture, in the window less the list beside it; a click on it plays or pauses
    let stage = c.id(key + "/desk-stage")
    c.cursor(stage, Hand)
    if c.clicked(stage) {
      p.play_pause()
      p.wake()
    }
    c.box(style=desk_play_row, fn() {
      c.box(style=desk_grow_full, id=stage, fn() {
        let w = dmax(desk_none, c.width - panel)
        match p.native() {
          Some(n) if n.here() => c.native(n, content=Some(p.picture_rect(s, w, c.height))) |> ignore
          _ => ()
        }
        if f.audio {
          c.layer(fn() {
            c.box(style=desk_play_cover, fn() {
              icon(c, "file-audio", size=desk_cover_icon, color=pal.muted) |> ignore
              c.text(name, style=desk_cover_name) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        // what it waits on, why it failed
        c.layer(fn() {
          c.box(style=desk_play_middle, fn() {
            match f.phase {
              Opening | Buffering =>
                if f.waited {
                  wait_pill(c, t(if f.phase == Opening { "common.opening" } else { "web-pages.drive.player.buffering" }), key="desk-play")
                }
              Failed =>
                c.text(t("web-pages.drive.player.failed", args=[("error", "")]), style=desk_play_note) |> ignore
              _ => ()
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      c.box(style=@ui.style(w=Fixed(panel), h=Full), fn() {  }) |> ignore
    })
    |> ignore
    // a subtitle's lines over the picture's middle: above the controls while they show, lower once they fade
    if f.said != "" {
      c.layer(fn() {
        c.box(style=if f.shown > desk_half { desk_cue_up } else { desk_cue_down }, fn() {
          c.box(style=desk_cue_row, fn() {
            c.box(style=desk_grow_middle, fn() {
              c.box(style=desk_cue_box, fn() { c.text(f.said, style=desk_cue_words) |> ignore }) |> ignore
            })
            |> ignore
            c.box(style=@ui.style(w=Fixed(panel)), fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    // the bar along the top
    c.layer(fn() {
      let meta = joined([if many && index >= 0 { "\{index + 1} / \{list.length()}" } else { "" }, file_size(file.size)], " · ")
      if viewer_bar(c, key + "/bar", back_label, name, meta, !f.on && !listing, ink, fn() {
          if many && viewer_tool(c, key + "/list", "list", t("web-pages.drive.player.list"), ink, on=listing) {
            desk_listing[key] = !listing
          }
          if viewer_download(c, key + "/download", ink) {
            (file.save)()
          }
        }) {
        desk_leave(c, key, on_back)
      }
    })
    |> ignore
    // 选集, docked at the right under the bar
    if listing {
      c.layer(fn() { desk_play_list(c, p, list, index, f.phase == Playing, go) }) |> ignore
    }
    // the controls over the foot
    c.layer(fn() {
      c.box(style=desk_controls_place, fn() {
        c.box(style=desk_play_row_end, fn() {
          c.box(style=desk_grow_middle, fn() {
            let most = dmin(media_bar_most, dmax(desk_none, c.width - panel - 2.0 * media_bar_in))
            let n = c.box(style=media_bar_box.then(@ui.style(w=Fixed(most), bg=Data(media_ground()))), id=c.id(key + "/desk-controls"), fn() {
              desk_play_controls(c, p, s, f, many, prev, next, go)
            })
            c.look(n, @ui.look(alpha=f.shown))
          })
          |> ignore
          c.box(style=@ui.style(w=Fixed(panel)), fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Back from a player (`go_back`), the window as it was if the player made it fill the screen.
fn desk_leave(c : @ui.Ctx, key : String, go_back : () -> Unit) -> Unit {
  if desk_fulled.contains(key) {
    desk_fulled.remove(key)
    if @ui.full_screen() {
      c.set_full_screen(false)
    }
  }
  go_back()
}

///|
/// The controls (Player.tsx's vvBar): the timeline, then the steps and play, the time, the sound, the speed, the
/// subtitle and full screen.
fn desk_play_controls(
  c : @ui.Ctx,
  p : @kit.Media,
  s : @kit.MediaStatus,
  f : @kit.MediaFrame,
  many : Bool,
  prev : String?,
  next : String?,
  go : (String) -> Unit,
) -> Unit {
  let pal = theme().p
  let key = p.key()
  let on = f.on
  desk_play_timeline(c, p, s, on)
  c.box(style=media_row, fn() {
    c.box(style=media_group, fn() {
      if many && media_key(c, key + "/prev", "skip-back", t("web-pages.drive.player.prev"), on && prev is Some(_), small=true) {
        match prev {
          Some(other) => go(other)
          None => ()
        }
      }
      if media_key(c, key + "/back15", "back-15", t("web-pages.drive.player.back15"), on) {
        p.seek_by(-p.nudge_ms())
        p.wake()
      }
      let playing = f.phase == Playing || f.phase == Buffering
      if media_key(c, key + "/play", if playing { "pause" } else { "play" }, t(if playing { "web-main.video.pauseKey" } else { "web-main.video.playKey" }), on, bright=true) {
        p.play_pause()
        p.wake()
      }
      if media_key(c, key + "/forward15", "forward-15", t("web-pages.drive.player.forward15"), on) {
        p.seek_by(p.nudge_ms())
        p.wake()
      }
      if many && media_key(c, key + "/next", "skip-forward", t("web-pages.drive.player.next"), on && next is Some(_), small=true) {
        match next {
          Some(other) => go(other)
          None => ()
        }
      }
    })
    |> ignore
    // the time: where it is (the timeline's drag while it is dragged), of how long
    let at = p.scrubbing().unwrap_or(s.position)
    c.box(style=desk_grow_clip, fn() {
      c.rich(
        [
          @ui.span(clock(at), color=pal.text, weight=media_strong, mono=true),
          @ui.span(" / " + (if s.duration > 0.0 { clock(s.duration) } else { "--:--" }), color=pal.muted, mono=true),
        ],
        style=media_time_words,
      )
      |> ignore
    })
    |> ignore
    c.box(style=media_group, fn() {
      desk_volume(c, p, on)
      // the speed, as a figure: a click goes to the next (1×, 1.25×, 1.5×, 2×, 0.5×, 0.75×)
      if media_rate(c, key + "/speed", speed_label(p.speed()), t("web-pages.drive.player.rate"), on) {
        p.step_speed()
        p.wake()
      }
      let (subtitle, subs_on) = p.subtitle()
      if subtitle &&
        media_key(c, key + "/captions", "captions", t(if subs_on { "web-pages.drive.player.captionsOff" } else { "web-pages.drive.player.captionsOn" }), on, small=true, lit=subs_on) {
        p.toggle_subtitle()
        p.wake()
      }
      // 全屏: the window filling the screen (macOS's), back as it was (and as the player is left)
      if !f.audio && @ui.platform() == 0 {
        let full = @ui.full_screen()
        if media_key(c, key + "/full", if full { "shrink" } else { "expand" }, t(if full { "web-pages.drive.player.unfull" } else { "web-pages.drive.player.full" }), on, small=true) {
          c.set_full_screen(!full)
          if full {
            desk_fulled.remove(key)
          } else {
            desk_fulled[key] = true
          }
          p.wake()
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The sound (Player.tsx VolumeControl): a button that mutes, and beside it a line 72 wide to press or drag along (in
/// twentieths), how loud on it in the words, a 10 head.
fn desk_volume(c : @ui.Ctx, p : @kit.Media, on : Bool) -> Unit {
  let pal = theme().p
  let key = p.key()
  let (volume, muted) = p.volume()
  let silent = muted || volume == 0.0
  c.box(style=desk_volume_row, fn() {
    if media_key(c, key + "/mute", if silent { "volume-x" } else { "volume" }, t(if silent { "web-pages.drive.player.unmute" } else { "web-pages.drive.player.mute" }), on, small=true) {
      p.toggle_mute()
      p.wake()
    }
    let id = c.id(key + "/volume")
    if on {
      c.cursor(id, Hand)
    }
    // pressed along it: as loud as where (told the player once the frame's builds are over)
    match c.rect_of(id) {
      Some((x, _, w, _)) if on && c.pressed(id) => {
        let (px, _, _) = c.pointer()
        let to = (dmin(desk_whole, dmax(desk_none, (px - x) / dmax(desk_whole, w))) * desk_volume_steps).round() / desk_volume_steps
        c.after_build(key + "/volume", fn() {
          p.set_volume(to)
          p.wake()
        })
      }
      _ => ()
    }
    let shown = if muted { desk_none } else { volume }
    let b = c.box(style=desk_volume_line, id=if on { id } else { 0 }, fn() {
      c.box(style=media_track.then(@ui.style(bg=Data(alpha(pal.text, media_track_share)))), fn() {
        c.layer(fn() { media_share_bar(c, shown, pal.text) }) |> ignore
      })
      |> ignore
      c.layer(fn() { media_head(c, shown, pal.text, small=true) }) |> ignore
    })
    c.semantics(b, Slider, id~, label=t("web-pages.drive.player.volume"), range=(desk_none, desk_whole, shown))
  })
  |> ignore
}

///|
/// Where it is, to click or drag to a place (Player.tsx Timeline): the track on the words at 20%, what has come at 22%
/// over it, what has played in the words, the head; the player sent there once let go (@kit.Media); with the pointer
/// over it (or dragging), the time where it points over it.
fn desk_play_timeline(c : @ui.Ctx, p : @kit.Media, s : @kit.MediaStatus, on : Bool) -> Unit {
  let pal = theme().p
  let id = c.id(p.key() + "/desk-timeline")
  p.timeline(c, id, on)
  let dur = s.duration
  let part = fn(ms : Double) { if dur <= 0.0 { desk_none } else { dmin(desk_whole, dmax(desk_none, ms / dur)) } }
  let shown = part(p.scrubbing().unwrap_or(s.position))
  let came = part(s.buffered)
  if on {
    c.cursor(id, Hand)
  }
  c.box(style=media_timeline_box, id=if on { id } else { 0 }, fn() {
    c.box(style=media_track.then(@ui.style(bg=Data(alpha(pal.text, media_track_share)))), fn() {
      c.layer(fn() { media_share_bar(c, came, alpha(pal.text, media_came_share)) }) |> ignore
      c.layer(fn() { media_share_bar(c, shown, pal.text) }) |> ignore
    })
    |> ignore
    // the head where it is
    c.layer(fn() { media_head(c, shown, pal.text) }) |> ignore
    // with a mouse over it (or dragging), the time where it points, over it (Player.tsx Timeline `pointed`)
    match c.rect_of(id) {
      Some((x, _, w, _)) if on && dur > 0.0 && (c.hovered(id) || c.pressed(id)) => {
        let (px, _, _) = c.pointer()
        let at = dmin(desk_whole, dmax(desk_none, (px - x) / dmax(desk_whole, w)))
        c.layer(fn() {
          c.box(style=desk_pointed, tx=px - x - desk_pointed_w / 2.0, ty=-desk_pointed_up, fn() {
            c.rich([@ui.span(clock(at * dur), mono=true)], style=desk_pointed_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      _ => ()
    }
  })
  |> ignore
}

///|
/// 选集 (Player.tsx list): the folder's others docked at the right under the bar, on the canvas with a line before them:
/// 选集 and which of how many, its close; each numbered, the one playing on the page's chosen ground with ▶ (✓ paused).
fn desk_play_list(c : @ui.Ctx, p : @kit.Media, list : Array[String], index : Int, playing : Bool, go : (String) -> Unit) -> Unit {
  let pal = theme().p
  let key = p.key()
  c.box(style=desk_panel_place, fn() {
    c.box(style=desk_panel_top, fn() {  }) |> ignore
    c.box(style=desk_panel_row, fn() {
      c.box(style=desk_panel_room, fn() {  }) |> ignore
      c.box(style=desk_panel_rule.then(@ui.style(bg=Data(pal.line))), fn() {  }) |> ignore
      c.box(style=desk_panel_box.then(@ui.style(bg=Data(pal.canvas))), id=c.id(key + "/list-panel"), fn() {
        c.box(style=desk_list_head, fn() {
          c.text(t("web-pages.drive.player.list"), style=desk_panel_title) |> ignore
          c.box(style=desk_grow, fn() {
            c.text("\{index + 1} / \{list.length()}", style=desk_panel_note.then(@ui.text_style(color=Muted))) |> ignore
          })
          |> ignore
          if viewer_tool(c, key + "/list-close", "close", t("common.close"), page_viewer_ink()) {
            desk_listing[key] = false
          }
        })
        |> ignore
        c.box(style=desk_panel_list, fn() {
          c.list(key + "/list", list.length(), desk_row_h, fn(i) {
            let id = c.id(key + "/list/\{i}")
            let now = i == index
            c.cursor(id, Hand)
            if c.clicked(id) && !now {
              go(list[i])
            }
            c.box(style=desk_list_row, selected=now, id~, fn() {
              c.box(style=desk_chapter_number, fn() {
                c.text("\{i + 1}", style=desk_chapter_n_words.then(@ui.text_style(color=Muted))) |> ignore
              })
              |> ignore
              c.box(style=desk_grow_clip, fn() {
                c.text(list[i], style=if now { desk_list_now } else { desk_list_words }) |> ignore
              })
              |> ignore
              if now {
                icon(c, if playing { "play" } else { "check" }, size=desk_check_icon, color=pal.text) |> ignore
              }
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A song's mark (72) in the middle; the cue's words (16 on 1.6) on black at 60%; above the controls while they show
/// (112 off the foot), else 28.
let desk_cover_icon : Double = 72.0

///|
let desk_half : Double = 0.5

///|
/// The time where the pointer is (Player.css.ts pointed): over the timeline, 4 above it, on black at 75%, 11 in white.
let desk_pointed_w : Double = 56.0

///|
let desk_pointed_up : Double = 24.0

///|
// kept across runs: a value (no field of it changes)
let desk_pointed : @ui.Style = @ui.style(w=Fixed(desk_pointed_w), h=S5, radius=Md, bg=VeilDeep, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let desk_pointed_words : @ui.TextStyle = @ui.text_style(size=Xs2, color=OnVeil, wrap=false)

///|
/// The sound's line: in twentieths, 72 wide.
let desk_volume_steps : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let desk_volume_row : @ui.Style = @ui.style(row=true, pr=S1_5, gap=S0_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_volume_line : @ui.Style = @ui.style(w=Fixed(desk_volume_w), h=Fixed(media_timeline_h), justify=JCenter)

///|
let desk_volume_w : Double = 72.0

///|
// kept across runs: a value (no field of it changes)
let desk_play_ground : @ui.Style = @ui.style(w=Full, h=Full, bg=Bg)

///|
// kept across runs: a value (no field of it changes)
let desk_play_row : @ui.Style = @ui.style(row=true, w=Full, h=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_grow_full : @ui.Style = @ui.style(w=grow, h=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_play_cover : @ui.Style = @ui.style(w=Full, h=Full, px=S8, gap=S4, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let desk_cover_name : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let desk_play_middle : @ui.Style = @ui.style(w=Full, h=Full, align=ACenter, justify=JCenter)

///|
/// Why it failed (Player.css.ts note): 12 and quiet, in the middle.
// kept across runs: a value (no field of it changes)
let desk_play_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, center=true)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_up : @ui.Style = @ui.style(w=Full, h=Full, pb=S28, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_down : @ui.Style = @ui.style(w=Full, h=Full, pb=S7, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_row : @ui.Style = @ui.style(row=true, w=Full, px=S4)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_box : @ui.Style = @ui.style(px=S2, py=S0_5, radius=Md, bg=Veil)

///|
// kept across runs: a value (no field of it changes)
let desk_cue_words : @ui.TextStyle = @ui.text_style(size=Xl, color=OnVeil, center=true, leading=L7)

///|
/// The controls: 16 off the window's foot, in the middle of what the list leaves.
// kept across runs: a value (no field of it changes)
let desk_controls_place : @ui.Style = @ui.style(w=Full, h=Full, pb=S4, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let desk_play_row_end : @ui.Style = @ui.style(row=true, w=Full)

///|
/// 选集's head (listHead: 12 over, 10 right, 6 under, 18 at its start) and rows (listRow: 40 at least, 8 and 10 in, the
/// page's corner; the one playing on the chosen ground, in 500).
// kept across runs: a value (no field of it changes)
let desk_list_head : @ui.Style = @ui.style(row=true, w=Full, pl=S4_5, pr=S2_5, pt=S3, pb=S1_5, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_list_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=S10,
  px=S2_5,
  py=S2,
  gap=S1,
  align=ACenter,
  radius=Xl,
  hovered=@ui.patch(bg=Hover),
  selected=@ui.patch(bg=Selected),
)

///|
// kept across runs: a value (no field of it changes)
let desk_list_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_list_now : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)
