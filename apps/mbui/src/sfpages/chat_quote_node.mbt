// A passage of a message picked with the mouse in a chat's page made as nodes, quoted into its draft (the old page's
// pick_pop: sfbase's pick.mbt; web Chat.tsx useSelectionQuote, Chat.css.ts quotePop): once the pointer has let go of a
// pick wholly within one message, a small dark pill 引用 with its mark 8 over the end it let go (mbui's picked_now,
// picked_end_piece); pressed, what is picked kept (keeps_picked), quoted as the old page quoted it (whose words, the
// words, the message, as what: chat_layers'), let go, and gone. A pick across messages, or in a row that is no message
// with an id to quote by (what is on its way from here, a notice's line, the list's own rows), gives none. A finger's
// pick has no pill: the system's text menu over it offers 引用 after its copy and select all (mbui's picked_menu), doing
// the same, and after it what that message offers of itself where it offers it (message_items' but its words, which
// the system's copy has: 多选, its turn shared from the chat's picture; 复制链接, its link), as the old finger's bar
// over a passage held (sfbase's pick_bar) did.

///|
/// The message of chat `rows` whose words a mouse's pick lies wholly within, once the pointer let it go: what is
/// picked and the message (a message the core has, by its ts: the id the old page quoted by); none otherwise.
fn chat_quotable(rows : () -> ChatBodyRows) -> (@ui.WordsPicked, Message)? {
  guard chat_picked_message(rows) is Some((p, m)) && !p.finger else { return None }
  Some((p, m))
}

///|
/// The message of chat `rows` whose words what is picked lies wholly within, once let go, with the mouse or a finger
/// (one the viewer sent not yet the chat's too: outgoing_said): what is picked and the message; none otherwise.
fn chat_picked_message(rows : () -> ChatBodyRows) -> (@ui.WordsPicked, Message)? {
  guard @ui.picked_now() is Some(p) && p.of.length() == 1 else { return None }
  match rows().rows.get(p.of[0]) {
    Some({ entry: Said(m), .. }) if m.ts != "" => Some((p, m))
    // (one of the viewer's not the chat's yet, on its way or failed: theirs, of no message, as the old rows quote it)
    Some({ entry: Out(o), .. }) => Some((p, outgoing_said(o)))
    _ => None
  }
}

///|
/// What is picked within one message of chat `rows` quoted into draft `draft` (writing_quote: whose words and as what,
/// as the old rows said them, sfpages' picking; its text trimmed, nothing where that is empty) and let go; picked
/// across messages or in no message, nothing done, what is picked left as it is.
fn chat_quote_take(src : Source, draft : String, rows : () -> ChatBodyRows) -> Unit {
  guard @signals.untracked(fn() { chat_picked_message(rows) }) is Some((p, m)) else { return }
  let text = p.text.trim(chars=" \n\t").to_owned()
  if text != "" {
    let author = if m.mine { @sf.t("web-main.chat.you") } else { m.by.name }
    let role = if !m.mine && m.author_kind == "agent" { "agent" } else { "person" }
    @sfbase.writing_quote(src, @sfbase.writing(src, draft), {
      "author": Json::string(author),
      "text": Json::string(text),
      "ts": Json::string(m.ts),
      "role": Json::string(role),
    })
  }
  @ui.picked_let_go()
}

///|
/// Over chat `r`'s list in `v` (its rows `rows`, each of whose words are said of its key: chat_body_row's picked_of):
/// the pill 引用 over a mouse's pick within one message, quoting it into the chat's draft (writing_quote, its text
/// trimmed, nothing where that is empty), what is picked let go then. One for each pick (its `made`). A finger's pick
/// in what `v` holds is offered the same in the system's text menu (picked_menu), and the message's own items there
/// (its MessageShare in the chat `here` is: message_share_of).
fn chat_quote_node(v : @view.View, src : Source, r : ChatRef, here : MessageNodeHere, rows : () -> ChatBodyRows) -> Unit {
  let draft = r.station + ":" + r.session
  // (a finger's pick: 引用 in the system's text menu over it, for what the list holds, where it lies within one message;
  // then its turn shared and its link copied, where it offers them, what is picked let go as either is chosen)
  @ui.picked_menu(v, fn(_) {
    guard chat_picked_message(rows) is Some((_, m)) else { return [] }
    let items = [(@sf.t("web-main.chat.quote"), fn() { chat_quote_take(src, draft, rows) })]
    // (one not the chat's yet has no turn to share, no link)
    match (if m.ts == "" { None } else { message_share_of(src, here, fn() { m }) }) {
      Some(s) => {
        items.push((@sf.t("web-main.chat.selectMessages"), fn() {
          @ui.picked_let_go()
          (s.go)()
        }))
        let link = (s.link)()
        if link != "" {
          items.push((@sf.t("common.link.copy"), fn() {
            @sfbase.copy_out(link, said=@sf.t("common.link.copied"))
            @ui.picked_let_go()
          }))
        }
      }
      None => ()
    }
    items
  })
  |> ignore
  v.pick(fn() { chat_quotable(rows).map(fn(q) { q.0.made }) }, fn(holds, made) {
    guard made is Some(_) && @signals.untracked(fn() { chat_quotable(rows) }) is Some((p, _)) else { return }
    holds.box(fn(b) {
      @sf.style_node(b, fn() { chat_quote_pill })
      @ui.keeps_picked(b)
      .ground(By(fn() { @ui.tree_theme().color(if @sf.lit_node(b) { chat_quote_lit } else { Primary }) }))
      .shadow(
        By(fn() {
          let (blur, fall) = @ui.Shadow::Md.blur_y()
          (blur, fall, @ui.tree_theme().shadow)
        }),
      )
      .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.chat.quote"))) }))
      .beside(p.ends_in, side=Top, offset=8.0, piece=@ui.picked_end_piece(p))
      .on_press(fn() { chat_quote_take(src, draft, rows) })
      |> ignore
      @sf.icon_node(b, "quote", chat_quote_icon, By(fn() { @sf.theme().p.on_primary })) |> ignore
      @sf.words_node(b, fn() { @sf.t("web-main.chat.quote") }, fn() { chat_quote_words }) |> ignore
    })
    |> ignore
  })
}

///|
/// The pill (quotePop: 26 high, 10 in, its mark 4 before its words, round, on the primary ground with a shadow, a step
/// towards the page where the hand is on it: mbui ui/hand_moves.mbt), its mark 12, its words.
// kept across runs: a value (no field of it changes)
let chat_quote_pill : @ui.Style = @ui.style(
  row=true,
  h=@sf.quote_pop_h,
  px=S2_5,
  gap=S1,
  radius=Full,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let chat_quote_lit : @ui.Color = Over(Primary, A(Bg, O15))

///|
let chat_quote_icon : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let chat_quote_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Medium, color=OnPrimary, wrap=false)
