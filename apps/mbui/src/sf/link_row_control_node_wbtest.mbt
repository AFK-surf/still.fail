// A link row with an independent end control: its two actions, their reach, responsive words and live styles.

///|
fn controlled_row_case(
  look : Look,
  width : Double,
  finger : Bool,
  face : @signals.Signal[Bool],
  shown : @signals.Signal[Bool],
  lacks : @signals.Signal[Bool],
  styled : @signals.Signal[Bool],
  there : @signals.Signal[Bool],
  opened : Ref[Int],
  revoked : Ref[Int],
  busy? : @signals.Signal[Bool] = @signals.signal(false),
  custom? : Bool = true,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=width, h=300.0, platform=if finger { 2 } else { 0 })
  t.host_says_finger(Some(finger))
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      look_lent(b, look)
      b.show(fn() { there.get() }, fn(p) {
        group_node(p, fn(g) {
          link_row_node(
            g,
            fn() { "A chat with a long and useful title" },
            fn() { opened.val += 1 },
            value=fn() { "2 minutes ago" },
            note=fn() { "The reason this chat needs the phone" },
            face=fn() { face.get() },
            lacks=fn() { lacks.get() },
            title_style?=if custom {
              Some(fn() { @ui.text_style(size=Body, weight=if styled.get() { Normal } else { Bold }, wrap=true) })
            } else { None },
            note_style=fn() {
              @ui.text_style(size=Caption, color=Muted, balance=styled.get())
            },
            control=fn(end) {
              button_node(end, fn() { "Revoke" }, fn() { revoked.val += 1 }, tone=Ghost, busy=fn() { busy.get() }) |> ignore
            },
            control_shown=fn() { shown.get() },
          )
        })
      })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
fn controlled_word(words : String) -> @view.Drawn {
  @ui.view_tree().unwrap().drawn().iter().find_first(fn(d) { d.words == words }).unwrap()
}

///|
test "link row end control: each action has its own touch and pointer target, keyboard focus and reader action" {
  for look in [Narrow, Wide] {
    for finger in [false, true] {
      for face in [false, true] {
        let opened = Ref(0)
        let revoked = Ref(0)
        let t = controlled_row_case(
          look, if look is Narrow { 320.0 } else { 760.0 }, finger, @signals.signal(face), @signals.signal(true),
          @signals.signal(false), @signals.signal(true), @signals.signal(true), opened, revoked,
        )
        let row = t.get(Link, label="A chat with a long and useful title")
        let button = t.get(Button, label="Revoke")
        let (bx, by, bw, bh) = button.rect
        assert_true(bw >= 44.0 && bh == button_height(), msg="\{look} \{finger} \{face}: \{button.rect}")
        // Both ends of the button's actual room, including the end that reaches into the card padding.
        for x in [bx + 1.0, bx + bw - 1.0] {
          assert_eq(t.press_target_at(x, by + bh / 2.0).map(fn(s) { s.label }), Some("Revoke"))
          t.tap(x, by + bh / 2.0)
        }
        assert_eq((opened.val, revoked.val), (0, 2))
        // A finger gets 44 points of reach; keyboard and mouse use the button's 36-point drawn height.
        for y in (if finger { [by - 3.0, by + bh + 3.0] } else { [by + 1.0, by + bh - 1.0] }) {
          assert_eq(t.press_target_at(bx + bw / 2.0, y).map(fn(s) { s.label }), Some("Revoke"), msg="\{look} \{finger} \{face}: button \{button.rect}, y=\{y}")
          t.tap(bx + bw / 2.0, y)
        }
        assert_eq((opened.val, revoked.val), (0, 4))
        let (rx, ry, _, rh) = row.rect
        t.tap(rx + 2.0, ry + rh / 2.0)
        assert_eq((opened.val, revoked.val), (1, 4))
        t.act(Link, Focus, label="A chat with a long and useful title")
        t.enter()
        t.tab()
        assert_eq(t.focused().map(fn(s) { s.label }), Some("Revoke"))
        t.key(@ui.key_space)
        t.act(Button, Activate, label="Revoke")
        assert_eq((opened.val, revoked.val), (2, 6))
      }
    }
  }
}

