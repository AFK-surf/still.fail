// What an agent (or still.fail itself) said, as nodes of the window's tree, made once (message.mbt's others_message
// with prose_with_files): under its picture, name and time, its words as the core read their Markdown (markdown_node:
// its links pressed where they lead and held for their menus, a bare link to a chat read as its title, the files its
// paths name its agent's chips, the files it places drawn where it places them, a link to a station's screens its card
// and a bare one its title: screen_links_node; each link's card while a mouse rests on it: message_link_card), its other
// files under them, what it asks under it (message_decision_node).
// What it quotes ahead of its words (message_quotes_node), each quote's own file in its card and not under its words.
// Each read through what it is given, as that changes.
// Not here yet, each where it comes in:
// - a Mermaid chart: as its code till then; `code` takes viz_mermaid_node once it is in main (#5525).
// - a vault item's card asking for a file to be picked (message_card_node's NotYet): nothing drawn for it yet.
// - its picture held under the pane's top as a long one scrolls past (c.stick).
// Its coming out of its agent's picture is here (agent_said_node's `out_of`): grown out of it, one flight; the line
// folding to its picture first and the picture's own glide (emit.mbt's Fold, Float, Return) are not.

///|
/// The card an agent's message shows in place of its words (prose_with_files'), by kind: a vault item's, a phone's, a
/// sign-in's, a rig's; "" none.
fn agent_card_kind(m : Message) -> String {
  match m.card {
    Some({ ask: Some(_), .. }) => "vault"
    Some({ phone: Some(_), .. }) => "phone"
    Some({ signin: Some(_), .. }) => "signin"
    Some({ rig: Some(_), .. }) => "rig"
    _ => ""
  }
}

///|
/// A station's screens' cards in what message `m` says (screen_links_node), each one's preview by the message and its
/// link, as the old view's (message.mbt's screen_links).
fn agent_screens(src : Source, here : MessageNodeHere, m : () -> Message) -> @sf.ScreensNode {
  let ts = @signals.untracked(m).ts
  @sfbase.screen_links_node(src, message=here.station + "/" + here.session + "/" + ts)
}

