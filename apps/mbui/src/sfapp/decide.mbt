// What a chat's cards and buttons do (slice 8: ember apps/android chat/screens/Decisions.kt DecisionUnder, OptionButton;
// Chat.kt AskDismiss, ArchiveUnder, archiveChat; LoginCards.kt; AppState.kt act, isDoing); a sheet's head (SheetHead). The
// chat's sheets (sheets.mbt) are the library's presenters'. What is done is said to
// the core as the Android app says it, under way on its button (a spinner), said in a toast when it could not be;
// nothing with MBUI_READONLY=1.

///|
/// What this slice keeps while the app runs.
priv struct Decide {
  /// asks let go here, before the core says so (Chat.kt AskDismiss `gone`), by station, thread and post
  gone : Map[String, Bool]
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
  jobs_all: false,
  letters_open: "",
  letters_held: {},
  job_tab: 0,
  history_tab: 0,
  opened: {},
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
  deck_anims.clear()
  dui.gone.clear()
  dui.jobs_all = false
  dui.letters_open = ""
  dui.letters_held.clear()
  dui.job_tab = 0
  dui.history_tab = 0
  dui.opened.clear()
  history_placed.clear()
  history_short.clear()
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

// ── what comes and goes under a post ────────────────────────────────────

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
/// The chat into the archive (Chat.kt archiveChat; its bar's 归档, the one under its last 做完了, its sheet's): Home at
/// once, the chat gone from the list (the core's), said at once by its title, or why not.
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
    done=@sf.t("web-main.chat.archivedNamed", args=[("title", v.title)]),
    done_action=tr("android-chat.archived.undo"),
    done_run=@sfbase.archive_undo(src, p),
    at_once=true,
  )
}

// ── a sheet's head ──────────────────────────────────────────────────────

///|
/// A sheet's head (Sheet.kt SheetHead): its title, 17 bold.
fn sheet_head(c : @ui.Ctx, title : String) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), pl=18.0, pr=18.0, pt=4.0, pb=10.0, align=ACenter, fn() {
    c.text(title, size=t.t.title, weight=700, color=t.p.text, wrap=false) |> ignore
  })
  |> ignore
}