///|
test "link row: a busy end button is read as disabled and a press there cannot open the row" {
  for look in [Narrow, Wide] {
    let busy = @signals.signal(false)
    let opened = Ref(0)
    let revoked = Ref(0)
    let t = controlled_row_case(
      look, 390.0, true, @signals.signal(true), @signals.signal(true), @signals.signal(false), @signals.signal(true),
      @signals.signal(true), opened, revoked, busy~,
    )
    busy.set(true)
    t.draw()
    let button = t.get(Button, label="Revoke")
    assert_true(button.disabled)
    let (x, y, w, h) = button.rect
    t.tap(x + w / 2.0, y + h / 2.0)
    assert_eq((opened.val, revoked.val), (0, 0))
  }
}

///|
test "link row end control: title, time and reason remain clear of the control at narrow widths" {
  for look in [Narrow, Wide] {
    let face = true
    for custom in [false, true] {
      let t = controlled_row_case(
        look, 280.0, true, @signals.signal(face), @signals.signal(true), @signals.signal(false), @signals.signal(true),
        @signals.signal(true), Ref(0), Ref(0), custom~,
      )
      for scale in [1.0, 2.0] {
        t.set_font_scale(scale)
        t.draw()
        let (bx, by, bw, bh) = t.get(Button, label="Revoke").rect
        let words = ["A chat with a long and useful title", "2 minutes ago", "The reason this chat needs the phone"].map(controlled_word)
        for w in words {
          assert_true(
            w.x + w.w <= bx + 0.01 || w.y + w.h <= by + 0.01 || w.y >= by + bh - 0.01 || w.x >= bx + bw - 0.01,
            msg="\{look} scale=\{scale} custom=\{custom}: \{w.words} at (\{w.x}, \{w.y}, \{w.w}, \{w.h}), button (\{bx}, \{by}, \{bw}, \{bh})",
          )
        }
        for i in 0..<words.length() {
          for j in (i + 1)..<words.length() {
            let (a, b) = (words[i], words[j])
            assert_true(a.x + a.w <= b.x + 0.01 || a.y + a.h <= b.y + 0.01 || a.y >= b.y + b.h - 0.01 || a.x >= b.x + b.w - 0.01)
          }
        }
      }
    }
  }
}

