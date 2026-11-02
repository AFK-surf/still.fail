// A chat shared as a picture (2026-10-26 用户：「静态分享功能改成分享图片吧，把内容直接渲染成一张长图」; ember
// web/src/Publish.tsx PublishDialog, PublishPicture, FileToggle; Publish.css.ts, FilePreview.css.ts fp; the phone's
// PublishSheet in mobile/Chat.tsx, the same), one on every screen: from its info's 分享图片, over the whole window as a
// file is previewed, the picture as it would be (`chat.publishPreview`, asked as it opens: what the chat holds now,
// what looks like a secret in it hidden): the chat's name, its messages as the chat's list draws them (the preview's
// `list`, drawn by its rows), each attachment where its message has it, pressed anywhere to tick it or not (all at
// first: FileToggle's label), and still.fail's mark at its foot. What it is for is the library's viewer_frame_act (2026-10-26 用户, of a button filled
// in a pill of its own over it: 「太不对劲了」「应该放下面，俩按钮，一个取消一个保存到相册，pc 的话直接跟附件预览一样，有顶栏」「pc
// 也用文字按钮，不要用图标」): on a wide screen the bar a file opened has across the top (back to the chat by its name, 分享图片
// and how much was hidden), the button 复制图片 at its end; on a small screen 取消 and 保存到相册 side by side at the foot
// (picture_out). Pressed, the picture is drawn whole off the screen as one long picture (Ctx::shot), the attachments
// left out not in it, nor the ticks and the notes of what was hidden that are for the one sharing it, its times as
// dates; then handed out. A page of HTML an agent's words place is drawn live on the page, as the chat draws it, and in
// the picture as it looks then (2026-11-02 用户：「分享会话内容时，好像不会把inline html也渲染进去」): a page is the system's
// view, which no shot holds, so before the picture is taken each is brought into sight and grabbed (publish_walk), its
// grab drawn in its place; one that cannot be (a browser's frame grabs nothing, a page that did not draw) is its card, as
// are those left out on the page. Which files an agent's words place, and those words as Markdown, are the core's (the
// list's `placed`, `md`). The frames draw it over their pages (publish_layer). (A link once made of a chat,
// docs/public-share.md, is made no more; those made still open, and its info lists them.)

///|
/// The sharing as it stands: the chat it is of and its thread (None: closed), the preview as read (0 being read, 1
/// read, 2 not: `error` says why), the attachments left out (by their `k`), its picture being taken, how many times it
/// was copied (its button 已复制 a moment after).
priv struct Publishing {
  of : @signals.Signal[(ChatRef, Double)?]
  read : @signals.Signal[Int]
  preview : @signals.Signal[Json?]
  error : @signals.Signal[String]
  off : @sf.LiveMap[String, Bool]
  busy : @signals.Signal[Bool]
  copied : @signals.Signal[Int]
  /// the chat's thread its page is drawn for: the one open, and once closed while it goes (publish_layer)
  mut drawn : (ChatRef, Double)?
  /// the pages of HTML drawn live on the page, by their `k`: the box each is drawn in and its place (viz_frame's)
  viz_boxes : Map[String, (Int, String)]
  /// those of them whose file could not be read: their cards
  viz_failed : Map[String, Bool]
  /// what each was grabbed as for the picture, by its `k`: its image and how tall it is drawn
  stills : Map[String, (String, Double)]
  /// the going through them as its picture is asked for, and how many times it was asked
  mut walk : PublishWalk?
  mut walks : Int
}

///|
/// The pages of HTML being grabbed for the picture (publish_walk): their `k`s, which it is at and how far with it (0 to
/// bring it into sight, 1 waiting till it has drawn itself, 2 waiting for its grab), how far the page was scrolled
/// (negative: not read yet).
priv struct PublishWalk {
  todo : Array[String]
  mut at : Int
  mut step : Int
  mut back : Double
}

///|
let publishing : Publishing = {
  of: @signals.signal(None),
  read: @signals.signal(0, same=fn(a, b) { a == b }),
  preview: @signals.signal(None),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  off: @sf.LiveMap::new(),
  busy: @signals.signal(false, same=fn(a, b) { a == b }),
  copied: @signals.signal(0, same=fn(a, b) { a == b }),
  drawn: None,
  viz_boxes: {},
  viz_failed: {},
  stills: {},
  walk: None,
  walks: 0,
}

