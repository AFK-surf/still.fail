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
}

///|
/// What this slice keeps while the app runs.
priv struct Decide {
  /// what was set going and is not answered yet (AppState.isDoing), by its call and what it is of
  doing : Map[String, Bool]
  /// asks let go here, before the core says so (Chat.kt AskDismiss `gone`), by station, thread and post
  gone : Map[String, Bool]
  /// what failed a moment ago (the core's doing, `stage: failed`, kept 6 s: DoingMark's red mark), by its key, which
  /// failure it is (failed_serial: each its own 6 s)
  failed : Map[String, Int]
  mut failed_n : Int
  /// the sheet open; the one going (its motion is @kit.sheet's)
  mut sheet : Sheet?
  mut leaving : Sheet?
  /// the jobs' sheet shows all of them, not only those that matter now
  mut jobs_all : Bool
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
  /// the 奏 page: decisions answered or let go here (not shown) and set aside here (last), until the core's list
  /// has them so (Decisions.kt DecisionsLocal)
  dgone : Array[String]
  dlater : Array[String]
  /// the front decision: its key, how far across it is dragged, whether a finger has it (its moves and speed the
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
  doing: {},
  gone: {},
  failed: {},
  failed_n: 0,
  sheet: None,
  leaving: None,
  jobs_all: false,
  job_tab: 0,
  history_tab: 0,
  opened: {},
  history_asked: "",
  detail_at: {},
  dgone: [],
  dlater: [],
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
  dui.doing.clear()
  dui.gone.clear()
  dui.failed.clear()
  dui.sheet = None
  dui.leaving = None
  dui.jobs_all = false
  dui.job_tab = 0
  dui.history_tab = 0
  dui.opened.clear()
  dui.history_asked = ""
  dui.detail_at.clear()
  dui.dgone.clear()
  dui.dlater.clear()
  dui.front = ""
  dui.drag = 0.0
  dui.held = false
  dui.swiping = false
  dui.going = 0
  dui.going_from = 0.0
  dui.out = None
  dui.out_dir = 0
  dui.out_from = 0.0
}

///|
/// Says `words` in the toast from the next frame on (from a call's answer, between frames).
fn toast_later(words : String) -> Unit {
  app.toast = words
  app.toast_n += 1
}

///|
/// Has the core do something (AppState.act): `key` under way until it answers (its button's spinner), `done` said
/// when it did, why not said when it could not (`failed` told then). Nothing with MBUI_READONLY=1.
fn act(
  src : Source,
  what : String,
  key : String,
  call : String,
  params : Json,
  done? : String = "",
  ok? : (Json) -> Unit = fn(_) {  },
  failed? : () -> Unit = fn() {  },
) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    failed()
    return
  }
  if key != "" {
    dui.doing[key] = true
    dui.failed.remove(key)
  }
  (src.call)(call, params, fn(res) {
    if key != "" {
      dui.doing.remove(key)
    }
    if key != "" && res is Err(_) {
      // its 6 s from the frame that first shows it (failed_lately)
      dui.failed[key] = failed_next()
    }
    match res {
      Ok(v) => {
        if done != "" {
          toast_later(done)
        }
        ok(v)
      }
      Err(e) => {
        let code = text(Some(e), "code")
        toast_later(
          fill(
            if code == "unconfirmed" {
              "android-misc.act.unconfirmed"
            } else {
              "android-misc.act.failed"
            },
            [("what", what), ("error", error_words(e))],
          ),
        )
        failed()
      }
    }
  })
}

///|
/// What went wrong, in words (errorText): the core's message, else its code.
fn error_words(e : Json) -> String {
  match text(Some(e), "message") {
    "" => text(Some(e), "code")
    m => m
  }
}

///|
/// Whether `key` is under way (AppState.isDoing).
fn doing(key : String) -> Bool {
  dui.doing.contains(key)
}

///|
/// How long what failed keeps its red mark (the core's doing keeps a failure 6 s).
let failed_ms : Double = 6000.0

