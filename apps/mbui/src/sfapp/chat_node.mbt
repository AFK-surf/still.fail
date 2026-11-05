// A chat's page (chat.mbt's chat_page) made once in the window's tree on a narrow screen: its root a node of the
// stack's, kept by the chat, made again only as the workspace in view changes; what it shows followed by getters. Its
// messages (sfpages chat_list_node), composer (sfpages chat_composer_node), and bar its own nodes. Deferred menu
// actions (opening links and copying text or pictures) are still drained in this page's context.

///|
/// Chat `r`'s page in `v` while it shows (entry `entry` of the stack): its messages under its bar over its composer's
/// room, the composer at its foot, the bar over them.
fn chat_root_node(v : @view.View, src : Source, r : ChatRef, entry : Int, frame : () -> PageFrame, stint : () -> Int) -> Unit {
  v.pick(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(p, _id) {
    // The page fills the stack; its list ends above the system bar, as chat_page's padded root did. Overlays still
    // span the page, with the composer itself padded above that bar below.
    p.grow(Is(1.0)).min_height(Is(Some(0.0))).padding(By(fn() { (0.0, 0.0, 0.0, frame().foot) }))
    .ground(By(fn() { @sf.theme().p.bg })) |> ignore
    guard @signals.untracked(fn() { workspace_in_view(src).0 }) is Some(w) else { return }
    let view = fn() { view_of_chat(src, r).0 }
    let entries = fn() { view_of_chat(src, r).1 }
    let width = fn() { p.window().0 }
    let height = fn() { p.window().1 }
    // (the list's way to its end, once it is made: what words sent take it to)
    let latest : Ref[() -> Unit] = Ref(fn() {  })
    // (where what was sent lands, by its row as the list has it, once the list is made)
    let landing : Ref[(String) -> @sfpages.MineLanding?] = Ref(fn(_) { None })
    // (the composer's room at the page's foot, as it says it: the list's foot over it)
    let room : @signals.Signal[(() -> Double)?] = @signals.signal(None, same=fn(a, b) { a is None && b is None })
    let room_height : @signals.Signal[(() -> @view.Height)?] = @signals.signal(None, same=fn(a, b) { a is None && b is None })
    let composer_room = fn() { room.get().map(fn(f) { f() }).unwrap_or(0.0) }
    let page_height = fn() { p.laid_size_told().map(fn(z) { z.1 }).unwrap_or(height()) }
    let list_room = fn() { dmax(composer_room(), tabletop_clear_in(page_height(), frame().foot)) }
    p.show(fn() { view() is None }, fn(waiting) {
      waiting
      .over(Is(true))
      .width(By(fn() { p.laid_size_told().map(fn(z) { z.0 }) }))
      .height(By(fn() { p.laid_size_told().map(fn(z) { z.1 }) }))
      |> ignore
      @sfpages.chat_waiting_node(waiting, src, r, list_top, bar_foot)
    })
    p.box(fn(l) {
      // (a new chat's list comes up with its first words sent, on their way: flight_node.mbt's send_list_rise)
      l
      .grow(Is(1.0))
      .min_height(Is(Some(0.0)))
      .drawn_off(By(fn() {
        (0.0, @sfbase.send_list_rise(l, r.station + ":" + r.session, fn(f) {
          (landing.val)(f.key).map(fn(m) { m.anchor })
        }))
      }))
      |> ignore
      let list = @sfpages.chat_list_node(l, src, r, view, entries, fn() { list_top() }, list_room, settings_core(src, w), foot_gap=list_foot(),
        foot_height=fn() {
          room_height.get().map(fn(f) { f() }).unwrap_or(@view.height(0.0))
          .maximum(@view.height(tabletop_clear_in(page_height(), frame().foot)))
        })
      latest.val = list.to_latest
      landing.val = list.landing_of
    })
    |> ignore
    // (the composer over the list at the page's foot, over the navigation bar)
    p.box(fn(f) {
      // (over all of the page, what it holds at its foot)
      f
      .over(Is(true))
      .width(By(fn() { p.laid_size_told().map(fn(z) { z.0 }) }))
      .height(By(fn() { p.laid_size_told().map(fn(z) { z.1 }) }))
      .lies_along(By(fn() { if @ui.system_tabletop() is Some(_) { Start } else { End } }))
      .padding(By(fn() {
        let top = match @ui.system_tabletop() {
          Some((_, foot)) => dmax(0.0, dmin(foot, page_height() - frame().foot - composer_room()))
          None => 0.0
        }
        (0.0, top, 0.0, frame().foot)
      }))
      |> ignore
      @sfpages.composer_on_page(f, fn() { app.nav.top_stay().0 == entry }, fn(f) {
      f.grow(By(fn() { if @ui.system_tabletop() is Some(_) { 1.0 } else { 0.0 } }))
      .basis(By(fn() { if @ui.system_tabletop() is Some(_) { Some(0.0) } else { None } }))
      .min_height(Is(Some(0.0))) |> ignore
      let made = @sfpages.chat_composer_node(
        f,
        src,
        r,
        view,
        fn() { @sfpages.composer_width(width()) },
        height,
        fn() { @sfpages.composer_foot_in(width()) },
        fn() { @sfpages.composer_alone },
        // (words sent: the list to its end, following it)
        fn(_key) { (latest.val)() },
        // (its keys and focus its own while this chat is the stack's top, not while another slides over it)
        active=fn() { app.nav.top_stay().0 == entry },
        drops=p,
      )
      room.set(Some(made.room))
      room_height.set(Some(made.room_height))
      made.root.shrink(Is(0.0)) |> ignore
      f.owns(fn() { room.set(None); room_height.set(None) }) |> ignore
      // The fold owns the room below it. The composer remains the same editor as the pose changes; the recent
      // chats take only the space left below it, and give that space up as the keyboard comes in.
      f.show(fn() { @ui.system_tabletop() is Some(_) }, fn(recent) {
        recent.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).clips(Is(true)) |> ignore
        recent_list_node(recent, src, w, stint)
      })
      })
    })
    |> ignore
    // (what flies in the page: over its messages and its composer, under its bar and what opens over it, cut by
    // neither: what words sent fly in, sfpages' chat_flight_layer)
    p.box(fn(fl) {
      fl
      .over(Is(true))
      .width(By(fn() { p.laid_size_told().map(fn(z) { z.0 }) }))
      .height(By(fn() { p.laid_size_told().map(fn(z) { z.1 }) }))
      |> ignore
      @sfpages.chat_flight_layer_made(r, fl)
      // (words sent: from the composer to their row's bubble and words, as the list has that row)
      @sfbase.send_flight_node(fl, r.station + ":" + r.session, fn(f) {
        (landing.val)(f.key).bind(fn(l) { l.text })
      }, quotes=fn(f, key) { (landing.val)(f.key).bind(fn(l) { l.quotes.get(key) }) }, files=fn(f, key) {
        (landing.val)(f.key).bind(fn(l) { l.files.get(key) })
      })
    })
    |> ignore
    // (what is picked of a message: the finger's bar or the mouse's pill over it, under the bar: pick_node.mbt)
    p.box(fn(pl) {
      pl
      .over(Is(true))
      .width(By(fn() { p.laid_size_told().map(fn(z) { z.0 }) }))
      .height(By(fn() { p.laid_size_told().map(fn(z) { z.1 }) }))
      |> ignore
      @sfpages.pick_bar_node(pl, src, r.station + ":" + r.session, fn() { bar_foot() }, list_room)
    })
    |> ignore
    // (a new chat it became from: that page's scene leaving over it, as the old view drew it, an island while it does:
    // new_chat_leaving)
    p.box(fn(l) {
      l
      .over(Is(true))
      .width(By(fn() { p.laid_size_told().map(fn(z) { z.0 }) }))
      .height(By(fn() { p.laid_size_told().map(fn(z) { z.1 }) }))
      |> ignore
      // (let go once it has left: nothing of it read again, its way's clock no more)
      let left = @signals.signal(false, same=fn(a, b) { a == b })
      l.show(fn() { @sfbase.fresh.became.get() == Some(r) && !left.get() }, fn(o) {
        o.grow(Is(1.0)) |> ignore
        @ui.old(o, fn(c) {
          if @sfbase.new_chat_leaving_of(c, r) {
            new_chat_leaving(c, src, w, r)
          } else {
            c.tell("new-chat-left", fn() { left.set(true) })
          }
        })
        .grow(Is(1.0))
        |> ignore
      })
    })
    |> ignore
    // The bar over all of it: its words, marks and keys are retained by the page.
    p.box(fn(b) {
      b.over(Is(true)).width_share(Is(1.0)).lies_along(Is(Start)) |> ignore
      b.show(fn() { app.nav.shows(entry) }, fn(o) {
        chat_bar_node(o, src, w, r, view, stint, frame)
        // A menu's choice may leave host work to finish through this page's context.
        @ui.old(
          o,
          fn(c) {
            app.nav.page_old(c, entry, fn(c) {
              // (what a menu's choice in its messages left: menus.mbt)
              @sfpages.chat_menus_frame(c)
            })
          },
          natural=true,
        )
        .over(Is(true)) |> ignore
      })
    })
    |> ignore
  })
}