///|
pub fn publish_reset() -> Unit {
  publishing.drawn = None
  publishing.of.set(None)
  publishing.read.set(0)
  publishing.preview.set(None)
  publishing.error.set("")
  publishing.off.clear()
  publishing.busy.set(false)
  publishing.copied.set(0)
  publishing.viz_boxes.clear()
  publishing.viz_failed.clear()
  publishing.stills.clear()
  publishing.walk = None
}

///|
/// Opened for chat `r`'s `thread`: what the picture would hold asked now (usePublishPreview); with `turn` (a
/// message's seq), the turn of that message alone (a message's menu's 分享这一轮).
pub fn open_publish(src : Source, r : ChatRef, thread : Double, turn? : Double? = None) -> Unit {
  publish_reset()
  publishing.of.set(Some((r, thread)))
  let asked : Map[String, Json] = { "station": Json::string(r.station), "thread": Json::number(thread) }
  match turn {
    Some(n) => asked["turn"] = Json::number(n)
    None => ()
  }
  (src.call)("chat.publishPreview", Json::object(asked), fn(res) {
    match publishing.of.get() {
      Some((o, th)) if o.station == r.station && th == thread =>
        match res {
          Ok(v) => {
            publishing.preview.set(Some(v))
            publishing.read.set(1)
          }
          Err(e) => {
            publishing.error.set(error_words(e))
            publishing.read.set(2)
          }
        }
      _ => ()
    }
  })
}

///|
/// Its page closed: it goes (publish_layer), what it showed kept till it has gone, the rest put back as the next opens.
pub fn publish_close() -> Unit {
  publishing.of.set(None)
  publishing.busy.set(false)
  publishing.walk = None
}

///|
/// Whether its page is open (not closed, whether or not it has gone yet).
pub fn publish_open() -> Bool {
  @signals.untracked(fn() { publishing.of.get() }) is Some(_)
}

///|
/// Chat `r`'s `thread` being shared, `preview` read (a screen's fixture).
pub fn publish_set(r : ChatRef, thread : Double, preview : Json) -> Unit {
  publish_reset()
  publishing.of.set(Some((r, thread)))
  publishing.preview.set(Some(preview))
  publishing.read.set(1)
}

///|
/// Whether page of HTML `k` was grabbed for the picture (tests).
pub fn publish_has_still(k : String) -> Bool {
  publishing.stills.contains(k)
}

///|
/// Whether attachment `k` is left out of the picture (tests).
pub fn publish_left_out(k : String) -> Bool {
  publishing.off.contains(k)
}

///|
/// What leaves message `seq` out of the picture in `off` (its attachments are there by their `k`).
fn message_k(seq : Double) -> String {
  "m:" + seq_s(seq)
}

///|
/// Whether message `seq` is left out of the picture (tests).
pub fn publish_message_left_out(seq : Double) -> Bool {
  publishing.off.contains(message_k(seq))
}

///|
/// How many of the preview's messages go in the picture (none ticked: nothing to take).
fn publish_kept(p : Json?) -> Int {
  items(p, "list").filter(fn(j) { !publishing.off.contains(message_k(number(Some(j), "seq"))) }).length()
}

///|
/// The picture's shot (Ctx::shot).
let publish_shot : String = "publish/picture"

///|
/// Its picture asked for: the pages of HTML in it grabbed first (publish_walk), then taken.
fn publish_go(c : @ui.Ctx) -> Unit {
  publishing.busy.set(true)
  publishing.stills.clear()
  let todo = publish_viz_todo()
  if todo.is_empty() {
    publish_take(c)
  } else {
    publishing.walks = publishing.walks + 1
    publishing.walk = Some({ todo, at: 0, step: 0, back: -1.0 })
  }
}

///|
/// The `k`s of the pages of HTML the picture holds, drawn live on the page, in the order they come in it.
fn publish_viz_todo() -> Array[String] {
  let todo = []
  for j in items(publishing.preview.get(), "list") {
    let m = picture_message(@sfbase.message_of(j), true)
    if publishing.off.contains(message_k(m.seq)) {
      continue
    }
    for a in m.attachments {
      let k = file_k(m.seq, a)
      if publishing.viz_boxes.contains(k) && m.placed.contains(a.name) && is_viz(a.name) {
        todo.push(k)
      }
    }
  }
  todo
}