///|
/// What an agent or still.fail said (others_message's with prose_with_files) in its row's room (message_row_frame_node:
/// `key`, its list's Entry::id; `side`, `top`; `over`), as `m` says it as it changes: its picture out in the margin
/// (inline: over the head's start), its name (one of the chat's agents' opens its history), its time; its words as
/// prose_node_of draws them, its other files under them, what it asks under them (message_decision_node); where it
/// offers itself (`share`), its ⋯ and a right click's offer. `code`, `screens` (a station's screens' cards by default:
/// screen_links_node) and `shown` as agent_prose_node takes them.
// the chat's page as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn agent_said_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  key : String,
  side : () -> Double,
  top : () -> Double,
  m : () -> Message,
  found? : () -> Array[String] = fn() { [] },
  found_at? : () -> Int? = fn() { None },
  lit? : () -> (String, Int64) = fn() { ("", 0L) },
  share? : MessageShare? = None,
  over? : (@view.View, String) -> Unit = fn(_, _) {  },
  code? : (String) -> ((@view.View, () -> String) -> Unit)? = fn(_) { None },
  screens? : @sf.ScreensNode,
  shown? : (@view.View, Array[(String, String, Int)]) -> Unit,
  core? : @settings.Core? = None,
  out_of? : (@view.View, @motion.Way)? = None,
) -> MessageRowNode {
  let menu_on : Ref[() -> Bool] = Ref(fn() { false })
  let row = message_row_frame_node(v, key, side, top, over~, fn(r) {
    // (come by data while its agent was at work: out of that agent's picture on its line (`out_of`), as emit.mbt's, each
    // step from the cause's moment: the line folds into its picture (Fold); its own picture glides there from that one
    // (Float, a flight: View::flies_in); its head and its words come out of it, the words a glyph at a time (Spit,
    // emit_out's, sfbase's glyph_in); the line unfolds again (Return))
    let out = match out_of {
      Some((face, fold)) => Some(agent_out_steps(r, face, fold))
      None => None
    }
    let out_glyphs = out.map(fn(o) { o.glyphs })
    let (_, on) = message_others_node(
      r,
      here,
      fn() { m().time },
      fn(av) {
        // (an agent's its maker's mark; still.fail's own its mark; one of the chat's agents' with its card over it under
        // a pointer, agent_hover's: a finger's by its name)
        let pic = agent_avatar_node(
          av,
          fn() { if m().author_kind == "agent" { m().by.maker } else { "" } },
          fn() { if m().author_kind == "agent" { m().by.runtime } else { "" } },
          fn() { "" },
        )
        let agent = @signals.untracked(fn() { if m().author_kind == "agent" { message_agent_of(here, m().by.agent) } else { "" } })
        if agent != "" {
          message_agent_card_node(pic, src, here, agent, pointed=true)
        }
        // (out of its agent's picture at work: from there, Float)
        match out {
          Some(o) => (o.avatar)(av)
          None => ()
        }
      },
      fn(h) {
        message_name_node(h, src, here, fn() { m().by.name }, fn() { message_agent_of(here, m().by.agent) }, fn() {
          m().by.from
        })
        // (out of its picture: sliding out beside it, Spit)
        match out {
          Some(o) => (o.head)(h)
          None => ()
        }
      },
      None,
      fn(b) {
        // (what it quotes ahead of its words, as the old body's)
        message_quotes_node(b, src, here, fn() { m().quotes }, fn() { m().attachments }, false, message_place(@signals.untracked(m)), said=fn() { m().said })
        // (its words, or the card in their place: one in the other's place as the post says)
        b.pick(fn() { agent_card_kind(m()) == "" }, fn(p, words) {
          // (what is read in it starts here, its words or the card in their place, under its head line and what it
          // quotes: what a page's list holds what shows by, where it starts (View::read_from))
          p.read_from() |> ignore
          // (and what is picked of it is of its key, what is read of it alone, not its head line: quoted by it, all of
          // it taken by 全选, chat_quote_node)
          @ui.picked_of(p, key, whole=true) |> ignore
          if words {
            // (its words and its files one piece, none apart, as the old list holds them to be picked: pickable's
            // pick_fill; a letter's, drawn by the old view alone, has them 4 apart)
            @sf.style_node(p, fn() { agent_prose_piece })
            agent_prose_node(p, src, here, m, found~, found_at~, lit~, code~, screens=screens.unwrap_or(agent_screens(src, here, m)), shown?, glyphs?=out_glyphs)
          } else {
            message_card_node(p, here, core, m)
          }
        })
        // (what it asks under it, where it asks anything: nothing else made, as no gap is wanted for nothing; a login's
        // card where there is a core to read it with)
        b.show(
          fn() {
            match decision_asks(m()) {
              Nothing => false
              Login => core is Some(_)
              _ => true
            }
          },
          fn(d) { message_decision_node(d, src, here, m, core~) },
        )
      },
      share~,
    )
    menu_on.val = on
  })
  { ..row, menu_on: menu_on.val }
}

