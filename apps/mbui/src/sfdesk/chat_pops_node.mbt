// What a chat's bar on 中屏 and 大屏 opens under it where the chat's page is made as nodes (sfbase's chat_page_nodes on;
// off, the old page's bar_popovers draws them, chat_page.mbt), presented by the
// library's presenters as the signals its buttons set say so (chat_own's `info_open`, `jobs_open`): its info
// (chat_info_node) and its services (jobs_pop_node), each a panel of nodes beside its button in the bar, or beside the
// mark of the system's bars where it was chosen there and the bar has no buttons of its own (rail_native.mbt). Each is
// presented as its signal comes to say open where what it opens beside is made, closed as it comes to say closed, and
// says closed as the panel closes for anything else (Escape, a press outside, what was chosen in it, all that is
// presented closed); what it opens beside let go (another chat's bar in its place, the bar of another screen as the
// window comes to one), the panel closes with it, its signal as it was: the one made in its place opens it there.

///|
/// What the chat's info and its services' popover were presented as (their serials, 0 none: @sf.last_presented).
priv struct ChatPops {
  mut info : Int
  mut jobs : Int
  /// told as what one of them opened beside is let go with it open: the one made in its place presents it
  left : @signals.Signal[Int]
}

///|
// kept across runs: put back by chat_page_reset
let chat_pops : ChatPops = { info: 0, jobs: 0, left: @signals.signal(0) }

///|
/// What the bar of chat `r` presents (wide_bar_of's, in `b`), its view as it is read (`view`), its pictures asked for on
/// the page's time (`stint`): where the system's bars have its buttons, its info and its services beside their mark;
/// the window turned beside them, both closed (what they opened from is elsewhere: rail_native.mbt).
fn chat_pops_node(b : @view.View, src : Source, r : ChatRef, view : () -> ChatView?, stint : () -> Int) -> Unit {
  b.show(fn() { view() is Some(_) && @sf.native_on() }, fn(n) {
    chat_info_pop_node(n, src, r, view, stint, None)
    chat_jobs_pop_node(n, src, r, None)
  })
  b.reacts(
    fn() { b.window().0 },
    fn(_) {
      if @sf.native_on() {
        chat_own.info_open.set(false)
        chat_own.jobs_open.set(false)
      }
    },
    at_start=false,
  )
}

///|
/// The chat's info presented from `host` (its button in the bar, `own`; None: the mark of the system's bars), as
/// `info_open` says.
fn chat_info_pop_node(host : @view.View, src : Source, r : ChatRef, view : () -> ChatView?, stint : () -> Int, own : @view.View?) -> Unit {
  chat_pop_node(
    host,
    chat_own.info_open,
    own,
    chat_info_w,
    fn() { chat_pops.info },
    fn(s) { chat_pops.info = s },
    fn(v) { chat_info_node(v, src, r, view, stint, fn() { chat_own.info_open.set(false) }) },
  )
}

///|
/// The chat's services' popover presented from `host` (its button in the bar, `own`; None: the mark of the system's
/// bars), as `jobs_open` says: a service or a job chosen opens 任务 beside the chat, at it.
fn chat_jobs_pop_node(host : @view.View, src : Source, r : ChatRef, own : @view.View?) -> Unit {
  let open = fn(id : String) {
    chat_own.jobs_open.set(false)
    if id != "" {
      pick_job(id)
    }
    side_change(src, r, "open", Some("jobs"))
  }
  chat_pop_node(host, chat_own.jobs_open, own, jobs_pop_w, fn() { chat_pops.jobs }, fn(s) { chat_pops.jobs = s }, fn(v) {
    // (a service's own tab is not here yet: it opens in 任务 too)
    jobs_pop_node(v, src, r.station, fn() { src.topic("chatJobs", chat_params(r)).get().value }, open, open)
  })
}

///|
/// One of the bar's popovers presented from `host` as `open` comes to say so: a panel of nodes `w` wide holding `body`,
/// beside `own` (the bar's button) under it, its end at the button's, or the system's bars' mark (bar_anchor_node's); none
/// of it where there is nothing to stand beside (the old view's popover beside nothing). Presented as `was`, said by
/// `keep`; `open` set closed as it closes unsaid (gone) or for anything else; `host` let go, the panel closed with it.
fn chat_pop_node(
  host : @view.View,
  open : @signals.Signal[Bool],
  own : @view.View?,
  w : Double,
  was : () -> Int,
  keep : (Int) -> Unit,
  body : (@view.View) -> Unit,
) -> Unit {
  let gone = Ref(false)
  let mine = Ref(0)
  host.reacts(fn() { (open.get(), chat_pops.left.get()) }, fn(said) {
    let (on, _) = said
    if !on {
      if was() != 0 {
        @sf.close_presented_of(was())
      }
      return
    }
    guard !@sf.presented_open_of(was()) else { return }
    guard bar_anchor_node(own, Bottom, End) is Some((from, side, along)) else { return }
    @sf.panel_nodes("", fn(v, _) { body(v) }, from~, w~, side~, along~, gone=fn() { open.set(false) })
    mine.val = @sf.last_presented()
    keep(mine.val)
  })
  // (closed by anything else (all that is presented closed, another page on top): said closed then)
  host.reacts(
    fn() { @sf.presented_open_now(was()) },
    fn(shown) {
      if !shown && !gone.val {
        open.set(false)
      }
    },
    at_start=false,
  )
  host.owns(fn() {
    gone.val = true
    if mine.val != 0 && @sf.presented_open_of(mine.val) {
      @sf.close_presented_of(mine.val)
      // (still open as it says: presented again where the one made in its place stands)
      chat_pops.left.set(chat_pops.left.untracked() + 1)
    }
  })
  |> ignore
}