///|
/// How long a page of HTML that has drawn itself is left before it is grabbed (what it draws on coming in: a chart's
/// first animation), and how long it is waited for at most at each step: one not there by then is its card.
pub let publish_viz_settle_ms : Double = 600.0

///|
let publish_viz_wait_ms : Double = 8000.0

///|
/// The tallest page of HTML grabbed: a picture of one taller (a catalogue of twenty screens) is past what a host holds
/// at once. Its card.
let publish_viz_most_h : Double = 8000.0

///|
/// Each frame while its picture is asked for: the next of the pages of HTML in it brought into sight on the page (`list`
/// the page's list by its key, `node`: a host places and draws only what is in sight), left till it has drawn itself,
/// grabbed, and that kept for the picture; after the last the page scrolled back and the picture taken.
fn publish_walk(c : @ui.Ctx, list : String, node : Int) -> Unit {
  guard publishing.walk is Some(w) else { return }
  if w.back < 0.0 && node >= 0 {
    w.back = c.list_scrolled(node)
  }
  if w.at >= w.todo.length() {
    publishing.walk = None
    if node >= 0 {
      c.list_scroll_by(list, w.back - c.list_scrolled(node))
    }
    publish_take(c)
    return
  }
  let k = w.todo[w.at]
  let next = fn() {
    w.at = w.at + 1
    w.step = 0
    c.request_frame()
  }
  let timer = "publish/walk/\{publishing.walks}/\{k}"
  let (box, place) = match publishing.viz_boxes.get(k) {
    Some(b) if !publishing.viz_failed.contains(k) => b
    _ => return next()
  }
  let frame = @sfbase.viz_frames.get(place)
  // (read each frame: a box read in no frame is not kept)
  let laid = c.laid_rect(box)
  if @kit.after(c, timer + "/out/" + w.step.to_string(), true, publish_viz_wait_ms) {
    return next()
  }
  match w.step {
    0 =>
      match laid {
        Some((_, y, _, h)) => {
          if h > publish_viz_most_h {
            return next()
          }
          // (under what is over the page at the top, over what is at its foot)
          let top = @sf.viewer_act_head(c)
          if y < top || y + h > c.height - @sf.viewer_act_foot(c) {
            c.list_scroll_by(list, y - top)
          }
          w.step = 1
        }
        None => ()
      }
    1 =>
      match frame {
        Some(f) => {
          let ready = f.shown && f.view.host_done()
          if @kit.after(c, timer + "/settled", ready, publish_viz_settle_ms) && !f.view.grabbing() {
            f.view.grab_frame(0.0)
            w.step = 2
          }
        }
        None => ()
      }
    _ =>
      match frame.map(fn(f) { f.view.grabbed() }) {
        Some(Some(png)) => {
          match (publish_viz_grab_size(png), laid) {
            // (a grab of all of it: one of a part of it is not stretched to all of it)
            (Some((pw, ph)), Some((_, _, bw, bh))) if ((ph * bw / pw - bh).abs() <= 2.0) => {
              let src = "mem:publish/\{publishing.walks}/\{k}"
              @ui.add_image(src, png)
              publishing.stills[k] = (src, bh)
            }
            _ => ()
          }
          next()
        }
        Some(None) => ()
        None => next()
      }
  }
}

///|
/// How many pixels across and down a page's grab `png` is; None when it is empty or not a PNG.
fn publish_viz_grab_size(png : Bytes) -> (Double, Double)? {
  match @sfbase.png_size(png) {
    Some((w, h)) if w > 0 && h > 0 => Some((w.to_double(), h.to_double()))
    _ => None
  }
}

///|
/// The picture taken (the attachments ticked in it, nothing else of the page's), then handed out as its button says:
/// copied, its button 已复制 a moment, else what came of it said.
fn publish_take(c : @ui.Ctx) -> Unit {
  c.take_shot(publish_shot, fn(png) {
    publishing.busy.set(false)
    let (_, icon) = @sf.picture_out_way()
    if picture_out(c, png, copy_said=icon == "copy") && icon == "copy" {
      publishing.copied.set(publishing.copied.get() + 1)
    }
  })
}

