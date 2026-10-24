// What a chat's cards and buttons do (slice 8: ember apps/android chat/screens/Decisions.kt DecisionUnder, OptionButton;
// Chat.kt AskDismiss, ArchiveUnder, archiveChat; LoginCards.kt; AppState.kt act, isDoing), and the frame of the sheets
// over a chat (ui/Sheet.kt SheetHost, SheetGrab, SheetHead; sheets.mbt draws what is in them). What is done is said to
// the core as the Android app says it, under way on its button (a spinner), said in a toast when it could not be;
// nothing with MBUI_READONLY=1.

///|
/// A sheet over the pages (Sheet.kt SheetSpec): one at a time.
priv enum Sheet {
  /// the chat's own, from "…" (ChatInfo.kt)
  Info(ChatRef)
  /// an agent of the chat, by its session (AgentSheet.kt)
  AgentOf(ChatRef, String)
  /// the chat's services and jobs (Jobs.kt openJobs)
  JobsOf(ChatRef)
  /// one job, by its id (Jobs.kt openJob)
  JobOf(ChatRef, String)
  /// renaming the chat (ChatInfo.kt askTitle): its thread and its name as it was
  Rename(ChatRef, Double?, String)
  /// publishing the chat (Publish.kt openPublish): its station and thread
  Publish(String, Double)
  /// sharing the chat with the viewer's other workspaces (ChatInfo.kt openShare): its thread
  XShare(ChatRef, Double?)
  /// what can be done to an agent's context (AgentSheet.kt openContext): its session
  ContextOf(ChatRef, String)
  /// asking before an agent's context is cleared (AgentSheet.kt, PageParts.kt confirm): its session
  ClearContext(ChatRef, String)
  /// relaying the chat to a channel (Relay.kt openRelay): its thread
  Relay(ChatRef, Double)
  /// what its agents and other chats' wrote each other (Letters.kt openLetters): its thread
  LettersOf(ChatRef, Double)
}

///|
/// What this slice keeps while the app runs.
priv struct Decide {
  /// asks let go here, before the core says so (Chat.kt AskDismiss `gone`), by station, thread and post
  gone : Map[String, Bool]
  /// the sheet open; the one going (its motion is @kit.sheet's)
  mut sheet : Sheet?
  mut leaving : Sheet?
  /// the jobs' sheet shows all of them, not only those that matter now
  mut jobs_all : Bool
  /// the letters' sheet: the chat opened in it, by its key ("" the list of them)
  mut letters_open : String
  /// the chats whose letters were read for their sheet (the core's `chatLetters`), by station and session: their
  /// threads, let go as the chat is (chat.mbt chat_left)
  letters_held : Map[String, Double]
  /// a job's sheet: what it said (0) or its output (1)
  mut job_tab : Int
  /// the history's tab: its steps (0) or its details (1)
  mut history_tab : Int
  /// groups and steps of a history opened, by their key
  opened : Map[String, Bool]
  /// a history's page before asked for, by its first item (once a page)
  mut history_asked : String
  /// the steps asked to be read whole (`history.detail`), and when the answer came, by their entries
  detail_at : Map[String, Double]
  /// the 奏 page's front decision: its key, how far across it is dragged, whether a finger has it (its moves and speed the
  /// framework's drag's: decisions.mbt)
  mut front : String
  mut drag : Double
  mut held : Bool
  mut swiping : Bool
  /// the front one let go short of going: going back where it rests (3, decisions.mbt card_back), else 0; from
  /// where across
  mut going : Int
  mut going_from : Double
  /// the one that went (out of the deck at once), only drawn as it flies off: it, which way (1 right 不再提醒, -1
  /// left 待定, 2 up answered; decisions.mbt card_out), from where across
  mut out : Json?
  mut out_dir : Int
  mut out_from : Double
}

///|
let dui : Decide = {
  gone: {},
  sheet: None,
  leaving: None,
  jobs_all: false,
  letters_open: "",
  letters_held: {},
  job_tab: 0,
  history_tab: 0,
  opened: {},
  history_asked: "",
  detail_at: {},
  front: "",
  drag: 0.0,
  held: false,
  swiping: false,
  going: 0,
  going_from: 0.0,
  out: None,
  out_dir: 0,
  out_from: 0.0,
}

