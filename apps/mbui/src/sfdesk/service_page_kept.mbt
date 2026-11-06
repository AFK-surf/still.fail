// A service page can be shared by a page on the navigation stack and a chat's side tab. The core answers tab changes
// asynchronously, so a page must stay alive during the handoff as well as while a tab or its exit animation holds it.

///|
priv struct ServiceTabChange {
  id : Int
  opening : Bool
  was_open : Bool
  // 0: waiting, 1: succeeded, 2: failed
  mut result : Int
  // An open can reach prefs before the chat's filtered tab view catches up.
  mut observed : Bool
}

///|
priv struct ServiceTabChanges {
  chat : ChatRef
  tab : String
  job : String
  changes : Array[ServiceTabChange]
}

///|
// kept across runs: put back by service_ownership_reset (sv_reset)
let service_tab_changes : Map[String, ServiceTabChanges] = Map([])

///|
// kept across runs: a late reply from before a reset must not answer a later request
let service_tab_change_id : Ref[Int] = Ref(0)

///|
// One detached effect follows the core's tab preferences while a handoff or a release is outstanding. It is stopped
// when both are settled, including on reset; it is not owned by the page that may be about to leave.
// kept across runs: stopped and put back by service_ownership_reset (sv_reset)
let service_ownership_stop : Ref[(() -> Unit)?] = Ref(None)

///|
// kept across runs: put back by service_ownership_reset (sv_reset)
let service_ownership_rechecking : Ref[Bool] = Ref(false)

///|
fn service_ownership_idle() -> Unit {
  if service_tab_changes.is_empty() && sv_closing.is_empty() {
    match service_ownership_stop.val {
      Some(stop) => {
        service_ownership_stop.val = None
        stop()
      }
      None => ()
    }
  }
}

///|
fn service_ownership_watch(src : Source) -> Unit {
  if service_ownership_stop.val is Some(_) { return }
  let old_sub = @signals.set_active_sub(None)
  let old_owner = @signals.set_owner(None)
  let started = Ref(false)
  let stop = @signals.effect(fn() {
    (src.topic)("prefs", {}).value |> ignore
    // The active stack's chat topics can change after prefs (or filter a service when its job disappears). Background
    // stacks have left their chat subscriptions; do not reopen them just to check ownership.
    for page in app.nav.pages() {
      match page {
        Chat(r) => @sfbase.chat_view_now(src, r) |> ignore
        _ => ()
      }
    }
    if started.val {
      @signals.after_flush(fn() { service_ownership_reconcile(src) })
    }
  })
  @signals.set_owner(old_owner) |> ignore
  @signals.set_active_sub(old_sub) |> ignore
  service_ownership_stop.val = Some(stop)
  started.val = true
  service_ownership_reconcile(src)
}

///|
// A reply and the prefs topic need not arrive together. Once both agree, forget the intent, then recheck every pending
// release against the current owners. Revalidation in service_release_pending makes a later reopen win.
fn service_ownership_reconcile(src : Source) -> Unit {
  if service_ownership_rechecking.val { return }
  service_ownership_rechecking.val = true
  @signals.untracked(fn() {
    let prefs = (src.topic)("prefs", {}).value
    let forget : Array[String] = []
    for key, changes in service_tab_changes {
      if !service_tab_waits(changes) {
        match service_tab_last(changes) {
          None => forget.push(key)
          Some(last) =>
            match prefs {
              Some(Object(_)) => {
                let saved = field(field(prefs, "chatTabs"), tabs_key(changes.chat))
                let tabs = items(saved, "tabs")
                let present = tabs.iter().any(fn(value) {
                  match value { String(tab) => tab == changes.tab; _ => false }
                })
                if present == last.opening {
                  last.observed = true
                  // A file is never filtered by agents. For a service, keep the successful open until the chat view
                  // has adopted it or has established that the job is not one of its agents' jobs.
                  let adopted = !last.opening || tab_file(changes.tab) is Some(_) ||
                    !service_chat_live(src, changes.chat) ||
                    (match @sfbase.chat_kept(changes.chat) {
                      Some(v) => side_of(v).0.contains(changes.tab) || service_job_filtered(src, changes.chat, changes.tab)
                      None => true
                    })
                  if adopted { forget.push(key) }
                } else if last.opening && last.observed {
                  // The open was observed and then removed by a later change, before the filtered topic caught up.
                  forget.push(key)
                }
              }
              _ => ()
            }
        }
      }
    }
    for key in forget { service_tab_changes.remove(key) }
    let check : Array[(String, String)] = []
    for _, waiting in sv_closing { check.push((waiting.station, waiting.job)) }
    for (station, job) in check { service_release_pending(src, station, job) }
  })
  service_ownership_rechecking.val = false
  service_ownership_idle()
}