///|
test "link row: warning, title weight, balanced note and its control follow state and leave with their row" {
  for look in [Narrow, Wide] {
    let face = @signals.signal(true)
    let shown = @signals.signal(true)
    let lacks = @signals.signal(false)
    let styled = @signals.signal(false)
    let there = @signals.signal(true)
    let t = controlled_row_case(look, 240.0, true, face, shown, lacks, styled, there, Ref(0), Ref(0))
    let title = fn() { controlled_word("A chat with a long and useful title") }
    let note = fn() { controlled_word("The reason this chat needs the phone") }
    let ink = note().ink
    assert_eq((title().words_look.weight, note().words_look.balance), (700, false))
    lacks.set(true)
    styled.set(true)
    t.draw()
    assert_eq((title().words_look.weight, note().words_look.balance), (400, true))
    assert_eq(note().ink, @ui.style_ink(lacking))
    assert_true(note().ink != ink)
    t.act(Button, Focus, label="Revoke")
    let button_id = t.get(Button, label="Revoke").id
    face.set(false)
    t.draw()
    assert_eq((t.get(Button, label="Revoke").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Revoke")))
    face.set(true)
    t.draw()
    assert_eq((t.get(Button, label="Revoke").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Revoke")))
    shown.set(false)
    t.draw()
    assert_true(t.query(Button, label="Revoke") is None)
    assert_true(note().words_look.balance && note().words_look.wrap)
    assert_true(note().h > @ui.current().sp(note().words_look.line))
    shown.set(true)
    t.draw()
    assert_true(t.query(Button, label="Revoke") is Some(_))
    there.set(false)
    t.draw()
    assert_true(t.query(Link, label="A chat with a long and useful title") is None)
    assert_true(t.query(Button, label="Revoke") is None)
  }
}

///|
test "link row: settings title and note styles follow the page and their live wrapping choices" {
  for look in [Narrow, Wide] {
    let wrap_title = @signals.signal(false)
    let wrap_note = @signals.signal(false)
    let t = @ui.Tester::new(fn(_c) {  }, w=220.0, h=500.0)
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        look_lent(b, look)
        group_node(b, fn(g) {
          link_row_node(
            g,
            fn() { "A station title that needs more than one line" },
            fn() {  },
            note=fn() { "A pairing explanation that should be balanced across several lines" },
            title_style=fn() { settings_row_title_style(g, wrap=wrap_title.get()) },
            note_style=fn() { settings_row_note_style(g, wrap=wrap_note.get()) },
          )
        })
      })
      |> ignore
    })
    t.draw()
    let title = fn() { controlled_word("A station title that needs more than one line") }
    let note = fn() { controlled_word("A pairing explanation that should be balanced across several lines") }
    let th = @ui.tree_theme()
    assert_eq(title().words_look.size, th.text_size(if look is Wide { Ui } else { Body }).0)
    assert_eq(note().words_look.size, th.text_size(if look is Wide { Caption } else { Meta }).0)
    assert_eq((title().words_look.weight, title().words_look.wrap, note().words_look.wrap), (400, false, false))
    assert_eq((title().ink, note().ink), (th.color(Fg), th.color(Muted)))
    let title_line_height = title().h
    let note_line_height = note().h
    wrap_title.set(true)
    wrap_note.set(true)
    t.draw()
    assert_eq(title().words_look.size, th.text_size(Body).0)
    assert_eq((title().words_look.weight, title().words_look.wrap, note().words_look.wrap, note().words_look.balance), (400, true, true, true))
    assert_true(title().h > title_line_height)
    assert_true(note().h > note_line_height)
    wrap_title.set(false)
    wrap_note.set(false)
    t.draw()
    assert_eq((title().words_look.wrap, note().words_look.wrap), (false, false))
  }
}

///|
test "link row: danger and value ink follow state while a busy action keeps focus without repeating" {
  for look in [Narrow, Wide] {
    for finger in [false, true] {
      let danger = @signals.signal(false)
      let value_lit = @signals.signal(false)
      let busy = @signals.signal(false)
      let calls = Ref(0)
      let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=if finger { 2 } else { 0 })
      t.host_says_finger(Some(finger))
      @ui.set_view_app(fn(root) {
        root.box(fn(b) {
          look_lent(b, look)
          group_node(b, fn(g) {
            link_row_node(
              g, fn() { "Delete vault" }, fn() { calls.val += 1 },
              note=fn() { "Devices waiting for a key" }, value=fn() { "Authorize" }, chevron=false,
              danger=fn() { danger.get() }, value_lit=fn() { value_lit.get() }, busy=fn() { busy.get() },
            )
          })
        })
        |> ignore
      })
      t.draw()
      let title = fn() { controlled_word("Delete vault") }
      let value = fn() { controlled_word("Authorize") }
      let (title_ink, value_ink) = (title().ink, value().ink)
      t.act(Link, Focus, label="Delete vault")
      t.enter()
      assert_eq(calls.val, 1)
      danger.set(true)
      value_lit.set(true)
      busy.set(true)
      t.draw()
      assert_eq(title().ink, @ui.style_ink(bad))
      assert_eq(value().ink, link_ink())
      assert_true(title().ink != title_ink && value().ink != value_ink)
      assert_eq(t.focused().map(fn(s) { s.label }), Some("Delete vault"))
      let (x, y, w, h) = t.get(Link, label="Delete vault").rect
      t.tap(x + w / 2.0, y + h / 2.0)
      t.enter()
      t.act(Link, Activate, label="Delete vault")
      assert_eq(calls.val, 1)
      busy.set(false)
      danger.set(false)
      value_lit.set(false)
      t.draw()
      assert_eq((title().ink, value().ink), (title_ink, value_ink))
      t.act(Link, Activate, label="Delete vault")
      assert_eq(calls.val, 2)
    }
  }
}