///|
/// Whether `key` failed within the last 6 s (AppState.failedOf); a frame asked for when its mark is to go.
fn failed_lately(c : @ui.Ctx, key : String) -> Bool {
  match dui.failed.get(key) {
    // (its going is not what is shown waits for: a screenshot of it failing shows the mark)
    Some(n) if @kit.after(c, "failed/\{key}/\{n}", true, failed_ms, later=true) => {
      dui.failed.remove(key)
      false
    }
    Some(_) => true
    None => false
  }
}

///|
/// Each failure told its own number (dui.failed): the same key failing again is a new 6 s.
fn failed_next() -> Int {
  dui.failed_n += 1
  dui.failed_n
}

///|
fn seq_key(station : String, thread : Double, seq : Double) -> String {
  station + "\t" + thread.to_int64().to_string() + "\t" + seq.to_int64().to_string()
}

// ── what comes and goes under a post ────────────────────────────────────

///|
/// ListMotion.kt closeGap: the room left closed by the rows' spring (critically damped, 350), a little late (100 ms).
// kept across runs: a curve, never written
let close_gap : @motion.Spec = @motion.spring(stiffness=350.0, threshold=0.002, delay=100.0)

///|
/// The archive buttons' curve and time (Chat.kt ArchiveEase, 280 ms): a quick start, a soft landing.
// kept across runs: a curve, never written
let archive_tween : @motion.Spec = @motion.tween(280.0, ease=Soft)