///|
fn service_ownership_reset() -> Unit {
  match service_ownership_stop.val {
    Some(stop) => stop()
    None => ()
  }
  service_ownership_stop.val = None
  service_ownership_rechecking.val = false
  service_tab_changes.clear()
}

///|
fn service_tab_change_key(r : ChatRef, tab : String) -> String {
  tabs_key(r) + "\u{1}" + tab
}

///|
fn service_tab_last(changes : ServiceTabChanges) -> ServiceTabChange? {
  let mut last = None
  for change in changes.changes {
    if change.result != 2 {
      last = Some(change)
    }
  }
  last
}

///|
fn service_tab_waits(changes : ServiceTabChanges) -> Bool {
  changes.changes.iter().any(fn(change) { change.result == 0 })
}

///|
// Called before changing the panel or asking the core, including for an open that has not appeared in its topic yet.
fn service_tab_asking(src : Source, r : ChatRef, tab : String, opening : Bool, was_open? : Bool = false) -> Int? {
  guard tab_job(tab) is Some(job) else { return None }
  let key = service_tab_change_key(r, tab)
  let changes = match service_tab_changes.get(key) {
    Some(changes) => changes
    None => {
      let changes : ServiceTabChanges = { chat: r, tab, job, changes: [] }
      service_tab_changes[key] = changes
      changes
    }
  }
  service_tab_change_id.val += 1
  let id = service_tab_change_id.val
  changes.changes.push({ id, opening, was_open, result: 0, observed: false })
  service_ownership_watch(src)
  Some(id)
}

///|
// The tabs a clear must close include ones whose open has not yet appeared in the core's topic.
fn service_tabs_pending(r : ChatRef) -> Array[String] {
  let tabs = []
  for _, changes in service_tab_changes {
    if tabs_key(changes.chat) == tabs_key(r) && !tabs.contains(changes.tab) {
      tabs.push(changes.tab)
    }
  }
  tabs
}

///|
fn service_tab_visible(chat : String, tab : String) -> Bool {
  match service_tab_changes.get(chat + "\u{1}" + tab) {
    Some(changes) if !service_tab_waits(changes) =>
      match service_tab_last(changes) {
        Some(last) if last.result == 1 && !last.opening => false
        _ => true
      }
    _ => true
  }
}

///|
// Answer after the core has received the request. A successful open is a tab's ownership even if its topic has not
// caught up; a failed open is eligible for release, after all other owners have been checked.
fn service_tab_answered(src : Source, r : ChatRef, tab : String, id : Int, ok : Bool) -> Unit {
  let key = service_tab_change_key(r, tab)
  guard service_tab_changes.get(key) is Some(changes) else { return }
  guard changes.changes.iter().find_first(fn(change) { change.id == id }) is Some(change) else { return }
  change.result = if ok { 1 } else { 2 }
  if !ok && !change.opening && !service_tab_waits(changes) {
    match service_tab_last(changes) {
      Some(last) if last.opening => service_close_failed(r, tab)
      None if change.was_open => service_close_failed(r, tab)
      _ => ()
    }
  }
  if !service_tab_waits(changes) && service_tab_last(changes) is None {
    service_tab_changes.remove(key)
  }
  if !ok && change.opening {
    service_page_drop(src, r.station, changes.job)
  }
  service_ownership_reconcile(src)
}

