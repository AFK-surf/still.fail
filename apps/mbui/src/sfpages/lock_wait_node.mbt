// The page of a device not yet confirmed in the workspace's safe mode (lock_wait.mbt's head) as nodes of the window's
// tree, made once: the library's waiting page, then the steps as the lock's `me.pair` says them, each part bound to
// what it shows; the code typed into the code field's boxes (@ui.code_field_node), sent as it is complete, emptied
// for the next try where it is refused.

///|
/// The page in `parent` (lock_wait_page's): the shield, 等待批准, what it waits for, then the steps
/// (pair_steps_node). The node.
pub fn lock_wait_node(parent : @view.View, core : Core, here : @settings.Here) -> @view.View {
  @sf.waiting_page_node(
    parent,
    "shield-check",
    fn() { @sf.t("web-pages.security.waitingTitle") },
    fn() { @sf.t("web-pages.security.waitingLead", args=[("name", here.name)]) },
    fn(col) { pair_steps_node(col, core, here.workspace) },
  )
}

///|
/// Which of the steps shows (pair_steps' branches): the code typed, one being found, or what is so and the request.
priv enum PairShows {
  Typing
  Finding
  Asked
} derive(Eq)

///|
/// The steps in `col` (pair_steps' as nodes, on the waiting page): typing, 输入… over the six boxes, then 正在核对
/// (turning), or how many tries are left in red, until when the code holds and 重新获取安全码; finding one, turning,
/// 没收到，重新申请 under it while nothing is asked; else what is so, 发送批准请求 under it.
fn pair_steps_node(col : @view.View, core : Core, ws : String) -> Unit {
  let pair = fn() { field(field((core.topic)("lock", { "workspace": Json::string(ws) }).get().value, "me"), "pair") }
  let me = fn() { field((core.topic)("lock", { "workspace": Json::string(ws) }).get().value, "me") }
  let state = fn() { text(pair(), "state") }
  let on = [("workspace", ws)]
  let asking = fn() { @settings.is_doing(core, ["lock.pair"], on) }
  let checking = fn() { @settings.is_doing(core, ["lock.pairCode"], on) || state() == "checking" }
  let shows = fn() {
    match state() {
      "code" | "wrong" | "checking" => Typing
      "finding" => Finding
      _ if asking() => Finding
      _ => Asked
    }
  }
  // (what is typed, kept while the page shows: emptied as a code is refused or a new one asked for)
  let typed = @ui.Field::new()
  col.pick(shows, fn(v, shown) {
    lock_steps_node(v)
    match shown {
      Typing => {
        lock_note_node(v, fn() { @sf.t("web-pages.security.pairEnter") })
        @ui.code_field_node(
          v,
          typed,
          fn(code) {
            (core.call)("lock.pairCode", { "workspace": Json::string(ws), "code": Json::string(code) }, fn(r) {
              if r is Err(_) {
                typed.set("")
              }
            })
          },
          label=@signals.untracked(fn() { @sf.t("web-pages.security.pairEnter") }),
          wrong=fn() { state() == "wrong" },
          enabled=fn() { !checking() },
          inks=fn() {
            let th = @ui.tree_theme()
            { digits: th.color(Fg), off: th.color(Muted), edge: th.color(@sf.code_edge), next: th.color(Fg), wrong: th.color(Danger) }
          },
        )
        |> ignore
        v.show(checking, fn(n) { lock_note_node(n, fn() { @sf.t("web-pages.security.pairChecking") }, turning=true) })
        v.show(fn() { !checking() }, fn(n) {
          lock_steps_node(n)
          // (what the core says of it, the device showing the code maybe gone; a core of before says nothing)
          n.show(fn() { state() == "wrong" }, fn(w) {
            @sf.words_node(w, fn() {
              match text(pair(), "error") {
                "" => @sf.t("web-pages.security.pairWrong", args=[("n", count(pair(), "left").to_string())])
                words => words
              }
            }, fn() { lock_failed })
            |> ignore
          })
          // (how long the code holds, and a new one asked for at any time: the code gone or not read in time)
          n.show(fn() { text(pair(), "untilText") != "" }, fn(u) { lock_note_node(u, fn() { text(pair(), "untilText") }) })
          lock_actions_node(n, fn(a) {
            @sf.button_node(a, fn() { @sf.t("web-pages.security.pairAgain") }, fn() {
              typed.set("")
              @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.pairAgain"), [])
            }, tone=Ghost)
            |> ignore
          })
        })
      }
      Finding => {
        lock_note_node(v, fn() { @sf.t("web-pages.security.pairFinding") }, turning=true)
        // asked again while it looks: the person opened a trusted device and nothing came up (2026-11-06 the user:
        // 「直接加个没收到重新申请的按钮」)
        v.show(fn() { !asking() }, fn(n) {
          lock_actions_node(n, fn(a) {
            @sf.button_node(a, fn() { @sf.t("web-pages.security.pairRetry") }, fn() {
              @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.pairRetry"), [])
            }, tone=Ghost)
            |> ignore
          })
        })
      }
      Asked => {
        v.show(fn() { state() == "failed" }, fn(n) {
          @sf.words_node(n, fn() { text(pair(), "error") }, fn() { lock_failed }) |> ignore
        })
        v.show(fn() { state() != "failed" }, fn(n) {
          lock_note_node(n, fn() {
            match state() {
              "none" => @sf.t("web-pages.security.pairNone")
              _ => @sf.t(if flag(me(), "unsigned") { "web-pages.security.upgradeNotAsked" } else { "web-pages.security.notAsked" })
            }
          })
        })
        lock_actions_node(v, fn(a) {
          @sf.button_node(a, fn() { @sf.t("web-pages.security.request") }, fn() {
            @settings.lock_call(core, ws, "pair", @sf.t("web-pages.security.request"), [])
          }, tone=Primary)
          |> ignore
        })
      }
    }
  })
}

///|
/// What holds some of the steps (`v`): as the page's column lays them out, 14 apart, each as wide as it is, in the
/// middle (wait_column's).
fn lock_steps_node(v : @view.View) -> Unit {
  @sf.style_node(v, fn() { lock_steps })
}

///|
// kept across runs: a value (no field of it changes)
let lock_steps : @ui.Style = @ui.css("w=Full gap=S3_5 align=ACenter")

///|
/// What is so (lock_note's): `words()`, a turning ring before it where `turning`.
fn lock_note_node(parent : @view.View, words : () -> String, turning? : Bool = false) -> Unit {
  parent.box(fn(row) {
    @sf.style_node(row, fn() { lock_note })
    if turning {
      @sf.spinner_node(row, size=lock_spin) |> ignore
    }
    @sf.words_node(row, words, fn() { lock_note_words }) |> ignore
  })
  |> ignore
}

///|
/// The actions' row (lock_actions'), what `make` puts in it.
fn lock_actions_node(parent : @view.View, make : (@view.View) -> Unit) -> Unit {
  parent.box(fn(row) {
    @sf.style_node(row, fn() { lock_actions })
    make(row)
  })
  |> ignore
}
