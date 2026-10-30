// What a chat's cards and buttons do (slice 8: ember apps/android chat/screens/Decisions.kt DecisionUnder, OptionButton;
// Chat.kt AskDismiss, ArchiveUnder, archiveChat; LoginCards.kt; AppState.kt act, isDoing); a sheet's head (SheetHead). The
// chat's sheets (sheets.mbt) are the library's presenters'. What is done is said to
// the core as the Android app says it, under way on its button (a spinner), said in a toast when it could not be;
// nothing with MBUI_READONLY=1.

///|
/// What this slice keeps while the app runs.
priv struct Decide {
  /// asks let go here, before the core says so (Chat.kt AskDismiss `gone`), by station, thread and post
  gone : @sf.LiveMap[String, Bool]
  /// the jobs' sheet shows all of them, not only those that matter now
  jobs_all : @signals.Signal[Bool]
  /// the letters' sheet: the chat opened in it, by its key ("" the list of them)
  letters_open : @signals.Signal[String]
  /// the chats whose letters were read for their sheet (the core's `chatLetters`), by station and session: their
  /// threads, let go as the chat is (chat.mbt chat_left)
  letters_held : @sf.LiveMap[String, Double]
  /// a job's sheet: what it said (0) or its output (1)
  job_tab : @signals.Signal[Int]
  /// the history's tab: its steps (0) or its details (1)
  history_tab : @signals.Signal[Int]
  /// groups and steps of a history opened, by their key
  opened : @sf.LiveMap[String, Bool]
}

///|
let dui : Decide = {
  gone: @sf.LiveMap::new(),
  jobs_all: @signals.signal(false, same=fn(a, b) { a == b }),
  letters_open: @signals.signal("", same=fn(a, b) { a == b }),
  letters_held: @sf.LiveMap::new(),
  job_tab: @signals.signal(0, same=fn(a, b) { a == b }),
  history_tab: @signals.signal(0, same=fn(a, b) { a == b }),
  opened: @sf.LiveMap::new(),
}

///|
/// As at the start (tests).
fn decide_reset() -> Unit {
  dui.gone.clear()
  dui.jobs_all.set(false)
  dui.letters_open.set("")
  dui.letters_held.clear()
  dui.job_tab.set(0)
  dui.history_tab.set(0)
  dui.opened.clear()
  history_placed.clear()
  history_short.clear()
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