///|
// Only navigation stacks retained in this run are owners. prefs.chatTabs also includes historical chats and is not a
// list of live pages.
fn service_live_stacks(src : Source) -> Array[Array[Page]] {
  let stacks : Array[Array[Page]] = [app.nav.pages()]
  let active = match @sfbase.workspace_in_view(src).0 {
    Some(w) => tab_kept_key(w.id, tab_of_place(lit_place()))
    None => ""
  }
  // The system's other tabs retain their navigation stacks. The selected tab's saved stack is only an old snapshot;
  // its live stack above is authoritative.
  for name, pages in tabs_kept {
    if name != active && !name.has_suffix(" ") { stacks.push(pages) }
  }
  stacks
}

///|
fn service_chat_live(src : Source, r : ChatRef) -> Bool {
  for pages in service_live_stacks(src) {
    for page in pages {
      match page {
        Chat(other) if tabs_key(other) == tabs_key(r) => return true
        _ => ()
      }
    }
  }
  false
}

///|
// The core's tabsOf filters service tabs when agents are known. Used only to settle an open whose prefs have arrived
// but whose filtered chat view has not yet shown the tab. Do not resubscribe a background chat that has been left.
fn service_job_filtered(src : Source, r : ChatRef, tab : String) -> Bool {
  guard app.nav.pages().iter().any(fn(p) { match p { Chat(other) => tabs_key(other) == tabs_key(r); _ => false } }) else {
    return false
  }
  guard tab_service(tab) is Some(job) else { return false }
  let chat = (src.topic)("chat", @sfbase.chat_params(r)).value
  let agents = items(chat, "agents")
  if agents.is_empty() { return false }
  !agents.iter().any(fn(a) { items(Some(a), "jobs").iter().any(fn(j) { text(Some(j), "id") == job }) })
}

///|
/// Whether a page is still held by a navigation page, a tab, an in-flight tab change, or a tab's exiting node. A
/// closing tab may be excluded from its own release check; another tab for the same page remains an owner.
pub fn service_page_kept(
  src : Source,
  station : String,
  job : String,
  excluding? : (ChatRef, String)? = None,
) -> Bool {
  let key = service_key(station, job)
  if sv_nodes.contains(key) || sv_drawn.contains(key) {
    return true
  }
  let prefs = (src.topic)("prefs", {}).value
  let prefs_ready = prefs is Some(Object(_))
  let stacks = service_live_stacks(src)
  for pages in stacks {
    for page in pages {
      match page {
        Service(s, j) if s == station && j == job => return true
        PreviewFile(s, session, path, _) if s == station && "file:" + session + "\n" + path == job => return true
        Chat(r) if r.station == station => {
          // Either topic can arrive first. Include the live chat's view while it catches up to prefs; an acknowledged
          // close is suppressed by service_tab_visible (or by the closing tab's exclusion) until the old view changes.
          let tabs = if prefs_ready {
            items(field(field(prefs, "chatTabs"), tabs_key(r)), "tabs").filter_map(fn(value) {
              match value { String(tab) => Some(tab); _ => None }
            })
          } else {
            []
          }
          match @sfbase.chat_kept(r) {
            Some(v) => for tab in side_of(v).0 {
              if !tabs.contains(tab) { tabs.push(tab) }
            }
            None => ()
          }
          for tab in tabs {
            let excepted = match excluding {
              Some((other, omitted)) => tabs_key(r) == tabs_key(other) && tab == omitted
              None => false
            }
            let allowed = match (tab_service(tab), @sfbase.chat_kept(r)) {
              (Some(_), Some(v)) => side_of(v).0.contains(tab)
              _ => true
            }
            if !excepted && allowed && service_tab_visible(tabs_key(r), tab) && tab_job(tab) == Some(job) {
              return true
            }
          }
        }
        _ => ()
      }
    }
  }
  for _, changes in service_tab_changes {
    if changes.chat.station == station && changes.job == job {
      if service_tab_waits(changes) {
        return true
      }
      match service_tab_last(changes) {
        Some(last) if last.result == 1 && last.opening => return true
        _ => ()
      }
    }
  }
  false
}
