// A chat's page (chat.mbt's chat_page) made once in the window's tree on a narrow screen: its root a node of the
// stack's, kept by the chat, made again only as the workspace in view changes; what it shows followed by getters. Its
// messages (sfpages chat_list_node), composer (sfpages chat_composer_node), and bar its own nodes.

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
    let view = fn() { @sfbase.chat_view_now(src, r) }
    // (the list's way to its end, once it is made: what words sent take it to)
    let latest : Ref[() -> Unit] = Ref(fn() {  })
    // (where what was sent lands, by its row as the list has it, once the list is made)
    let landing : Ref[(String) -> @sfpages.MineLanding?] = Ref(fn(_) { None })
    // (its composer while made: what its page's layout and its picks read of the room it takes)
    let made_now : @signals.Signal[@sfpages.ChatComposerNode?] = @signals.signal(None, same=fn(a, b) {
      match (a, b) {
        (Some(x), Some(y)) => physical_equal(x.root, y.root)
        (None, None) => true
        _ => false
      }
    })
    // (the room under the list as this frame laid it out, read as it is painted: the composer's, or what the fold
    // leaves under the list where that is more)
    let list_room_laid = fn(laid : @view.Laid) {
      let room = match made_now.get() {
        Some(m) =>
          @sfpages.composer_room_in(
            laid.size(m.root).map(fn(z) { z.1 }).unwrap_or(0.0),
            laid.size(m.composer.cap).map(fn(z) { z.1 }).unwrap_or(0.0),
            (m.room_of)(),
          )
        None => 0.0
      }
      dmax(room, tabletop_clear_in(laid.size(p).map(fn(z) { z.1 }).unwrap_or(0.0), frame().foot))
    }
    p.show(fn() { view() is None }, fn(waiting) {
      waiting
      .over(Is(true))
      |> ignore
      @sfpages.chat_waiting_node(waiting, src, r, list_top, bar_foot)
    })
    // (its list over the page above the system's bar and its composer at its foot (or under the fold, the recent chats
    // under it), laid out by the page's room: the composer measured first, the room it takes (composer_room_in), or what
    // the fold leaves under the list where that is more, given the list as what covers its foot, its own lift
    // with it (Layout::measure's `foot`: its last row that tall), in the same layout: nothing of the composer or the
    // page read back)
    p.box(fn(body) {
      body.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      let lift : Ref[() -> Double] = Ref(fn() { 0.0 })
      let l = body.box(fn(l) {
        // (a new chat's list comes up with its first words sent, on their way: flight_node.mbt's send_list_rise)
        l
        .min_height(Is(Some(0.0)))
        .drawn_off(Painted(fn(laid) {
          (0.0, @sfbase.send_list_rise(laid, l, r.station + ":" + r.session, fn(f) {
            (landing.val)(f.key).map(fn(m) { m.anchor })
          }))
        }))
        |> ignore
        let list = @sfpages.chat_list_node(l, src, r, view, fn() { list_top() }, settings_core(src, w), foot_gap=list_foot())
        latest.val = list.to_latest
        landing.val = list.landing_of
        lift.val = list.lift
      })
      // (the composer over the list at the page's foot)
      let f = body.box(fn(f) {
        @sfpages.composer_on_page(f, src, r.station + ":" + r.session, fn() { app.nav.top_stay().0 == entry }, fn(f) {
        f.grow(By(fn() { if @ui.system_tabletop() is Some(_) { 1.0 } else { 0.0 } }))
        .basis(By(fn() { if @ui.system_tabletop() is Some(_) { Some(0.0) } else { None } }))
        .min_height(Is(Some(0.0))) |> ignore
        let made = @sfpages.chat_composer_node(
          f,
          src,
          r,
          view,
          fn() { @sfpages.composer_side() },
          // (its lines as many as the page's height gives them)
          (p, fn(_, h) { h }),
          fn(pane) { @sfpages.composer_foot_in(pane) },
          fn() { @sfpages.composer_alone },
          // (words sent: the list to its end, following it)
          fn(_key) { (latest.val)() },
          // (its keys and focus its own while this chat is the stack's top, not while another slides over it)
          active=fn() { app.nav.top_stay().0 == entry },
          drops=p,
        )
        made_now.set(Some(made))
        f.owns(fn() { made_now.set(None) }) |> ignore
        // The fold owns the room below it. The composer remains the same editor as the pose changes; the recent
        // chats take only the space left below it, and give that space up as the keyboard comes in.
        f.show(fn() { @ui.system_tabletop() is Some(_) }, fn(recent) {
          recent.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).clips(Is(true)) |> ignore
          recent_list_node(recent, src, w, stint)
        })
        })
      })
      // (what flies in the page: over its messages and its composer, under its bar and what opens over it, cut by
      // neither: what words sent fly in, sfpages' chat_flight_layer; laid out after them in the same layout, what
      // flies as big as what it lands on as that is laid out, Layout::anchor)
      let fl = body.box(fn(fl) {
        @sfpages.chat_flight_layer_made(r, fl)
        // (words sent: from the composer to their row's bubble and words, as the list has that row)
        @sfbase.send_flight_node(fl, r.station + ":" + r.session, fn(f) {
          (landing.val)(f.key).bind(fn(l) { l.text })
        }, quotes=fn(f, key) { (landing.val)(f.key).bind(fn(l) { l.quotes.get(key) }) }, files=fn(f, key) {
          (landing.val)(f.key).bind(fn(l) { l.files.get(key) })
        })
      })
      body.layout_box(By(fn() { (made_now.get().map(fn(m) { (m.room_of)() }), (lift.val)(), @ui.system_tabletop()) }), fn(lay, k) {
        let (of, lift, fold) = k
        // (as tall as the composer is, the recent chats under the fold taking none of it yet)
        let (_, ch) = lay.measure(f, lay.width)
        let room = match of {
          Some(o) => @sfpages.composer_room_in(lay.reported(f, "composer").unwrap_or(ch), lay.reported(f, "cap").unwrap_or(0.0), o)
          None => 0.0
        }
        // (what the fold leaves under the list: from it to the page's foot, the system's bar not counted)
        let under_fold = match fold {
          Some((top, _)) => dmax(0.0, lay.height - top)
          None => 0.0
        }
        let foot = dmax(room, under_fold) + lift
        lay.measure(l, lay.width, height=lay.height, foot=(0.0, foot)) |> ignore
        lay.place(l, 0.0, 0.0)
        match fold {
          // (under the fold, as far under it as the composer leaves room for at the page's foot, the recent chats
          // under it)
          Some((_, at)) => {
            let top = dmax(0.0, dmin(at, lay.height - room))
            lay.measure(f, lay.width, height=lay.height - top) |> ignore
            lay.place(f, 0.0, top)
          }
          None => lay.place(f, 0.0, lay.height - ch)
        }
        lay.measure(fl, lay.width, height=lay.height) |> ignore
        lay.place(fl, 0.0, 0.0)
      })
      |> ignore
    })
    |> ignore
    // (what is picked of a message: the finger's bar or the mouse's pill over it, under the bar: pick_node.mbt)
    p.box(fn(pl) {
      pl
      .over(Is(true))
      |> ignore
      @sfpages.pick_bar_node(pl, src, r.station + ":" + r.session, fn() { bar_foot() }, list_room_laid)
    })
    |> ignore
    // (a new chat it became from: that page's scene leaving over it, as the old view drew it, an island while it does:
    // new_chat_leaving)
    p.box(fn(l) {
      l
      .over(Is(true))
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
      })
    })
    |> ignore
  })
}