///|
/// What `body` builds under a post, shown or not as `shown` says (Compose's AnimatedVisibility with expandVertically /
/// shrinkVertically from its top): coming by `enter` (None: there at once, EnterTransition.None) as its room opens by
/// `open`, going by `exit` as its room closes by `close`; turned back mid-way from where it is; the first time as it
/// is. Its room is laid out (`@motion.reveal`, as the Android app's shrinkVertically lays it out, so what is under it
/// in the chat closes up); what is in it is only drawn while it goes (a tap is what is under it's).
fn under_post(
  c : @ui.Ctx,
  key : String,
  shown : Bool,
  enter? : @motion.Trans,
  open? : @motion.Spec = archive_tween,
  exit~ : @motion.Trans,
  close? : @motion.Spec = archive_tween,
  body : () -> Unit,
) -> Unit {
  let to = if shown { 1.0 } else { 0.0 }
  let h = @motion.anim(c, "under/" + key, to, global=true)
  let look = match enter {
    Some(e) => @motion.presence(c, "under-look/" + key, shown, enter=e, exit=exit)
    None => {
      // there at once as it comes; going, by `exit`
      if shown {
        h.snap(1.0)
      }
      @motion.presence(c, "under-look/" + key, shown, enter=@motion.trans(spec=@motion.Snap(0.0)), exit=exit)
    }
  }
  h.follow(to, if shown { open } else { close })
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
/// left, its room closing), and with the options once the card is answered.
fn ask_dismiss(c : @ui.Ctx, src : Source, here : Here, m : Message) -> Unit {
  let answered = match m.decision {
    Some(d) => d.resolved || d.dismissed
    None => false
  }
  if !m.asked && !answered {
    return
  }
  let k = seq_key(here.station, m.thread, m.seq)
  let shown = m.asked && !answered && !dui.gone.contains(k)
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
    exit=@motion.trans(fade=0.0, scale=0.85, ox=0.0, oy=0.0, spec=archive_tween),
    fn() {
      c.box(pt=6.0, fn() {
        c.box(id=if shown { id } else { 0 }, fn() {
          c.text(tr("android-chat.asks.dismiss"), size=12.0, color=t.p.muted, line=18.0) |> ignore
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

///|
/// 保留 and 归档此对话 under the agents' latest all-done post while nothing is left in the chat (Chat.kt ArchiveUnder),
/// as buttons (Decisions.kt OptionButton), the second in the accent; each a spinner while it is done, neither while the
/// station is offline or the other is under way; 保留 that failed a moment ago marked so. Offered or taken, they come
/// and go (280 ms, ArchiveEase: fading, from or to 85% about their top's middle, their room opening or closing).
fn archive_under_post(c : @ui.Ctx, src : Source, here : Here, m : Message) -> Unit {
  if m.author_kind != "agent" || m.ending != "all_done" {
    return
  }
  let under = archive_under(here.view) == Some(m.seq)
  let shown = under && here.view.thread is Some(_)
  let enter = @motion.trans(fade=0.0, scale=0.85, ox=0.5, oy=0.0, spec=archive_tween)
  under_post(c, "archive/" + here.station + "/" + m.ts, shown, enter~, exit=enter, fn() {
    archive_buttons(c, src, here, shown)
  })
}

///|
/// The two buttons of archive_under_post; `enabled` while they are offered (going, they are drawn as they were, not
/// pressed).
fn archive_buttons(c : @ui.Ctx, src : Source, here : Here, enabled : Bool) -> Unit {
  let r : ChatRef = { station: here.station, session: here.session, title: "", station_name: "" }
  let thread = match here.view.thread {
    Some(th) => th
    None => return
  }
  let archiving = doing("archive/" + here.station + "/" + here.session)
  let kkey = "keep/" + here.station + "/" + thread.to_int64().to_string()
  let keeping = doing(kkey)
  c.box(dir=Row, w=Fill(1.0), pt=6.0, gap=6.0, fn() {
    if option_button(
        c,
        "archive-under/keep",
        tr("android-chat.chat.keep"),
        false,
        enabled && !here.view.offline && !archiving,
        keeping,
        failed=failed_lately(c, kkey),
      ) {
      act(
        src,
        tr("android-chat.chat.keep.verb"),
        kkey,
        "chat.keep",
        { "station": Json::string(here.station), "thread": Json::number(thread) },
        done=tr("android-chat.chat.kept"),
      )
    }
    if option_button(
        c,
        "archive-under/archive",
        tr("android-chat.chat.archiveThis"),
        true,
        enabled && !here.view.offline && !keeping,
        archiving,
      ) {
      archive_chat(src, r, here.view)
    }
  })
  |> ignore
}

///|
/// A button as wide as it is given (Decisions.kt OptionButton): the label in medium, white on the accent when
/// `strong`, ink on the chip otherwise; half there when not `enabled`; a spinner while `busy`, the red mark when it
/// `failed` a moment ago; pressed, its ground the ripple's (in 75 ms, out 150) and the whole drawn at 97% (80 ms in,
/// 180 out, Ease.Out). True on the frame after it was tapped (never while busy or not enabled).
fn option_button(
  c : @ui.Ctx,
  key : String,
  label : String,
  strong : Bool,
  enabled : Bool,
  busy : Bool,
  failed? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let ink = if strong { 0xFFFFFFFFL } else { t.p.text }
  let ground = if strong { t.p.accent } else { t.p.chip }
  let free = enabled && !busy
  let down = free && c.pressed(id)
  let scale = @motion.animate(
    c,
    key + "/press",
    if down { 0.97 } else { 1.0 },
    spec=@motion.tween(if down { 80.0 } else { 180.0 }, ease=Out),
  )
  let pressed = if free { @motion.pressing(c, id) } else { 0.0 }
  let b = c.box(
    dir=Row,
    w=Fill(1.0),
    padx=14.0,
    pady=10.0,
    gap=8.0,
    radius=12.0,
    align=ACenter,
    opacity=if enabled { 1.0 } else { 0.5 },
    bg=if pressed > 0.0 { @sf.over(ground, @sf.alpha(ink, 0.12 * pressed)) } else { ground },
    id~,
    fn() {
      c.box(w=Fill(1.0), fn() {
        c.text(label, size=15.0, weight=500, color=ink, line=21.0) |> ignore
      })
      |> ignore
      if busy {
        if strong {
          @sf.spinner(c, size=12.0, ring=@sf.alpha(ink, 0.3), arc=ink) |> ignore
        } else {
          @sf.spinner(c, size=12.0) |> ignore
        }
      } else if failed {
        @sf.icon(c, "info", size=14.0, color=t.p.red) |> ignore
      }
    },
  )
  if scale != 1.0 {
    c.look(b, @ui.look(scale~))
  }
  c.clicked(id) && free
}

// ── a login card's buttons (LoginCards.kt ActiveCard) ───────────────────

///|
/// A login under way, for one who may finish it (the station's `machineLogins` says `canLogin`): what to do now by its
/// step, then the step's own pill (filled) and 取消 (LoginCards.kt ActiveCard). The pill opens the login's page in the
/// system's browser (Ctx::open_url; LoginPages.open): a device code first copied (复制并打开), a loopback login's page
/// once the core listens for its callback (`machineLogin.open`, the browser's answer coming back to this device).
fn login_active(c : @ui.Ctx, src : Source, station : String, l : Json?, relay : Bool) -> Unit {
  let t = @sf.theme()
  let id = text(l, "id")
  let step = if flag(l, "waiting") { "" } else { text(l, "step") }
  let domain = match text(l, "domain") {
    "" => ""
    d => fill("web-main.logins.domain", [("domain", d)])
  }
  let said = fn(words : String, red : Bool, busy : Bool) {
    c.box(dir=Row, padx=10.0, gap=6.0, align=ACenter, fn() {
      if busy {
        @sf.spinner(c, size=12.0) |> ignore
      }
      c.text(words, size=13.0, color=if red { t.p.red } else { t.p.muted }, line=19.0) |> ignore
    })
    |> ignore
  }
  let code = text(l, "code")
  let url = match text(l, "codeUrl") {
    "" => text(l, "url")
    u => u
  }
  let mut main = ""
  let mut copy = ""
  let mut page = ""
  match step {
    "device" if code != "" => {
      said(fill("web-main.logins.device", [("domain", text(l, "domain"))]), false, false)
      // the code, large enough to read and copy by eye; pressed, it is copied (nothing opened), said so
      let code_id = c.id("login-code/" + id)
      if c.clicked(code_id) {
        c.copy_text(code)
        say(c, tr("web-main.logins.codeCopied"))
      }
      c.box(padx=10.0, pady=4.0, id=code_id, fn() {
        c.text(code, size=22.0, weight=600, color=t.p.text, wrap=false, line=29.0) |> ignore
      })
      |> ignore
      main = tr("web-main.logins.copyOpen")
      copy = code
      page = url
    }
    "loopback" if !relay => {
      said(tr("web-main.logins.needsDesktop"), false, false)
      if domain != "" {
        said(domain, false, false)
      }
    }
    "loopback" => {
      if flag(l, "listening") {
        said(tr("web-main.logins.waitingBrowser"), false, true)
      } else if text(l, "relayText") != "" {
        said(text(l, "relayText"), true, false)
      }
      if domain != "" && !flag(l, "listening") {
        said(domain, false, false)
      }
      main = tr(if flag(l, "listening") { "web-main.logins.openAgain" } else { "web-main.logins.signIn" })
      page = "\u{1}relay"
    }
    "open" if url != "" => {
      if domain != "" {
        said(domain, false, false)
      }
      main = tr("web-main.logins.signIn")
      page = url
    }
    _ => said(text(l, "statusText"), false, true)
  }
  let cancel_key = "login-cancel/" + station + "/" + id
  c.box(dir=Row, pt=6.0, gap=4.0, align=ACenter, fn() {
    if main != "" {
      let open_key = "login-open/" + station + "/" + id
      if login_pill(c, "login-main/" + id, main, true, doing(open_key)) {
        if copy != "" {
          c.copy_text(copy)
        }
        if page == "\u{1}relay" {
          // the core listens for the browser's callback first, then the page opens (LoginCards.kt relay); this
          // device's port taken is said on the card (relayText), nothing opened
          act(
            src,
            tr("web-main.logins.openWhat"),
            open_key,
            "machineLogin.open",
            { "station": Json::string(station), "id": Json::string(id), "here": Json::boolean(false) },
            ok=fn(v) {
              let u = text(Some(v), "url")
              if u != "" && !@ui.open_url(u) {
                toast_later(tr("android-misc.link.cantOpen"))
              }
            },
          )
        } else if page != "" && !c.open_url(page) {
          say(c, tr("android-misc.link.cantOpen"))
        }
      }
    }
    if login_pill(c, "login-cancel/" + id, tr("common.cancel"), false, doing(cancel_key)) {
      act(
        src,
        tr("web-main.logins.cancelWhat"),
        cancel_key,
        "machineLogin.cancel",
        { "station": Json::string(station), "id": Json::string(id) },
      )
    }
  })
  |> ignore
}

///|
/// One of a login card's buttons (LoginCards.kt Pill): 28 high, the accent's tint when `filled`, plain otherwise (a
/// ground only while pressed).
fn login_pill(c : @ui.Ctx, key : String, label : String, filled : Bool, busy : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let ink = if filled { t.p.accent_text } else { t.p.text }
  let ground = if filled { t.p.accent_bg } else { 0L }
  c.box(
    dir=Row,
    h=Px(28.0),
    padx=10.0,
    gap=6.0,
    radius=14.0,
    align=ACenter,
    opacity=if busy { 0.6 } else { 1.0 },
    bg=if c.pressed(id) && !busy { @sf.over(ground, @sf.alpha(ink, 0.12)) } else { ground },
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=12.0) |> ignore
      }
      c.text(label, size=14.0, weight=500, color=ink, wrap=false) |> ignore
    },
  )
  |> ignore
  c.clicked(id) && !busy
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
let sheet_fitted : @ui.Style = @ui.style(w=Full)

///|
/// A sheet from the bottom (Sheet.kt SheetHost, mbui's @kit.sheet): the scrim (black at 28%) closing it when tapped;
/// the sheet `tall` high (its share of the screen), or with `fit` as tall as what it shows (SheetSpec fit), at most
/// 90%; its top corners 26 round, frosted over the page and the scrim (@sf.sheet_look); it rises and sinks on the
/// sheet's spring, drawn only as it goes (a tap meanwhile is what is under it's). The decisions' sheets are one sheet:
/// one asked in place of another goes to its height.
fn sheet_frame(c : @ui.Ctx, key : String, tall : Double, body : () -> Unit, fit? : Bool = false) -> Unit {
  let leaving = dui.sheet is None
  // fitted: what it shows as laid out (the frame before); `tall`, its share, until that is known
  let fit_key = "sheet-fit/" + key
  let h = match (fit, @motion.measured(c, fit_key)) {
    (true, Some(m)) => m
    _ => tall
  }
  let r = @kit.sheet(
    c,
    "decide-sheet",
    !leaving,
    h=dmin(h, c.height * 0.9),
    scrim=@sf.sheet_scrim,
    look=@sf.sheet_look(),
    fn() {
      if fit {
        // laid out at what it needs, kept for the next frame's height
        let shown = c.box(style=sheet_fitted, fn() {
          sheet_grab(c)
          body()
        })
        @motion.measure(c, shown, fit_key)
      } else {
        // its share: what it shows may fill it (a list scrolling in it)
        sheet_grab(c)
        body()
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
/// The sheet's grabber (Sheet.kt SheetGrab): 38 × 5 in the line's colour, 16 above it and 8 under.
fn sheet_grab(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pt=12.0, pb=8.0, align=ACenter, fn() {
    c.box(w=Px(38.0), h=Px(5.0), radius=3.0, bg=t.p.line, fn() {  }) |> ignore
  })
  |> ignore
}

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
  }
}