///|
/// An agent's message's words and files (prose_with_files') in `v`, as `m` says them as they change: its words as the
/// core read their Markdown at the body's size, those `found` says in bold (and marked where `found_at` says: markdown_node's), the passage `lit` says lit where they have it; a link tapped opens where it leads (a file
/// it places, that file; a path, that file of its agent's; else the link), held (or right clicked) its menu; a bare link
/// to a chat read as that chat's title; its paths its agent's files' chips; the files it places drawn where it places
/// them (their cards); the rest of its files under its words. `code`: what draws a fenced block of a language another
/// way (none: as code); `screens`: links to a station's screens as cards (none: as links); `shown`: its links told as
/// they change (what a card over one is drawn by).
fn agent_prose_node(
  v : @view.View,
  src : Source,
  here : MessageNodeHere,
  m : () -> Message,
  found? : () -> Array[String] = fn() { [] },
  found_at? : () -> Int? = fn() { None },
  lit? : () -> (String, Int64) = fn() { ("", 0L) },
  code? : (String) -> ((@view.View, () -> String) -> Unit)? = fn(_) { None },
  screens? : @sf.ScreensNode,
  shown? : (@view.View, Array[(String, String, Int)]) -> Unit,
  glyphs? : ((@view.View) -> Double, (Double, @view.GlyphAt) -> @view.GlyphLook)? = None,
) -> Unit {
  let place = message_files_at(here, fn() { m().said })
  let at = message_place(@signals.untracked(m)) + "/f"
  let by = fn() -> (String, String, String)? {
    let now = m()
    Some((now.by.name, if now.author_kind == "agent" { "agent" } else { "person" }, now.ts))
  }
  // (its files beside what it quotes; those it places by their names, the rest under its words)
  let files = fn() {
    let now = m()
    beside_quotes(now.quotes, now.attachments)
  }
  let placed = fn(name : String) -> Attachment? {
    if m().placed.contains(name) {
      files().iter().find_first(fn(a) { a.name == name })
    } else {
      None
    }
  }
  let rest = fn() {
    let names = m().placed
    files().filter(fn(a) { !names.contains(a.name) })
  }
  let on_link = fn(h : String) {
    let now = @signals.untracked(m)
    let old_here = place.here()
    match @signals.untracked(fn() { placed(@sf.file_name_of(h)) }) {
      Some(a) if is_viz(a.name) =>
        viz_open_full(a.name, here.station, owner_of(old_here, a), a.path, here.session, linked=true)
      Some(a) => open_file(old_here, a, at~)
      None =>
        match @sf.path_of_link(h) {
          Some((path, _)) => open_named(src, here.station, now.by.agent, path)
          None => open_link(h)
        }
    }
  }
  let on_hold = fn(href : String, at : (Double, Double, Double, Double)) {
    match @sf.path_of_link(href) {
      Some((path, _)) => message_path_held(src, here.station, @signals.untracked(m).by.agent, path, at)
      None => message_link_held(href, at)
    }
  }
  v.show(fn() { m().text != "" }, fn(w) {
    @sf.markdown_node(
      w,
      fn() { m().text },
      tree=fn() { m().md },
      size=fn() { body_size },
      found~,
      found_at~,
      lit~,
      // (its tables slid sideways out over the row's side to the pane's edge: the side as the list is laid out when it
      // is made, markdown_node's bleed being a number)
      bleed=@signals.untracked(fn() { row_side((here.width)()) }),
      on_link~,
      on_link_hold=Some(on_hold),
      on_link_shown?=shown,
      // (each link's card while a mouse rests on it: link_peeks', its agent's files read in its working directory)
      link_cards=(here.tips, message_link_card(src, here.station, @signals.untracked(m).by.agent, m)),
      chat_title=fn(h) { chat_title_of(m())(h) },
      // the files its paths name are its agent's (Chat.tsx ProseWithFiles' PathSession): their chips
      paths=@signals.untracked(m).by.agent != "",
      glyphs~,
      // (a file it places: its card where it places it; a picture's its box, side by side with others, in a table's cell)
      files=fn(name) {
        let card = fn(a) {
          fn(d) { message_files_node(d, src, here.tips, place, fn() { [a] }, fn() { false }, by, at) }
        }
        match placed(name) {
          // an HTML page: drawn as a page where it is placed (message_viz_node), its card where it cannot be read
          Some(a) if is_viz(a.name) =>
            Some({
              draw: fn(d) {
                let ts = @signals.untracked(m).ts
                message_viz_node(d, src, here.tips, here.station, here.session, owner_of(place.here(), a), ts, a, card(a))
              },
              image: None,
            })
          // (a picture: its width over its height and its box as wide as it is given there, side by side with others or
          // in a table's cell; made again only for another size, as message_files_node's)
          Some(a) =>
            Some({
              draw: card(a),
              image: image_ratio(a).map(fn(r) {
                (
                  r,
                  fn(d : @view.View, width : () -> Double) {
                    d.pick(at_once=true, fn() { width() }, fn(q, w) {
                      message_image_node(q, src, place, fn() { a }, by, at, w, w / r)
                    })
                    |> ignore
                  },
                )
              }),
            })
          None => None
        }
      },
      code~,
      screens?,
    )
    |> ignore
  })
  message_files_node(v, src, here.tips, place, rest, fn() { false }, by, at)
}