///|
/// As at the start (tests).
fn decide_reset() -> Unit {
  under_ends.clear()
  deck_anims.clear()
  dui.gone.clear()
  dui.sheet = None
  dui.leaving = None
  dui.jobs_all = false
  dui.letters_open = ""
  dui.letters_held.clear()
  dui.job_tab = 0
  dui.history_tab = 0
  dui.opened.clear()
  dui.history_asked = ""
  history_placed.clear()
  history_short.clear()
  history_marked.val = ("", "")
  dui.detail_at.clear()
  dui.front = ""
  dui.drag = 0.0
  dui.held = false
  dui.swiping = false
  dui.going = 0
  dui.going_from = 0.0
  dui.out = None
  dui.out_dir = 0
  dui.out_from = 0.0
  publish_reset()
  xsharing_reset()
}

// ── what comes and goes under a post ────────────────────────────────────

///|
/// ListMotion.kt closeGap: the room left closed by the rows' spring (critically damped, 350), a little late (100 ms).
// kept across runs: a curve, never written
let close_gap : @motion.Spec = @motion.spring(stiffness=350.0, threshold=0.002, delay=100.0)

///|
/// How long the archive buttons take to come and go (Chat.kt ArchiveEase's 280 ms), 忽略 too.
pub let archive_ms : Double = 280.0

///|
/// ArchiveEase (Chat.kt): a quick start, a soft landing.
// kept across runs: a curve, never written
pub let archive_ease : @motion.Ease = Soft

///|
/// How small the archive buttons (and 忽略) are as they have come or gone: 85%.
pub let archive_scale : Double = 0.85

///|
/// The archive buttons' curve and time (Chat.kt ArchiveEase, `archive_ms`): a quick start, a soft landing.
// kept across runs: a curve, never written
let archive_tween : @motion.Spec = @motion.tween(archive_ms, ease=archive_ease)

///|
/// The rooms under the posts as their motions were asked (under_post, by its key), kept to say when they are at rest.
let under_ends : Map[String, @motion.Anim] = {}

///|
/// When what comes and goes under the posts (options, how a card went, 忽略, the archive buttons) is at rest, their
/// rooms opening or closing on their springs and tweens (the frames' clock; -1: none moves; +inf: told to go, not
/// started yet): a test runs to it.
pub fn under_rest() -> Double {
  let mut end = -1.0
  under_ends.each(fn(_, a) { if a.ends_at() > end { end = a.ends_at() } })
  end
}

///|
/// What `body` builds under a post, shown or not as `shown` says (Compose's AnimatedVisibility with expandVertically /
/// shrinkVertically from its top): coming by `enter` (None: there at once, EnterTransition.None) as its room opens by
/// `open`, going by `exit` as its room closes by `close`; turned back mid-way from where it is; the first time as it
/// is. Its room is laid out (`@motion.reveal`, as the Android app's shrinkVertically lays it out, so what is under it
/// in the chat closes up); what is in it is only drawn while it goes (a tap is what is under it's). `start_at`: when
/// it was changed in its turn (Turns::in_turn), its motion from then.
fn under_post(
  c : @ui.Ctx,
  key : String,
  shown : Bool,
  enter? : @motion.Trans,
  open? : @motion.Spec = archive_tween,
  exit~ : @motion.Trans,
  close? : @motion.Spec = archive_tween,
  start_at? : Double,
  body : () -> Unit,
) -> Unit {
  let to = if shown { 1.0 } else { 0.0 }
  let h = @motion.anim(c, "under/" + key, to, global=true)
  let look = match enter {
    Some(e) => @motion.presence(c, "under-look/" + key, shown, enter=e, exit~, start_at?)
    None => {
      // there at once as it comes; going, by `exit`
      if shown {
        h.snap(1.0)
      }
      @motion.presence(c, "under-look/" + key, shown, enter=@motion.trans(spec=@motion.Snap(0.0)), exit~, start_at?)
    }
  }
  match start_at {
    Some(at) if h.target() != to => h.animate(to, if shown { open } else { close }, start_at=at)
    _ => h.follow(to, if shown { open } else { close })
  }
  under_ends[key] = h
  let share = h.get()
  let look = match look {
    Some(l) => l
    None => if share <= 0.0 { return } else { @ui.look(alpha=0.0) }
  }
  if h.moving() {
    @motion.log_frame(c, "under/" + key, "open=\{share} alpha=\{look.alpha} scale=\{look.sx}")
  }
  @motion.reveal(c, "under/" + key, share, fn() {
    let i = c.box(w=Fill(1.0), body)
    c.look(i, look)
    @motion.leaving(c, i, shown)
  })
}

// ── the cards in a chat ─────────────────────────────────────────────────

