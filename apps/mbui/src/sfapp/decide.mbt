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
  /// the sheet open, since when; the one going, since when
  mut sheet : Sheet?
  mut sheet_at : Double
  mut leaving : Sheet?
  mut leave_at : Double
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
  /// the front decision: its key, how far across it is dragged, whether a finger has it and from where
  mut front : String
  mut drag : Double
  mut held : Bool
  mut swiping : Bool
  mut from_x : Double
  mut from_y : Double
  mut base : Double
  /// where the pointer was the last two frames (the fling's speed)
  mut last_x : Double
  mut last_t : Double
  mut speed : Double
  /// the front one going: 1 right (不再提醒), -1 left (待定), 2 up (answered), 0 not; since when; what then
  mut going : Int
  mut going_at : Double
  mut going_from : Double
  mut after_go : () -> Unit
  /// the front one coming in, since when (-1: there at once)
  mut arrive_at : Double
}

///|
let dui : Decide = {
  doing: {},
  gone: {},
  sheet: None,
  sheet_at: 0.0,
  leaving: None,
  leave_at: 0.0,
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
  from_x: 0.0,
  from_y: 0.0,
  base: 0.0,
  last_x: 0.0,
  last_t: 0.0,
  speed: 0.0,
  going: 0,
  going_at: 0.0,
  going_from: 0.0,
  after_go: fn() {  },
  arrive_at: -1.0,
}

///|
/// As at the start (tests).
fn decide_reset() -> Unit {
  dui.doing.clear()
  dui.gone.clear()
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
  dui.arrive_at = -1.0
}

///|
/// Says `words` in the toast from the next frame on (from a call's answer, between frames).
fn toast_later(words : String) -> Unit {
  app.toast = words
  app.toast_at = -1.0
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
  }
  (src.call)(call, params, fn(res) {
    if key != "" {
      dui.doing.remove(key)
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
fn seq_key(station : String, thread : Double, seq : Double) -> String {
  station + "\t" + thread.to_int64().to_string() + "\t" + seq.to_int64().to_string()
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
/// failed (`decision.dismiss`).
fn ask_dismiss(c : @ui.Ctx, src : Source, here : Here, m : Message) -> Unit {
  let k = seq_key(here.station, m.thread, m.seq)
  if !m.asked || dui.gone.contains(k) {
    return
  }
  let t = @sf.theme()
  let id = c.id("ask-dismiss/" + m.ts)
  if c.clicked(id) {
    dui.gone[k] = true
    c.request_frame()
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
  c.box(pt=6.0, fn() {
    c.box(id~, fn() {
      c.text(tr("android-chat.asks.dismiss"), size=12.0, color=t.p.muted, line=18.0) |> ignore
    })
    |> ignore
  })
  |> ignore
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
/// station is offline or the other is under way.
fn archive_buttons(c : @ui.Ctx, src : Source, here : Here) -> Unit {
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
        !here.view.offline && !archiving,
        keeping,
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
        !here.view.offline && !keeping,
        archiving,
      ) {
      archive_chat(src, r, here.view)
    }
  })
  |> ignore
}

///|
/// A button as wide as it is given (Decisions.kt OptionButton): the label in medium, white on the accent when
/// `strong`, ink on the chip otherwise; half there when not `enabled`; a spinner while `busy`. True on the frame after
/// it was tapped (never while busy or not enabled).
fn option_button(
  c : @ui.Ctx,
  key : String,
  label : String,
  strong : Bool,
  enabled : Bool,
  busy : Bool,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let ink = if strong { 0xFFFFFFFFL } else { t.p.text }
  let ground = if strong { t.p.accent } else { t.p.chip }
  c.box(
    dir=Row,
    w=Fill(1.0),
    padx=14.0,
    pady=10.0,
    gap=8.0,
    radius=12.0,
    align=ACenter,
    opacity=if enabled { 1.0 } else { 0.5 },
    bg=if c.pressed(id) && enabled && !busy { @sf.over(ground, @sf.alpha(ink, 0.12)) } else { ground },
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
      }
    },
  )
  |> ignore
  c.clicked(id) && enabled && !busy
}

// ── a login card's buttons (LoginCards.kt ActiveCard) ───────────────────

///|
/// A login under way, for one who may finish it (the station's `machineLogins` says `canLogin`): what to do now by its
/// step, then the step's own pill (filled) and 取消. The page itself is not opened here: there is no browser hand-off
/// in the app yet, so its link (or the code) goes on the clipboard, said in a toast.
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
  match step {
    "device" if code != "" => {
      said(fill("web-main.logins.device", [("domain", text(l, "domain"))]), false, false)
      c.box(padx=10.0, pady=4.0, fn() {
        c.text(code, size=22.0, weight=600, color=t.p.text, wrap=false, line=29.0) |> ignore
      })
      |> ignore
      main = tr("web-main.logins.copyOpen")
      copy = code
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
      copy = url
    }
    "open" if url != "" => {
      if domain != "" {
        said(domain, false, false)
      }
      main = tr("web-main.logins.signIn")
      copy = url
    }
    _ => said(text(l, "statusText"), false, true)
  }
  let cancel_key = "login-cancel/" + station + "/" + id
  c.box(dir=Row, pt=6.0, gap=4.0, align=ACenter, fn() {
    if main != "" {
      if login_pill(c, "login-main/" + id, main, true, false) {
        c.copy_text(copy)
        say(c, tr("web-main.logins.codeCopied"))
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
  dui.sheet_at = c.now()
  dui.leaving = None
  c.blur()
  c.request_frame()
}

///|
/// Closes the sheet open, which goes down.
fn close_sheet(c : @ui.Ctx) -> Unit {
  match dui.sheet {
    Some(s) => {
      dui.leaving = Some(s)
      dui.leave_at = c.now()
    }
    None => ()
  }
  dui.sheet = None
  c.request_frame()
}

///|
/// A sheet from the bottom (Sheet.kt SheetHost, mbui's @kit.sheet): the scrim (black at 28%) closing it when tapped;
/// the sheet `tall` high (its share of the screen, or as tall as what it shows, at most 90%), its top corners 26
/// round, frosted over the page and the scrim (@sf.sheet_look); it rises and sinks on the sheet's spring, drawn only
/// as it goes (a tap meanwhile is what is under it's). The decisions' sheets are one sheet: one asked in place of
/// another goes to its height.
fn sheet_frame(c : @ui.Ctx, key : String, tall : Double, body : () -> Unit) -> Unit {
  ignore(key)
  let leaving = dui.sheet is None
  let r = @kit.sheet(
    c,
    "decide-sheet",
    !leaving,
    h=dmin(tall, c.height * 0.9),
    scrim=@sf.sheet_scrim,
    look=@sf.sheet_look(),
    fn() {
      sheet_grab(c)
      body()
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