///|
/// What an agent said and its files under it in a chat's list: one piece, none apart (sfbase's pick_fill, pickable's
/// box round them).
// kept across runs: a value (no field of it changes)
let agent_prose_piece : @ui.Style = @ui.css("w=Full")

///|
/// A file a message names by its path (`path`, its agent `agent`'s on `station`) held (or right clicked: path_held's),
/// its menu by the piece of line under the hand (`at`, in the window): 在侧边打开 where it is offered (beside_offered: a
/// side panel for the chat, a file, a kind that opens there); else nothing.
fn message_path_held(src : Source, station : String, agent : String, path : String, at : (Double, Double, Double, Double)) -> Unit {
  if path.has_suffix("/") || !@sfbase.beside_offered(path, stored_name(path)) {
    return
  }
  @sf.menu_held_node()
  @sf.menu(
    [
      Some(
        @sf.menu_item_of(@sf.t("web-main.preview.openBeside"), fn() { open_named(src, station, agent, path, beside=true) }, icon="panel-open"),
      ),
    ],
    from=At(at.0, at.1, at.2, at.3),
  )
}

///|
/// What an agent's message coming out of its picture at work does (agent_said_node's `out_of`; emit.mbt's poses, each
/// from the cause's moment): its glyphs' look as they come (Spit: emit_out's, sfbase's glyph_in, read a line at a time
/// and along it), its picture's way from that one (Float), its head's coming out beside it (Spit).
priv struct AgentOut {
  glyphs : ((@view.View) -> Double, (Double, @view.GlyphAt) -> @view.GlyphLook)
  avatar : (@view.View) -> Unit
  head : (@view.View) -> Unit
}

///|
/// An agent's message in row `r` come out of its agent's picture at work `face`, whose line is `fold` (1 shown): the
/// line folds (Fold), the message's picture glides from that one to its own place (Float, a flight: View::flies_in),
/// its head slides out beside it and its words come a glyph at a time (Spit), and the line unfolds (Return).
fn agent_out_steps(r : @view.View, face : @view.View, fold : @motion.Way) -> AgentOut {
  let at = r.cause_at()
  let fold_ms = @sfbase.Pose::Fold.ms()
  let float_ms = @sfbase.Pose::Float.ms()
  let spit_ms = @sfbase.Pose::Spit.ms()
  let out_at = at + fold_ms + float_ms
  // det-ok(motion-length): emit.mbt's Fold, Float, Spit and Return, a message coming out of its agent's picture
  fold.go(0.0, @motion.tween(fold_ms, ease=Out), at~)
  r.at_moment(out_at + spit_ms, fn() { fold.go(1.0, @motion.tween(@sfbase.Pose::Return.ms(), ease=Out), at=out_at + spit_ms) })
  |> ignore
  // (how long since it came out, ms: its words and head by it, nothing before)
  let since = @motion.Way::new(0.0)
  r.at_moment(out_at, fn() { since.go(1.0, @motion.tween(@sfbase.emit_out_ms_most, ease=Linear), at=out_at) }) |> ignore
  let salt = 7
  {
    glyphs: (fn(w) { since.shown_on(w) * @sfbase.emit_out_ms_most }, fn(ms, g) {
      @sfbase.glyph_in(ms, (g.line.to_double() + g.cx / 600.0) * @sfbase.glyph_line_ms, g.index, salt)
    }),
    avatar: fn(av) {
      av.flies_in(after(fold_ms, float_ms), fn(_) { Some(face.laid_window_now()) }) |> ignore
    },
    head: fn(h) {
      h.alpha(By(fn() { @ui.Ease::Out.at(dmin_one(since.shown_on(h) * @sfbase.emit_out_ms_most / @sfbase.emit_head_ms)) }))
      |> ignore
    },
  }
}

///|
/// A flight still for `wait` ms, then on over `ms` (emit.mbt's Float: a glide from rest to rest).
fn after(wait : Double, ms : Double) -> @view.Flight {
  { way: fn(_) { (wait + ms, fn(t) { if t <= wait { 0.0 } else { @ui.Ease::InOut.at(dmin_one((t - wait) / ms)) } }) } }
}

///|
fn dmin_one(x : Double) -> Double {
  if x > 1.0 {
    1.0
  } else {
    x
  }
}