///|
/// The page that shares it, while it is open, over the frame's pages (under the presenters and the toasts).
/// It comes in faded in as a file opened over the window does, and goes as a dialog does (@sf.window_page_in,
/// @kit.pop_out), drawn as it was while it goes.
pub fn publish_layer(c : @ui.Ctx, src : Source) -> Unit {
  let open = publishing.of.get()
  if open is Some(_) {
    publishing.drawn = open
  }
  guard publishing.drawn is Some((r, thread)) else { return }
  match @motion.presence(c, "publish", open is Some(_), initial=true, enter=@sf.window_page_in, exit=@kit.pop_out) {
    Some(look) => publish_page(c, src, r, thread, look, open is None)
    None => {
      publishing.drawn = None
      @sfbase.viz_close("publish/")
    }
  }
}

///|
/// The page that shares it (PublishDialog): over the whole window on the canvas, the picture as it would be at the
/// chat's width, what it is for over it (viewer_frame_act: the bar a file opened has, or 取消 and 保存到相册 at the
/// foot); Esc closes it. While its picture is taken, the picture drawn whole off the screen.
fn publish_page(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, look : @ui.Look, leaving : Bool) -> Unit {
  let p = publishing.preview.get()
  let messages = items(p, "list")
  let here : MessageHere = {
    station: r.station,
    session: r.session,
    view: match @sfbase.view_of_chat(src, r).0 {
      Some(v) => v
      None => @sfbase.chat_view_made(Json::null())
    },
    go: None,
    inline: true,
    gutter: 0.0,
    list: None,
    core: None,
  }
  // (the picture's width: the window's on a phone, less the column its boxes to tick stand in before it on the page)
  let column = dmin(c.width - publish_tick_room(), publish_page_w)
  // (dismissed by the hand: back, Escape; closed at that moment; not while its picture is being taken, back and Escape
  // its all the same then)
  let list_key = "publish/page/" + r.station + "/" + thread.to_string()
  c.with_dismissed(fn(_) { publish_close() }, fn() {
    let busy = fn() { @signals.untracked(fn() { publishing.busy.get() }) }
    c.overlay("publish", modal=true, stays=busy, scrim=@sf.alpha(@sf.theme().p.bg, look.alpha), inert=leaving, fn() {
      let list_node = Ref(-1)
      let page = c.box(style=publish_fill, fn() {
        match publishing.read.get() {
          0 => c.box(style=publish_note, fn() { @sf.wait_line(c, @sf.t("web-pages.chat.publish.reading"), key="publish/reading") }) |> ignore
          2 => c.box(style=publish_note, fn() { c.text(publishing.error.get(), style=publish_problem) |> ignore }) |> ignore
          _ if messages.length() == 0 =>
            c.box(style=publish_note, fn() { c.text(@sf.t("web-pages.chat.publish.empty"), style=publish_note_words) |> ignore })
            |> ignore
          _ =>
            list_node.val = c.list(list_key, 1, c.height, fn(_) {
              c.box(style=publish_column_room, fn() {
                // (under what is over it at the top, over the band at the foot)
                let top = @sf.room_of(@sf.viewer_act_head(c))
                let foot = @sf.room_of(publish_page_under + @sf.viewer_act_foot(c))
                c.box(style=@ui.style(w=Full, max_w=Fixed(publish_page_w + publish_tick_room()), pt=top, pb=foot), fn() {
                  publish_picture(c, src, here, p, column, false)
                })
                |> ignore
              })
              |> ignore
            })
        }
        // what it is for: on a wide screen the bar a file opened has (back to the chat), 复制图片 at its end; on a small
        // one 取消 and 保存到相册 at the foot
        c.layer(fn() {
          let (label, _) = @sf.picture_out_way()
          // (copied: 已复制 a moment after)
          let shown = publishing.copied.get() > 0 &&
            !@kit.after(c, "publish/copied/\{publishing.copied.get()}", true, @sf.copied_ms)
          let (closed, acted) = @sf.viewer_frame_act(
            c,
            "publish",
            if r.title != "" { r.title } else { @sf.t("common.close") },
            @sf.t("web-pages.chat.shareImage"),
            text(p, "hiddenText"),
            @sf.page_viewer_ink(),
            if shown { @sf.t("common.copied") } else { label },
            busy=publishing.busy.get(),
            disabled=p is None || publish_kept(p) == 0,
          )
          if acted && p is Some(_) && publish_kept(p) > 0 {
            publish_go(c)
          }
          if closed {
            publish_close()
          }
        })
        |> ignore
      })
      c.look(page, look)
      publish_walk(c, list_key, list_node.val)
      // the picture itself, while it is taken: the same, all of it, off the screen
      if messages.length() > 0 {
        c.shot(publish_shot, column, fn() { publish_picture(c, src, here, p, column, true) })
      }
    })
    |> ignore
  })
}