///|
test "link row: an action value stays clear of its title at a large text size" {
  for look in [Narrow, Wide] {
    let t = @ui.Tester::new(fn(_c) {  }, w=220.0, h=400.0, platform=2)
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        look_lent(b, look)
        group_node(b, fn(g) {
          link_row_node(
            g, fn() { "Lock secrets" }, fn() {  }, value=fn() { "Lock now" },
            value_lit=fn() { true }, chevron=false,
          )
        })
      }) |> ignore
    })
    t.set_font_scale(2.0)
    t.draw()
    let (a, b) = (controlled_word("Lock secrets"), controlled_word("Lock now"))
    assert_true(
      a.x + a.w <= b.x + 0.01 || a.y + a.h <= b.y + 0.01 || a.y >= b.y + b.h - 0.01 || a.x >= b.x + b.w - 0.01,
      msg="\{look}: title (\{a.x}, \{a.y}, \{a.w}, \{a.h}), value (\{b.x}, \{b.y}, \{b.w}, \{b.h})",
    )
  }
}

///|
test "link row: a long single-line title leaves room for its chevron at a large text size" {
  for look in [Narrow, Wide] {
    let t = @ui.Tester::new(fn(_c) {  }, w=220.0, h=400.0, platform=2)
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        look_lent(b, look)
        group_node(b, fn(g) {
          link_row_node(g, fn() { "Workspace Station" }, fn() {  }, note=fn() { "Needs pairing" })
        })
      }) |> ignore
    })
    t.set_font_scale(2.0)
    t.draw()
    let tree = @ui.view_tree().unwrap()
    let title = controlled_word("Workspace Station")
    let arrow = tree.drawn().iter().find_first(fn(d) { tree.drawn_name(d.id) == "/icon/chevron-right/" }).unwrap()
    assert_true(title.x + title.w <= arrow.x + 0.01, msg="\{look}: title right \{title.x + title.w}, arrow left \{arrow.x}")
  }
}