///|
/// An option picked (Decisions.kt DecisionUnder → answerDecision): the core sends it as the viewer's message quoting
/// the post (or, for an option the agent made to close, closes the card without one); the option's spinner meanwhile.
fn answer_option(src : Source, station : String, thread : Double, seq : Double, option : String) -> Unit {
  act(
    src,
    tr("android-misc.decisions.answerWhat"),
    "answer/" + seq_key(station, thread, seq) + "/" + option,
    "decision.answer",
    {
      "station": Json::string(station),
      "thread": Json::number(thread),
      "seq": Json::number(seq),
      "option": Json::string(option),
    },
  )
}

///|
/// The option of a card being answered, if one is.
fn answering(station : String, m : Message, options : Array[Choice]) -> String? {
  for o in options {
    if doing("answer/" + seq_key(station, m.thread, m.seq) + "/" + o.label) {
      return Some(o.label)
    }
  }
  None
}

///|
/// 忽略 under a post that asks what no one has decided (Chat.kt AskDismiss): gone at once, back if letting it go
/// failed (`decision.dismiss`). It goes as the archive buttons go (280 ms, ArchiveEase: fading, to 85% from its top
/// left, its room closing), in its turn among what changes the list's height (`turns`), and with the options once the
/// card is answered (`asking`, from `asked_at`).
fn ask_dismiss(
  c : @ui.Ctx,
  src : Source,
  here : Here,
  m : Message,
  asking : Bool,
  asked_at : Double,
  turns : Turns,
) -> Unit {
  let answered = match m.decision {
    Some(d) => d.resolved || d.dismissed
    None => false
  }
  if !m.asked && !answered {
    return
  }
  let k = seq_key(here.station, m.thread, m.seq)
  // (answered, it goes with the options, in their turn; let go here, in a turn of its own)
  let mine = turns.in_turn(c, "dismiss/" + k, (m.asked || answered) && !dui.gone.contains(k), dismiss_turn_ms)
  let shown = asking && mine
  let own_at = turns.started_at("dismiss/" + k)
  let at = if !asking { asked_at } else { own_at }
  let t = @sf.theme()
  let id = c.id("ask-dismiss/" + m.ts)
  if shown && c.clicked(id) {
    dui.gone[k] = true
    act(
      src,
      tr("android-misc.decisions.dismissWhat"),
      "",
      "decision.dismiss",
      {
        "station": Json::string(here.station),
        "thread": Json::number(m.thread),
        "seq": Json::number(m.seq),
      },
      failed=fn() { dui.gone.remove(k) },
    )
  }
  under_post(
    c,
    "dismiss/" + k,
    shown,
    exit=@motion.trans(fade=0.0, scale=archive_scale, ox=0.0, oy=0.0, spec=archive_tween),
    start_at?=if at >= 0.0 { Some(at) } else { None },
    fn() {
      // (6 under the options)
      c.box(pt=6.0, fn() {
        c.box(id=if shown { id } else { 0 }, fn() {
          c.rich([@ui.span(tr("android-chat.asks.dismiss"))], size=12.0, color=t.p.muted, line=18.0) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
  )
}

///|
/// The chat into the archive (Chat.kt archiveChat; its bar's 归档, the one under its last 做完了, its sheet's): Home at
/// once, the chat gone from the list meanwhile (the core's), said when it is done, or why not.
fn archive_chat(src : Source, r : ChatRef, v : ChatView) -> Unit {
  home()
  let p : Map[String, Json] = {
    "station": Json::string(r.station),
    "session": Json::string(r.session),
    "archived": Json::boolean(true),
  }
  match v.thread {
    Some(th) => p["thread"] = Json::number(th)
    None => ()
  }
  act(
    src,
    tr("android-chat.archive.verb"),
    "archive/" + r.station + "/" + r.session,
    "chat.archive",
    Json::object(p),
    done=tr("android-chat.archived"),
  )
}

// ── the sheets' frame ───────────────────────────────────────────────────

///|
/// Opens `s` over the pages (one at a time: the one open goes).
fn open_sheet(c : @ui.Ctx, s : Sheet) -> Unit {
  dui.sheet = Some(s)
  dui.leaving = None
  c.blur()
}

///|
/// Closes the sheet open, which goes down.
fn close_sheet(c : @ui.Ctx) -> Unit {
  match dui.sheet {
    Some(s) => dui.leaving = Some(s)
    None => ()
  }
  dui.sheet = None
}

///|
/// What a fitted sheet shows, as wide as it and as tall as what it holds (measured for the sheet's height).
// kept across runs: a value (no field of it changes)
let sheet_fitted : @ui.Style = @ui.css("w=Full")

///|
/// Under what a sheet shows, the navigation bar's room: what it shows kept above the bar, its ground going on down to
/// the screen's foot (Sheet.kt: windowInsetsPadding(keyboard.union(navigationBars)) inside the sheet).
fn sheet_foot(c : @ui.Ctx) -> Unit {
  if nav_foot() > 0.0 {
    c.box(style=@ui.style(w=Full, h=Fixed(nav_foot())), fn() {  }) |> ignore
  }
}

///|
/// A sheet from the bottom (Sheet.kt SheetHost, mbui's @kit.sheet): the scrim (black at 28%) closing it when tapped;
/// the sheet `tall` high (its share of the screen), or with `fit` as tall as what it shows, or with `fit_to` that
/// tall over the navigation bar (SheetSpec fit: Android's own reckoning of what it shows, what is more scrolling in it),
/// at most 90%; its top corners 26 round, frosted over the page and the scrim (@sf.sheet_look); it rises and sinks on the
/// sheet's spring, drawn only as it goes (a tap meanwhile is what is under it's). The decisions' sheets are one sheet:
/// one asked in place of another goes to its height.
fn sheet_frame(
  c : @ui.Ctx,
  key : String,
  tall : Double,
  body : () -> Unit,
  fit? : Bool = false,
  fit_to? : Double = 0.0,
  draggable? : Bool = false,
) -> Unit {
  let leaving = dui.sheet is None
  // fitted: what it shows as laid out (the frame before); `tall`, its share, until that is known
  let fit_key = "sheet-fit/" + key
  let h = match (fit, @motion.measured(c, fit_key)) {
    _ if fit_to > 0.0 => fit_to + nav_foot()
    (true, Some(m)) => m
    _ => tall
  }
  let r = @kit.sheet(
    c,
    "decide-sheet",
    !leaving,
    h=dmin(h, c.height * 0.9),
    // a draggable one between half (55%) and nearly all (94%) of the screen, a tap on its grabber to the other (Sheet.kt)
    detents=if draggable { sheet_detents } else { [] },
    scrim=@sf.sheet_scrim,
    look=@sf.sheet_look(),
    fn() {
      if fit_to > 0.0 {
        // the grabber, then what it shows scrolling in the room left over the navigation bar (Sheet.kt: the content's
        // Column(weight(1f).verticalScroll))
        @sf.sheet_grab(c)
        c.box(style=sheet_scrolled, fn() {
          c.list("sheet-scroll/" + key, 1, fit_to, fn(_) { body() }) |> ignore
        })
        |> ignore
        sheet_foot(c)
      } else if fit {
        // laid out at what it needs, kept for the next frame's height
        let shown = c.box(style=sheet_fitted, fn() {
          @sf.sheet_grab(c)
          body()
          sheet_foot(c)
        })
        @motion.measure(c, shown, fit_key)
      } else {
        // its share: what it shows may fill it (a list scrolling in it)
        @sf.sheet_grab(c)
        body()
        sheet_foot(c)
      }
    },
  )
  if !leaving && !r.open {
    close_sheet(c)
  }
  if leaving && !r.shown {
    dui.leaving = None
  }
}

///|
/// What a sheet reckoned by `fit_to` shows: the room between its grabber and its foot.
// kept across runs: a value (no field of it changes)
let sheet_scrolled : @ui.Style = @ui.style(w=Full, h=@sf.grow)

///|
/// Where a draggable sheet settles: half the screen and nearly all of it (Sheet.kt SheetHost: 0.55, 0.94).
// kept across runs: a table, never written
let sheet_detents : Array[Double] = [0.55, 0.94]

///|
/// A sheet's head (Sheet.kt SheetHead): its title, 17 bold.
fn sheet_head(c : @ui.Ctx, title : String) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=4.0, pb=10.0, align=ACenter, fn() {
    c.text(title, size=17.0, weight=700, color=t.p.text, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// The sheet open over the pages, or the one going down.
fn sheets(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let s = match (dui.sheet, dui.leaving) {
    (Some(s), _) => s
    (None, Some(s)) => s
    _ => return
  }
  match s {
    Info(r) => chat_info_sheet(c, src, w, r)
    AgentOf(r, key) => agent_sheet(c, src, w, r, key)
    JobsOf(r) => jobs_sheet(c, src, r)
    JobOf(r, id) => job_sheet(c, src, r, id)
    Rename(r, thread, was) => rename_sheet(c, src, r, thread, was)
    Publish(station, thread) => publish_sheet(c, src, station, thread)
    XShare(r, thread) => xshare_sheet(c, src, r, thread)
    ContextOf(r, key) => context_sheet(c, src, r, key)
    ClearContext(r, key) => clear_context_sheet(c, src, r, key)
    Relay(r, thread) => relay_sheet(c, src, r, thread)
    LettersOf(r, thread) => letters_sheet(c, src, r, thread)
  }
}