///|
/// The picture, `w` wide (as it is taken: `taking`; else as the page shows it): on the page's ground, the chat's name
/// over its messages as the chat's list draws them (its rows, out of a list: message_row; 2026-10-26 用户, of a picture
/// that drew them apart: 「渲染跟消息列表完全不一样」): the viewer's own in their bubbles at its end, an agent's cards as
/// cards, the heads in line with their pictures and the rows as far apart and in as the list has them at that width
/// (chat_list.mbt); still.fail's mark and name at its foot. On the page each attachment with its box to tick
/// (publish_file) and, under a message with something hidden in it, how many; in the picture taken only those ticked,
/// and its times dates (how long ago it was is not so for long).
fn publish_picture(c : @ui.Ctx, src : Source, here : MessageHere, p : Json?, w : Double, taking : Bool) -> Unit {
  let narrow = w <= chat_narrow_w
  let here = { ..here, inline: narrow }
  // (on the page, before its words a column for its messages' boxes to tick; the picture taken has none)
  let ticks = if taking { 0.0 } else { publish_tick_room() }
  let paper = if narrow { publish_paper_narrow } else { publish_paper }
  // (its edge's room, and how far in its words are: past the pictures out in the margin)
  let paper_edge = if narrow { row_side_narrow } else { publish_paper_in }
  let paper_in = if narrow { paper_edge } else { paper_edge + @sf.message_avatar_reach }
  // (how much was hidden in each, by its seq: the preview's `messages`, by their n)
  let hidden : Map[Double, String] = {}
  for m in items(p, "messages") {
    match text(Some(m), "hiddenText") {
      "" => ()
      h => hidden[number(Some(m), "n")] = h
    }
  }
  c.box(style=paper.then(@ui.style(pl=@sf.room_of(paper_in + ticks))), fn() {
    match text(p, "title") {
      "" => ()
      title => c.text(title, style=publish_title) |> ignore
    }
    c.box(style=if narrow { publish_list_narrow } else { publish_list }, fn() {
      for j in items(p, "list") {
        let m = picture_message(@sfbase.message_of(j), taking)
        let k = message_k(m.seq)
        let on = !publishing.off.contains(k)
        if taking && !on {
          continue
        }
        // on the page, its box to tick pointed at (or pressed): the whole of it lit, a band across the picture from
        // edge to edge (square: it runs out of its sides as a list's row does, nothing in its corners), half the room
        // between messages over and under it, so that lit one after another they meet
        let side = @sf.theme().rows.check
        let down = centred_in(first_line_h(c, m), side)
        let lit = if taking {
          0.0
        } else {
          let pointed = c.hand_lit(c.lit(c.id("publish/tick/" + k)))
          @motion.animate(c, "publish/lit/" + k, if pointed { 1.0 } else { 0.0 }, spec=@motion.tween(@sf.dur_ms, ease=Out))
        }
        let ground = if taking {
          publish_said
        } else {
          let start = paper_in + ticks
          let half = (if narrow { list_gap_narrow } else { list_gap }) / 2.0
          publish_said.then(@sf.bleed_start(start)).then(@sf.bleed_end(paper_edge)).then(@sf.bleed_y(half))
        }
        c.box(style=ground, fn() {
          if lit > 0.0 {
            let g = c.layer(fn() { c.box(style=publish_lit, fn() {  }) |> ignore })
            c.look(g, @ui.look(alpha=lit))
          }
          let said = c.box(style=publish_said, fn() {
            // (its files drawn each to tick: file_item asks picturing)
            picturing.val = Some((m.seq, taking))
            message_row(c, src, here, m)
            picturing.val = None
            // on the page its box to tick, in the column before the words (before the pictures out in the margin), on
            // the middle of its first line: its head's, or the first of the viewer's own bubble
            if !taking {
              c.layer(fn() {
                let style = @ui.style(ml=@sf.room_of(-(paper_in - paper_edge + ticks)), pt=@sf.room_of(down))
                c.box(style=publish_message_tick.then(style), fn() {
                  let look = @kit.checkbox_look_of(size=side, radius=@sf.theme().rows.check_corner)
                  let now = @kit.checkbox(c, "publish/tick/" + k, if on { On } else { Off }, label=@sf.t("web-pages.chat.publish.message"), look~).value
                  if (now == On) != on {
                    if now == On {
                      publishing.off.remove(k)
                    } else {
                      publishing.off[k] = true
                    }
                  }
                })
                |> ignore
              })
              |> ignore
            }
            match hidden.get(m.seq) {
              Some(h) if !taking =>
                c.box(style=if m.mine { publish_note_mine } else { publish_note_said }, fn() {
                  @sf.icon(c, "shield-check", size=publish_note_icon_small, color=@sf.theme().p.muted) |> ignore
                  c.text(h, style=publish_meta) |> ignore
                })
                |> ignore
              _ => ()
            }
          })
          let out = if taking { 0.0 } else { publish_out(c, k, on) }
          if out > 0.0 {
            c.look(said, @ui.look(alpha=publish_faded(out)))
          }
        })
        |> ignore
      }
    })
    |> ignore
    c.box(style=publish_foot, fn() {
      @sf.drawable(c, if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" }, publish_mark) |> ignore
      c.text("still.fail", style=publish_brand) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// While a message of the picture is drawn (publish_picture): its seq, and whether the picture is being taken. Its files
/// are drawn each to tick then (file_item: publish_file), a page of HTML its words place by publish_viz.
// kept across runs: None again after each message of the picture
let picturing : Ref[(Double, Bool)?] = Ref(None)

///|
/// Message `m` as the picture holds it: taken (`taking`), without the attachments left out, its time a date.
fn picture_message(m : Message, taking : Bool) -> Message {
  if !taking {
    return m
  }
  let kept = m.attachments.filter(fn(a) { !publishing.off.contains(file_k(m.seq, a)) })
  {
    ..m,
    attachments: kept,
    placed: m.placed.filter(fn(n) { kept.iter().any(fn(a) { a.name == n }) }),
    time: m.time.map(fn(s) { { ..s, ago: s.full } }),
  }
}

///|
/// Attachment `a` of message `seq`'s number in the preview (its `files`' `k`, by the message's n and where it is); ""
/// when it has none.
fn file_k(seq : Double, a : Attachment) -> String {
  for f in items(publishing.preview.get(), "files") {
    if number(Some(f), "n") == seq && text(field(Some(f), "file"), "path") == a.path {
      return text(Some(f), "k")
    }
  }
  ""
}

///|
/// An attachment of message `seq` in the picture, `w` wide, as the chat shows it (file_drawn). On the page, as what
/// waits to go in the composer has it, a ✕ hung on its top right corner (@sf.with_corner_remove) takes it out of the
/// picture (pressed anywhere on it too): it fades, its ✕ a ＋ that puts it back. In the picture taken (`taking`), as it
/// is, the room its mark hangs in kept.
fn publish_file(
  c : @ui.Ctx,
  src : Source,
  here : MessageHere,
  seq : Double,
  taking : Bool,
  a : Attachment,
  w : Double,
  by~ : (String, String, String)?,
) -> Unit {
  let k = file_k(seq, a)
  // (the room its mark is hung in kept in the picture too, so that it is laid out as the page has it)
  if taking || k == "" {
    c.box(style=@ui.style(pr=@sf.room_of(publish_file_hung())), fn() { file_drawn(c, src, here, a, w, by~) }) |> ignore
    return
  }
  publish_ticked(c, k, w=Some(w), fn() { file_drawn(c, src, here, a, w, by~) })
}

///|
/// Attachment `k` on the page, drawn by `draw` (`w` wide; None: as wide as there is), with its ✕ (publish_file).
fn publish_ticked(c : @ui.Ctx, k : String, w~ : Double?, draw : () -> Unit) -> Unit {
  let on = !publishing.off.contains(k)
  // (taken out: fading as its ✕ turns into a ＋, as long as a control's change takes)
  let out = publish_out(c, k, on)
  let id = c.id("publish/file/" + k)
  let hung = @sf.with_corner_remove(
    c,
    "publish/file/" + k,
    @sf.t(if on { "web-pages.chat.publish.leaveOut" } else { "web-pages.chat.publish.putBack" }),
    @sf.message_file_corner,
    w?=w,
    turn=out * publish_plus_turn,
    fn() {
      // (pressed anywhere, as its mark is: what the chat would open it by does not here)
      let card = c.box(style=publish_file_box, fn() {
        draw()
        c.layer(fn() { c.box(style=publish_file_press, id~, fn() {  }) |> ignore }) |> ignore
      })
      if out > 0.0 {
        c.look(card, @ui.look(alpha=publish_faded(out)))
      }
    },
  )
  if hung || c.clicked(id) {
    if on {
      publishing.off[k] = true
    } else {
      publishing.off.remove(k)
    }
  }
}

///|
/// Whether page of HTML `a`, placed in message `seq`'s words, is drawn as itself in the picture (publish_viz): on the
/// page where its host can grab it and it is in the picture (a view fades with nothing round it: one left out is its
/// card, to put back), in the picture taken once it was grabbed. Otherwise its card.
fn publish_viz_drawn(seq : Double, taking : Bool, a : Attachment) -> Bool {
  let k = file_k(seq, a)
  k != "" &&
  (if taking {
    publishing.stills.contains(k)
  } else {
    @ui.platform() != 4 && !publishing.off.contains(k) && !publishing.off.contains(message_k(seq))
  })
}

///|
/// Page of HTML `a` of message `seq` in the picture (publish_viz_drawn): in the picture taken, what it was grabbed as; on
/// the page, as the chat draws it, keeping nothing and sending nothing (the page's presses are its ✕'s, publish_ticked);
/// `card` when its file cannot be read.
fn publish_viz(c : @ui.Ctx, src : Source, here : MessageHere, seq : Double, taking : Bool, a : Attachment, card : () -> Unit) -> Unit {
  let k = file_k(seq, a)
  if taking {
    match publishing.stills.get(k) {
      Some((image, h)) =>
        c.box(style=@sfbase.viz_file_box, fn() {
          c.image(image, w=Fill(1.0), h=Px(h), fit=FitCover, bg=0L, fade=false) |> ignore
        })
        |> ignore
      None => card()
    }
    return
  }
  let loaded = @sfbase.viz_load(c, src, here.station, owner_of(here, a), a.path, size=a.size)
  if loaded is Some(Err(_)) {
    publishing.viz_failed[k] = true
    return card()
  }
  let place = "publish/" + here.station + ":" + here.session + "/" + k
  let box = c.id("publish/viz/" + k)
  publishing.viz_boxes[k] = (box, place)
  publish_ticked(c, k, w=None, fn() {
    c.box(style=@sfbase.viz_file_box, fn() {
      c.box(style=publish_file_box, id=box, fn() {
        match loaded {
          Some(Ok((html, state))) =>
            @sfbase.viz_frame(c, place, html, state, { keep: None, failed: None, follow_up: None })
          _ =>
            c.box(style=@sfbase.viz_wait_under, fn() {
              let i = c.box(style=@sfbase.viz_wait, fn() {  })
              @sf.breathe(c, i)
            })
            |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// An attachment left out (file[data-off]: .45); the shield before how much was hidden, in the bar (14) and under a
/// message (13).
let publish_off_alpha : Double = 0.45

///|
/// How far what `k` names is out of the picture (0 in it, 1 out), moving as its tick or its ✕ is pressed: as long as a
/// control's change takes (vars.dur), easing out.
fn publish_out(c : @ui.Ctx, k : String, on : Bool) -> Double {
  @motion.animate(c, "publish/out/" + k, if on { 0.0 } else { 1.0 }, spec=@motion.tween(@sf.dur_ms, ease=Out))
}

///|
/// How opaque it is, `out` of the picture.
fn publish_faded(out : Double) -> Double {
  1.0 - out * (1.0 - publish_off_alpha)
}

///|
/// The ✕ turned an eighth of a turn: a ＋.
let publish_plus_turn : Double = 0.7853981633974483

///|
let publish_note_icon_small : Double = 13.0

///|
/// The page over the whole window (fp): the canvas.
// kept across runs: a value (no field of it changes)
let publish_fill : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// Being read, not read, nothing to hold (fpNote: in the middle, muted, the ui's size).
// kept across runs: a value (no field of it changes)
let publish_note : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let publish_note_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let publish_problem : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger)

///|
/// What it would hold (page): the chat's width (760 at most) in the middle, right under what is over it at the top
/// (the bar on a wide screen, the status bar on a small one: its own 32 the room under them), 64 under (and the band at
/// the foot of a small screen).
// kept across runs: a value (no field of it changes)
let publish_column_room : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// The picture (page): 32 round what it holds, 32 down from its top and up from its foot, its parts 16 apart, on the
/// page's ground (what it is drawn on when it is taken too); its words the messages' pictures' room further in than
/// its end, as those stand out before them (@sf.message_avatar_reach).
// kept across runs: a value (no field of it changes)
let publish_paper : @ui.Style = @ui.style(
  w=Full,
  pl=@sf.room_of(publish_paper_in + @sf.message_avatar_reach),
  pr=S8,
  py=S8,
  gap=S4,
  bg=Bg,
)

///|
/// How far in from its sides what it holds is (S8's 32).
let publish_paper_in : Double = 32.0

///|
/// Narrow, its words as far in as the chat's list has them there (16: chat_list.mbt row_side_narrow).
// kept across runs: a value (no field of it changes)
let publish_paper_narrow : @ui.Style = @ui.style(w=Full, px=@sf.room_of(row_side_narrow), py=S8, gap=S4, bg=Bg)

///|
/// The chat's name over its messages (the chat's bar's title, its size).
// kept across runs: a value (no field of it changes)
let publish_title : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, w=Full)

///|
/// still.fail's mark and name at its foot, 6 apart, 8 under the last message, muted.
// kept across runs: a value (no field of it changes)
let publish_foot : @ui.Style = @ui.css("row pt=S2 gap=S1_5 align=ACenter")

///|
let publish_mark : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let publish_brand : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false)

///|
/// How far under the picture the page ends: 64, over the band of 取消 and 保存到相册 on a small screen.
let publish_page_under : Double = 64.0

///|
let publish_page_w : Double = 760.0

///|
/// How much was hidden in a message (note: its shield 6 before it, the meta's size, muted); under the viewer's own, at
/// its end as the message is.
// kept across runs: a value (no field of it changes)
let publish_note_said : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let publish_note_mine : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let publish_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The picture's messages, as far apart as the chat's list has them (28; narrow, 20: chat_list.mbt list_gap).
// kept across runs: a value (no field of it changes)
let publish_list : @ui.Style = @ui.style(w=Full, gap=@sf.room_of(list_gap))

///|
// kept across runs: a value (no field of it changes)
let publish_list_narrow : @ui.Style = @ui.style(w=Full, gap=@sf.room_of(list_gap_narrow))

///|
/// A message and, under it, how much was hidden in it (6 under).
// kept across runs: a value (no field of it changes)
let publish_said : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
/// A message's box to tick (on the page): in a column of its own before the picture's words, the paper's edge's room
/// before it and 12 after it (doc/ui-panels.md: what goes before a row is a column of its own, the words start after
/// it), not over the message; on the middle of the message's first line (first_line_h).
// kept across runs: a value (no field of it changes)
let publish_message_tick : @ui.Style = @ui.css("w=Full align=AStart")

///|
/// The column the boxes to tick stand in on the page: a box (the theme's rows' check) and 12 after it.
fn publish_tick_room() -> Double {
  @sf.theme().rows.check + publish_tick_gap
}

///|
let publish_tick_gap : Double = 12.0

///|
/// How far down something `h` high is to be in the middle of a line `line` high.
fn centred_in(line : Double, h : Double) -> Double {
  (line - h) / 2.0
}

///|
/// How high message `m`'s first line is, from its top: its head's line (its name, its time; S6), or for the viewer's
/// own that begins with its words, its bubble's first line (the bubble's 8 over a line of the theme's words); one that
/// begins with what it quotes or a file, the head's line as well.
fn first_line_h(c : @ui.Ctx, m : @sfbase.Message) -> Double {
  if m.mine && m.text != "" && m.quotes.length() == 0 && beside_quotes(m.quotes, m.attachments).length() == 0 {
    let line = c.style_size(@sf.theme().t.words).1
    bubble_in_y * 2.0 + line
  } else {
    head_line_h
  }
}

///|
/// An attachment on the page, faded once taken out.
// kept across runs: a value (no field of it changes)
let publish_file_box : @ui.Style = @ui.css("w=Full")

///|
/// A message's ground while its box to tick is pointed at: the hand's (hover).
// kept across runs: a value (no field of it changes)
let publish_lit : @ui.Style = @ui.css("w=Full h=Full bg=Hover")

///|
/// What takes its presses, all over it.
// kept across runs: a value (no field of it changes)
let publish_file_press : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The room its ✕ (＋ once taken out) hangs in past its top and right edge (@sf.with_corner_remove), kept in the
/// picture taken too.
fn publish_file_hung() -> Double {
  @sf.corner_remove_reach(@sf.message_file_corner)
}