///|
test "link row: a narrow face row gives its words room and keeps its independent control focused" {
  for (look, with_tail) in [(Narrow, false), (Narrow, true), (Wide, false), (Wide, true)] {
    let opened = Ref(0)
    let revoked = Ref(0)
    let t = @ui.Tester::new(fn(_c) {  }, w=650.0, h=1000.0, platform=2)
    t.host_says_finger(Some(true))
    @ui.set_view_app(fn(root) {
      root.padding(Is((48.0, 0.0, 48.0, 0.0))) |> ignore
      root.box(fn(b) {
        look_lent(b, look)
        group_node(b, fn(g) {
          link_row_node(
            g, fn() { "Alexandra Chen" }, fn() { opened.val += 1 },
            value=fn() { "2 minutes ago" }, note=fn() { "Waiting for a device" }, face=fn() { true },
            lead=LeadMade(fn(l) { avatar_node(l, fn() { "alexandra" }, fn() { "Alexandra Chen" }, fn() { "" }, 28.0) }),
            tail=fn(e) { e.width(Is(Some(10.0))).height(Is(Some(10.0))).says(Is(Some(@view.said(Image, label="Status")))) |> ignore },
            tail_shown=fn() { with_tail },
            control=fn(e) { button_node(e, fn() { "Revoke" }, fn() { revoked.val += 1 }, tone=Ghost) |> ignore },
          )
        })
      }) |> ignore
    })
    t.set_font_scale(2.0)
    t.draw()
    t.act(Button, Focus, label="Revoke")
    let button_id = t.get(Button, label="Revoke").id
    t.resize(320.0, 1000.0)
    t.draw()
    let title = controlled_word("Alexandra Chen")
    let time = controlled_word("2 minutes ago")
    let note = controlled_word("Waiting for a device")
    let (bx, by, bw, bh) = t.get(Button, label="Revoke").rect
    assert_true(by >= note.y + note.h - 0.01, msg="\{look}: button \{(bx, by, bw, bh)}, note \{(note.x, note.y, note.w, note.h)}, title \{(title.x, title.y, title.w, title.h)}, time \{(time.x, time.y, time.w, time.h)}")
    assert_true(title.w >= @ui.current().sp(@ui.tree_theme().text_size(Body).0 * 3.5), msg="\{look}: title width \{title.w}")
    assert_true(time.h <= @ui.current().sp(time.words_look.line) * 2.0 + 0.01, msg="\{look}: time height \{time.h}")
    assert_eq((t.get(Button, label="Revoke").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Revoke")))
    t.enter()
    t.tap(bx + bw - 1.0, by + bh / 2.0)
    let (rx, _, _, _) = t.get(Link, label="Alexandra Chen").rect
    t.tap(rx + 2.0, title.y + title.h / 2.0)
    assert_eq((opened.val, revoked.val), (1, 2))
    t.act(Button, Focus, label="Revoke")
    t.resize(650.0, 1000.0)
    t.draw()
    assert_eq((t.get(Button, label="Revoke").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Revoke")))
    t.act(Button, Activate, label="Revoke")
    assert_eq((opened.val, revoked.val), (1, 3))
  }
}

///|
test "link row: narrow account controls leave names readable and stay independent of adjacent rows" {
  for look in [Narrow, Wide] {
    for finger in [false, true] {
      for with_note in [false, true] {
        let title = if with_note { "Alexandra Chen" } else { "jamie.long@example.org" }
        let opened = Ref(0)
        let signed_out = Ref(0)
        let next_opened = Ref(0)
        let t = @ui.Tester::new(fn(_c) {  }, w=650.0, h=1000.0, platform=if finger { 2 } else { 0 })
        t.host_says_finger(Some(finger))
        @ui.set_view_app(fn(root) {
          root.padding(Is((48.0, 0.0, 48.0, 0.0))) |> ignore
          root.box(fn(b) {
            look_lent(b, look)
            group_node(b, fn(g) {
              link_row_node(
                g, fn() { title }, fn() { opened.val += 1 }, goes=with_note,
                note=fn() { if with_note { "alexandra.chen@example.org · Google" } else { "" } },
                lead=LeadMade(fn(l) { avatar_node(l, fn() { "alexandra@example.org" }, fn() { title }, fn() { "" }, identity_mark) }),
                control=fn(e) { button_node(e, fn() { "Sign out" }, fn() { signed_out.val += 1 }, tone=Ghost) |> ignore },
              )
              link_row_node(g, fn() { "Next row" }, fn() { next_opened.val += 1 })
            })
          }) |> ignore
        })
        t.set_font_scale(2.0)
        t.draw()
        t.act(Button, Focus, label="Sign out")
        let button_id = t.get(Button, label="Sign out").id
        t.resize(320.0, 1000.0)
        t.draw()
        let words = controlled_word(title)
        let (bx, by, bw, bh) = t.get(Button, label="Sign out").rect
        let (nx, ny, _, nh) = t.get(Link, label="Next row").rect
        assert_true(words.w >= @ui.current().sp(@ui.tree_theme().text_size(Body).0 * 3.5), msg="\{look} \{with_note}: title width \{words.w}")
        assert_true(by >= words.y + words.h - 0.01 && by + bh <= ny + 0.01, msg="\{look} \{with_note}: button \{(bx, by, bw, bh)}, title \{(words.x, words.y, words.w, words.h)}, next \{ny}")
        if with_note {
          let note = controlled_word("alexandra.chen@example.org · Google")
          assert_true(by >= note.y + note.h - 0.01)
        } else {
          assert_true(t.query(Link, label=title) is None)
        }
        assert_eq((t.get(Button, label="Sign out").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Sign out")))
        for y in (if finger { [by - 3.0, by + bh + 3.0] } else { [by + 1.0, by + bh - 1.0] }) {
          assert_eq(t.press_target_at(bx + bw / 2.0, y).map(fn(s) { s.label }), Some("Sign out"))
          t.tap(bx + bw / 2.0, y)
        }
        t.tap(nx + 2.0, ny + nh / 2.0)
        assert_eq((opened.val, signed_out.val, next_opened.val), (0, 2, 1))
        t.act(Button, Focus, label="Sign out")
        t.resize(650.0, 1000.0)
        t.draw()
        assert_eq((t.get(Button, label="Sign out").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Sign out")))
        t.enter()
        t.resize(320.0, 1000.0)
        t.draw()
        assert_eq((t.get(Button, label="Sign out").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Sign out")))
        t.act(Button, Activate, label="Sign out")
        assert_eq((opened.val, signed_out.val, next_opened.val), (0, 4, 1))
      }
    }
  }
}

///|
test "link row: a custom authorization mark lines up with its title" {
  for look in [Narrow, Wide] {
    let t = @ui.Tester::new(fn(_c) {  }, w=320.0, h=700.0, platform=2)
    @ui.set_view_app(fn(root) {
      root.padding(Is((48.0, 0.0, 48.0, 0.0))) |> ignore
      root.box(fn(b) {
        look_lent(b, look)
        group_node(b, fn(g) {
          link_row_node(
            g, fn() { "Data export helper" }, fn() {  }, goes=false,
            note=fn() { "Signed · workspace · granted 2 days ago" },
            lead=LeadMade(fn(l) { icon_node(l, "key", 16.0, By(fn() { theme().p.muted })) |> ignore }),
            control=fn(e) { button_node(e, fn() { "Revoke" }, fn() {  }, tone=Ghost) |> ignore },
          )
        })
      }) |> ignore
    })
    for scale in [1.0, 2.0] {
      t.set_font_scale(scale)
      t.draw()
      let title = controlled_word("Data export helper")
      let tree = @ui.view_tree().unwrap()
      let mark = tree.drawn().iter().find_first(fn(d) { tree.drawn_name(d.id) == "/icon/key/" }).unwrap()
      assert_true(mark.y >= title.y - 0.01 && mark.y + mark.h <= title.y + title.h + 0.01, msg="\{look} \{scale}: mark \{(mark.y, mark.h)}, title \{(title.y, title.h)}")
    }
  }
}

///|
test "link row: an open part below keeps its node and focus as its face or control changes" {
  for look in [Narrow, Wide] {
    let face = @signals.signal(false)
    let shown = @signals.signal(true)
    let presses = Ref(0)
    let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=400.0)
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        look_lent(b, look)
        group_node(b, fn(g) {
          link_row_node(
            g, fn() { "A chat" }, fn() {  }, note=fn() { "Its reason" },
            face=fn() { face.get() }, control_shown=fn() { shown.get() },
            control=fn(e) { button_node(e, fn() { "Revoke" }, fn() {  }, tone=Ghost) |> ignore },
            below=fn(e) { button_node(e, fn() { "Details" }, fn() { presses.val += 1 }) |> ignore },
            below_open=fn() { 1.0 },
          )
        })
      })
      |> ignore
    })
    t.draw()
    t.act(Link, Focus, label="A chat")
    t.tab()
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Revoke"))
    t.tab()
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Details"))
    let id = t.get(Button, label="Details").id
    face.set(true)
    t.draw()
    assert_eq((t.get(Button, label="Details").id, t.focused().map(fn(s) { s.label })), (id, Some("Details")))
    shown.set(false)
    t.draw()
    assert_eq((t.get(Button, label="Details").id, t.focused().map(fn(s) { s.label })), (id, Some("Details")))
    shown.set(true)
    face.set(false)
    t.draw()
    assert_eq((t.get(Button, label="Details").id, t.focused().map(fn(s) { s.label })), (id, Some("Details")))
    t.enter()
    assert_eq(presses.val, 1)
  }
}

///|
test "link row: changing permission keeps the independent control while the row joins and leaves the link order" {
  for look in [Narrow, Wide] {
    for finger in [false, true] {
      let permitted = @signals.signal(false)
      let opened = Ref(0)
      let removed = Ref(0)
      let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=if finger { 2 } else { 0 })
      t.host_says_finger(Some(finger))
      @ui.set_view_app(fn(root) {
        root.box(fn(b) {
          look_lent(b, look)
          group_node(b, fn(g) {
            link_row_node(
              g, fn() { "Member" }, fn() { opened.val += 1 },
              note=fn() { "member@example.org" }, goes=false, goes_now=fn() { permitted.get() },
              face=fn() { true }, chevron=false,
              control=fn(e) { button_node(e, fn() { "Remove" }, fn() { removed.val += 1 }, tone=Ghost) |> ignore },
            )
          })
        })
        |> ignore
      })
      t.draw()
      assert_true(t.query(Link, label="Member") is None)
      t.act(Button, Focus, label="Remove")
      let button_id = t.get(Button, label="Remove").id
      t.enter()
      assert_eq((opened.val, removed.val), (0, 1))
      permitted.set(true)
      t.draw()
      assert_true(t.query(Link, label="Member") is Some(_))
      assert_eq((t.get(Button, label="Remove").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Remove")))
      let (x, y, _, h) = t.get(Link, label="Member").rect
      t.tap(x + 2.0, y + h / 2.0)
      assert_eq((opened.val, removed.val), (1, 1))
      t.act(Button, Focus, label="Remove")
      permitted.set(false)
      t.draw()
      assert_true(t.query(Link, label="Member") is None)
      assert_eq((t.get(Button, label="Remove").id, t.focused().map(fn(s) { s.label })), (button_id, Some("Remove")))
      t.enter()
      assert_eq((opened.val, removed.val), (1, 2))
    }
  }
}

///|
test "link row: faces and end controls are centered and adjacent member rows keep their own touch targets" {
  for look in [Narrow, Wide] {
    let first_open = Ref(0)
    let second_open = Ref(0)
    let first_remove = Ref(0)
    let second_remove = Ref(0)
    let t = @ui.Tester::new(fn(_c) {  }, w=480.0, h=400.0, platform=2)
    t.host_says_finger(Some(true))
    @ui.set_view_app(fn(root) {
      root.box(fn(b) {
        look_lent(b, look)
        group_node(b, fn(g) {
          link_row_node(
            g, fn() { "Alexandra Chen" }, fn() { first_open.val += 1 },
            note=fn() { "alexandra.chen@example.org" }, face=fn() { true },
            lead=LeadMade(fn(l) {
              l.says(Is(Some(@view.said(Image, label="Alexandra face")))) |> ignore
              avatar_node(l, fn() { "alexandra" }, fn() { "Alexandra Chen" }, fn() { "" }, 28.0)
            }),
            tail=fn(e) {
              e.width(Is(Some(10.0))).height(Is(Some(10.0))).says(Is(Some(@view.said(Image, label="Status")))) |> ignore
            },
            control=fn(e) { button_node(e, fn() { "Remove Alexandra" }, fn() { first_remove.val += 1 }, tone=Ghost) |> ignore },
          )
          link_row_node(
            g, fn() { "Bo Zhang" }, fn() { second_open.val += 1 },
            note=fn() { "bo.zhang@example.org" }, face=fn() { true },
            lead=LeadMade(fn(l) {
              l.says(Is(Some(@view.said(Image, label="Bo face")))) |> ignore
              avatar_node(l, fn() { "bo" }, fn() { "Bo Zhang" }, fn() { "" }, 28.0)
            }),
            control=fn(e) { button_node(e, fn() { "Remove Bo" }, fn() { second_remove.val += 1 }, tone=Ghost) |> ignore },
          )
        })
      }) |> ignore
    })
    t.draw()
    for (name, face, button) in [
      ("Alexandra Chen", "Alexandra face", "Remove Alexandra"),
      ("Bo Zhang", "Bo face", "Remove Bo"),
    ] {
      let (rx, ry, _, rh) = t.get(Link, label=name).rect
      let (_, ay, _, ah) = t.get(Image, label=face).rect
      let (bx, by, bw, bh) = t.get(Button, label=button).rect
      assert_true(((ry + rh / 2.0) - (ay + ah / 2.0)).abs() < 0.01)
      assert_true(((ry + rh / 2.0) - (by + bh / 2.0)).abs() < 0.01)
      t.tap(bx + bw - 1.0, by + bh / 2.0)
      t.tap(rx + 2.0, ry + rh / 2.0)
    }
    let (_, status_y, _, status_h) = t.get(Image, label="Status").rect
    let title = controlled_word("Alexandra Chen")
    assert_true(((status_y + status_h / 2.0) - (title.y + title.h / 2.0)).abs() < 0.01)
    assert_eq((first_open.val, second_open.val, first_remove.val, second_remove.val), (1, 1, 1, 1))
  }
}
