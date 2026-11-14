// The search, one in every tier (sfpages' switcher.mbt): at a width of each tier with a finger and with a mouse, the
// same words find the same; with a finger its page in the lists' box (sfpages' search.mbt), from the field at a list's
// top; with a mouse ⌘K: laid out Medium or Large its panel (sfdesk's switcher.mbt), Small the same page as a finger's,
// over the page open. A row pressed opens its chat where the shell has it: ⌘K's panel closes as it does, the search's
// page stays open in the lists' box.

///|
/// The fixture's Home at width `w` with `platform`'s hand, the search opened as its frame has it, `words` typed.
fn finder_tester(w : Double, platform : Int, regular : Bool, words : String) -> @ui.Tester raise {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w~, h=900.0, platform~)
  if regular {
    let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
    assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  }
  t.draw()
  if platform == 2 {
    // a finger's: the field at the list's top, in every tier
    list_up_to_top(t)
    t.draw()
    tap_search_field(t)
    t.run_for(@ui.move_most_ms)
  } else {
    // a mouse's: ⌘K, in every tier
    t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
    t.frame()
  }
  t.type_text(words)
  t.frame()
  t
}

///|
test "the search at each width and with either hand: the same words find the same chats and messages" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = finder_tester(w, platform, regular, "签名")
    let at = "\{w} platform \{platform}"
    assert_eq(@sfpages.finder_query(), "签名", msg=at)
    // (drawn over the list, the search's own: the last of the words)
    assert_true(t.find_last("签名证书续期") is Some(_), msg="\{at}: \{t.words().map(fn(x) { x.0 }).join("|")}")
    assert_true(t.find("消息") is Some(_), msg=at)
  }
}

///|
test "a chat the search found, pressed: its chat; ⌘K closed as it opens, the phone's page left under it" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = finder_tester(w, platform, regular, "签名")
    let at = "\{w} platform \{platform}"
    let wide = @sfdesk.is_wide(t.ctx())
    guard t.find_last("签名证书续期") is Some((x, y)) else {
      fail("\{at}: not found: \{t.words().map(fn(x) { x.0 }).join("|")}")
    }
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() is Chat(_), msg=at)
    ignore(wide)
    if platform == 2 {
      assert_true(@sfpages.search_opened(), msg=at)
    } else {
      assert_false(@sfdesk.switcher_open(), msg=at)
    }
  }
}


///|
/// The search's field at a list's top pressed (the list's, the leftmost drawn: the search's own page not open yet).
fn tap_search_field(t : @ui.Tester) -> Unit raise {
  guard t.find("搜索全部内容") is Some((x, y)) else { fail("no search field: \{t.words().map(fn(w) { w.0 }).join("|")}") }
  t.tap(x, y)
}

///|
test "the search's way in by the hand: a field at the lists' top in every tier with either input, ⌘K's too with a mouse" {
  for case in [(390.0, 2, false), (720.0, 2, false), (1280.0, 2, true), (390.0, 0, false), (720.0, 0, false), (1280.0, 0, false)] {
    let (w, platform, regular) = case
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=900.0, platform~)
    if regular {
      let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
      assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
    }
    t.draw()
    list_up_to_top(t)
    t.draw()
    let at = "\{w} platform \{platform}"
    assert_true(t.find("搜索全部内容") is Some(_), msg=at)
    if platform != 2 {
      t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
      t.frame()
      // laid out Small the search's page, else the panel
      let wide = @sfdesk.is_wide(t.ctx())
      assert_eq(@sfdesk.switcher_open(), wide, msg=at)
      assert_eq(@sfpages.search_opened(), !wide, msg=at)
    }
  }
}

///|
/// The search's field as drawn now (`editor`: the page's, its placeholder the same words, as the one seen while it is
/// open; else the list's): how big its words are and how high its capsule is.
fn search_field_drawn(t : @ui.Tester, editor : Bool) -> (Double, Double)? {
  // (the page's field an editor, its placeholder the words: as the frame lays it out, in its capsule)
  if editor {
    let bs = t.boxes()
    for b in bs {
      if b.kind == "editor" && (b.text == "搜索全部内容" || b.text == "搜索") && b.parent >= 0 {
        let mut p = b.parent
        while p >= 0 && bs[p].h < b.h + 1.0 {
          p = bs[p].parent
        }
        if p >= 0 {
          return Some((b.font_size, bs[p].h))
        }
      }
    }
  }
  // (the field drawn now, the last of them: the search's page over the list where it is open; its words' size and its
  // capsule's height, the first drawn round them with a ground)
  // (a field of the tree's found by its hint, its words' size its editor's: Tester::drawn_words_found)
  let drawn = t.drawn_words_found()
  let mut found : (Double, Double)? = None
  for d in drawn {
    let (n, holder, _, words, size) = d
    if n.alpha > 0.0 && (words == "搜索全部内容" || words == "搜索") {
      let mut h = holder
      while h >= 0 && drawn[h].0.ground == 0L {
        h = drawn[h].1
      }
      if h >= 0 {
        found = Some((size, drawn[h].0.h))
      }
    }
  }
  found
}

///|
test "a finger's search field comes up from the list and goes back as itself: its words as big, it as high, in every tier" {
  for case in [(390.0, false), (720.0, false), (1280.0, true)] {
    let (w, regular) = case
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=900.0, platform=2)
    if regular {
      let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
      assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
    }
    t.draw()
    list_up_to_top(t)
    t.draw()
    let at = w.to_string()
    guard search_field_drawn(t, false) is Some(list) else { fail("\{at}: no field in the list") }
    tap_search_field(t)
    t.run_for(@ui.move_most_ms)
    assert_eq(search_field_drawn(t, true), Some(list), msg="\{at}: come up: \{Repr(search_field_drawn(t, true))} for \{Repr(list)}")
    // 取消: on its way back, then the list's again, as it was
    guard t.find_last("取消") is Some((x, y)) else { fail("\{at}: no 取消") }
    t.tap(x, y)
    // (well within its way back: none is shorter than a Move of nothing far)
    t.run_for(@ui.move_least_ms / 2.0)
    assert_true(@sfpages.search_leaving(), msg=at)
    assert_eq(search_field_drawn(t, true), Some(list), msg="\{at}: going back")
    t.run_for(@ui.move_most_ms)
    t.draw()
    assert_false(@sfpages.search_opened(), msg=at)
    assert_eq(search_field_drawn(t, false), Some(list), msg="\{at}: back")
  }
}

///|
test "a finger's search on a wide frame: in the lists' column; a row pressed, its chat beside it, the search still there" {
  let t = finder_tester(1280.0, 2, true, "签名")
  // the results in the sidebar's column, left of the page
  let (x, _) = t.find_last("签名证书续期").unwrap()
  assert_true(x < 400.0, msg=x.to_string())
  assert_true(t.find("取消") is Some(_))
  let (x, y) = t.find_last("签名证书续期").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_))
  assert_true(@sfpages.search_opened())
  assert_true(t.find("取消") is Some(_))
}

///|
/// The fixture's Home in a desktop's window 390 wide (laid out Small, pointed at with a mouse).
fn small_mouse(calls : Array[Made]) -> @ui.Tester {
  let t = wide_tester(calls, w=390.0, h=844.0, platform=0)
  t.draw()
  t
}

///|
test "small with a mouse, ⌘K: the search's page in the lists' box, the keys in its field; Enter opens the line chosen, Esc closes it" {
  let calls : Array[Made] = []
  let t = small_mouse(calls)
  assert_false(@sfdesk.is_wide(t.ctx()))
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfpages.search_opened())
  assert_false(@sfdesk.switcher_open())
  // the lists gone from under it, as under a finger's (not seen through its rows)
  // (the list's row there unseen; the same chat among what the search offers, seen)
  let rows = t.words().filter(fn(x) { x.0 == "整理发布清单" }).map(fn(x) { x.5 })
  assert_true(rows.iter().any(fn(a) { a < 0.01 }), msg=Repr(rows).to_string())
  // what can be done here among what it finds: 设置 with its keys, Enter runs it
  t.type_text("设置")
  t.frame()
  assert_true(t.find("⌘,") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.enter()
  t.frame()
  assert_true(app.nav.top() == Settings)
  // a chat found: Enter opens it
  let t = small_mouse(calls)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  t.type_text("签名")
  t.frame()
  assert_true(t.find_last("签名证书续期") is Some(_))
  // Enter: the line chosen (the first) opened
  t.enter()
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_))
  // Esc on Home's: closed, the lists as they were
  let t = small_mouse(calls)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfpages.search_opened())
  t.key(@ui.key_escape)
  t.frame()
  assert_false(@sfpages.search_opened())
  assert_true(app.nav.top() == Home)
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
test "small with a mouse, ⌘K in a chat: the search's page over it; Esc back to that chat, a row found its chat instead" {
  let calls : Array[Made] = []
  let t = small_mouse(calls)
  t.tap_text("夜里的构建又失败了")
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 2)
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfpages.search_opened())
  t.type_text("签名")
  t.frame()
  assert_true(t.find_last("签名证书续期") is Some(_))
  // Esc: closed, the chat under it as it was
  t.key(@ui.key_escape)
  t.frame()
  assert_false(@sfpages.search_opened())
  assert_eq(app.nav.depth(), 2)
  assert_true(app.nav.top() is Chat({ title: "夜里的构建又失败了", .. }))
  // again, a row pressed: its chat over this one, the search gone
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.frame()
  t.type_text("签名")
  t.frame()
  let (x, y) = t.find_last("签名证书续期").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_false(@sfpages.search_opened())
  assert_true(app.nav.top() is Chat({ title: "签名证书续期", .. }))
  // (the search's field gone with it at that press: the chat come's field with the focus as it comes, as any chat
  // opened with a keyboard; what is typed goes into it, none into the search no longer shown)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg=t.focus_said())
  t.type_text("新")
  assert_true(
    t.semantics().iter().any(fn(s) { s.role == TextField && s.label == "发消息" && s.value == "新" && s.focused }),
    msg=t.focus_said(),
  )
}

///|
test "small with a mouse, the app's keys: ⌘N a new chat; ⌘, settings; ⌘/ the shortcuts" {
  let calls : Array[Made] = []
  // ⌘N: a new chat, risen on the stack
  let t = small_mouse(calls)
  t.key(@ui.key_of_char('n'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(app.nav.top() == NewChat)
  // ⌘,: settings, their list's page
  let t = small_mouse(calls)
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.frame()
  assert_true(app.nav.top() == Settings)
  // ⌘/: the shortcuts
  let t = small_mouse(calls)
  t.key(@ui.key_of_char('/'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(@sfdesk.wide.keys_open.get())
}

///|
test "⌘K laid out Medium and Large: its panel, room round it on every side" {
  for w in [600.0, 1280.0] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, w~, h=800.0, platform=0)
    t.draw()
    assert_true(@sfdesk.is_wide(t.ctx()), msg=w.to_string())
    t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
    t.frame()
    assert_true(@sfdesk.switcher_open(), msg=w.to_string())
    assert_false(@sfpages.search_opened(), msg=w.to_string())
    let c = t.ctx()
    let (x, y, pw, _) = c.rect_of(c.id("switcher")).unwrap()
    assert_true(x >= 16.0 && x + pw <= w - 16.0 && y > 0.0, msg="\{w}: \{x} \{pw}")
  }
}

///|
test "⌘K's scrolling results reach its curved foot and fade towards it" {
  for width in [600.0, 1280.0] {
    let height = 180.0
    let calls : Array[Made] = []
    // A short window cuts the first, initially selected result partway through, without moving the pointer.
    let t = wide_tester(calls, w=width, h=height, platform=0)
    t.draw()
    t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
    t.run_for(@ui.move_most_ms)
    let c = t.ctx()
    let (px, py, pw, ph) = c.rect_of(c.id("switcher")).unwrap()
    let lists = t.boxes().filter(fn(b) { b.kind == "list" && b.w > pw * 0.8 && b.x >= px && b.x + b.w <= px + pw && b.y >= py && b.y < py + ph })
    assert_eq(lists.length(), 1, msg="\{width}: lists")
    let list = lists[0]
    let foot = list.y + list.h
    let rows = t.drawn_instances().filter(fn(a) {
      a[5] == 0.0 && (a[0] - list.x).abs() < 0.5 && (a[2] - list.w).abs() < 0.5 && a[1] < foot && a[1] + a[3] > foot
    })
    assert_eq(rows.length(), 1, msg="\{width}x\{height}: a selected row crosses the foot")
    let row = rows[0]
    // The viewport reaches the panel's edge; the panel itself cuts its contents to its outline.
    assert_true((foot - (py + ph)).abs() < 0.5, msg="\{width}: list ends at \{foot}, panel at \{py + ph}")
    assert_true(corner_cover(row, list.x + list.w / 2.0, foot - 2.0, 2.0) > 0.9, msg="\{width}: middle")
    let panels = t.boxes().filter(fn(b) { (b.x - px).abs() < 0.5 && (b.y - py).abs() < 0.5 && (b.w - pw).abs() < 0.5 && b.border_w > 0.0 })
    assert_eq(panels.length(), 1, msg="\{width}: panel")
    let inset = list.x - px
    // (cut at the panel's own edge: its line takes no room and is drawn over what it holds)
    let r = panels[0].radius
    // Its colour fades per pixel to the foot; the panel and its border stay whole.
    assert_true((row[54] - foot).abs() < 0.5 && (row[55] - inset).abs() < 0.5, msg="\{width}: fade \{row[54]}, \{row[55]}")
    let cover = fn(d : Double) { dmax(0.0, dmin(1.0, 0.5 - d * 2.0)) }
    for x0 in [list.x, list.x + list.w - 22.0] {
      for i in 0..<44 {
        for j in 0..<44 {
          let x = x0 + (i.to_double() + 0.5) / 2.0
          let y = foot - 22.0 + (j.to_double() + 0.5) / 2.0
          let own = cover(@ui.sd_box(x - (row[0] + row[2] / 2.0), y - (row[1] + row[3] / 2.0), row[2] / 2.0, row[3] / 2.0, row[4]))
          let inside = cover(@ui.sd_clip(x, y, px, py, px + pw, py + ph, (r, r, r, r), (1.0, 1.0, 1.0, 1.0)))
          let have = corner_cover(row, x, y, 2.0)
          assert_true((have - own * inside).abs() < 0.06, msg="\{width}x\{height}: (\{x}, \{y}) covers \{have}, expected \{own * inside}")
        }
      }
    }
  }
}

///|
test "⌘K: the pointer going down its rows leaves only the one under it shown chosen, none behind it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, w=1280.0, h=900.0, platform=0)
  t.draw()
  t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let c = t.ctx()
  let (px, py, pw, ph) = c.rect_of(c.id("switcher")).unwrap()
  let lists = t.boxes().filter(fn(b) { b.kind == "list" && b.w > pw * 0.8 && b.x >= px && b.x + b.w <= px + pw && b.y >= py && b.y < py + ph })
  assert_eq(lists.length(), 1, msg="lists")
  let list = lists[0]
  // the grounds drawn as wide as the list: the rows shown chosen, each at its top
  let chosen = fn() {
    t.drawn_instances().filter(fn(a) { a[5] == 0.0 && (a[0] - list.x).abs() < 0.5 && (a[2] - list.w).abs() < 0.5 }).map(fn(a) { a[1] })
  }
  let first = chosen()
  assert_eq(first.length(), 1, msg="as it opens")
  for k in 0..<4 {
    let y = first[0] + @sf.theme().chat_list.found.row_h * (k.to_double() + 0.5)
    t.move_to(list.x + list.w / 2.0, y)
    t.run_for(@ui.move_most_ms)
    let rows = chosen()
    assert_eq(rows.length(), 1, msg="the pointer on row \{k}: \{Repr(rows)}")
    assert_true(rows[0] <= y && y < rows[0] + @sf.theme().chat_list.found.row_h, msg="the pointer at \{y}: \{Repr(rows)}")
  }
}

///|
test "⌘K at its end leaves its last result as far from the foot as from the sides" {
  for width in [600.0, 1280.0] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, w=width, h=800.0, platform=0)
    t.draw()
    t.key(@ui.key_of_char('k'), mods=@ui.mod_cmd)
    t.run_for(@ui.move_most_ms)
    let c = t.ctx()
    let (px, py, pw, ph) = c.rect_of(c.id("switcher")).unwrap()
    let lists = t.boxes().filter(fn(b) { b.kind == "list" && b.w > pw * 0.8 && b.x >= px && b.x + b.w <= px + pw && b.y >= py && b.y < py + ph })
    assert_eq(lists.length(), 1, msg="\{width}: list")
    let list = lists[0]
    t.wheel(list.x + list.w / 2.0, list.y + list.h / 2.0, 3000.0)
    t.run_for(@ui.move_most_ms)
    let children = t.boxes().filter(fn(b) { b.parent == list.index })
    assert_true(children.length() >= 2, msg="\{width}: last row and its foot")
    let last = children[children.length() - 2]
    let blank = children[children.length() - 1]
    let inset = list.x - px
    assert_true(((last.y + last.h) - (py + ph - inset)).abs() < 0.5, msg="\{width}: last result ends at \{last.y + last.h}, panel at \{py + ph}")
    assert_true((blank.h - inset).abs() < 0.5, msg="\{width}: foot room \{blank.h}, side room \{inset}")
  }
}

///|
test "small with a mouse: back (⌘[, the keymap's nav.back) goes back one page only; forward (⌘]) brings it again" {
  let calls : Array[Made] = []
  let t = small_mouse(calls)
  t.tap_text("夜里的构建又失败了")
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 2)
  let chat = app.nav.top()
  // ⌘[: the system's back, once (Ctx::back: the stack's, as a back key's)
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 1)
  // ⌘]: what back took off, put back
  t.key(@ui.key_of_char(']'), mods=@ui.mod_cmd)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 2)
  assert_true(app.nav.top() == chat)
  // forward again: nothing more to bring
  t.key(@ui.key_of_char(']'), mods=@ui.mod_cmd)
  t.frame()
  assert_eq(app.nav.depth(), 2)
  // the system's back (a mouse's back button), then a mouse's forward button (the hosts' key_forward)
  t.back()
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 1)
  t.key(@ui.key_forward)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == chat)
}

///|
test "wide, back then forward: the chat back took off comes again; a page opened since, forward brings nothing" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.draw()
  t.tap_text("整理发布清单")
  t.frame()
  let chat = app.nav.top()
  assert_true(chat is Chat({ title: "整理发布清单", .. }))
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.frame()
  assert_false(app.nav.top() == chat)
  t.key(@ui.key_of_char(']'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(app.nav.top() == chat)
  // back, then another page opened (settings): what back took is forgotten
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.frame()
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.frame()
  let pages = app.nav.pages()
  t.key(@ui.key_forward)
  t.frame()
  assert_true(app.nav.pages() == pages)
}

///|
test "wide, chats chosen one after another beside the sidebar: back goes to the chat shown before, forward again" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.draw()
  t.tap_text("整理发布清单")
  t.frame()
  let first = app.nav.top()
  t.tap_text("夜里的构建又失败了")
  t.frame()
  let second = app.nav.top()
  assert_true(second is Chat({ title: "夜里的构建又失败了", .. }))
  // back: the chat shown before, in its place (the list and it alone on the stack)
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.frame()
  assert_true(app.nav.pages() == [Home, first])
  // forward: the chat back went from
  t.key(@ui.key_of_char(']'), mods=@ui.mod_cmd)
  t.frame()
  assert_true(app.nav.pages() == [Home, second])
  // back twice: the first chat, then what is under it (none shown before it: a new chat beside the list)
  t.back()
  t.frame()
  assert_true(app.nav.top() == first)
  t.back()
  t.frame()
  assert_true(app.nav.top() == NewChat)
}

///|
test "wide, another workspace switched to: back brings the first workspace again with its chat, forward the second" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.draw()
  t.tap_text("整理发布清单")
  t.frame()
  let chat = app.nav.pages()
  assert_true(app.nav.top() is Chat({ title: "整理发布清单", .. }))
  // ⌃2: the second workspace, its own page beside its chats
  t.key(@ui.key_of_char('2'), mods=@ui.mod_ctrl)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.picked.get(), "ws2")
  let second = app.nav.pages()
  assert_false(second == chat)
  // back: the first workspace in view again (the prefs told), the chat in its place
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.picked.get(), "ws1")
  assert_true(app.nav.pages() == chat)
  assert_true(named(calls, "prefs.set").last().map(fn(m) { text(Some(m.params), "workspace") }) == Some("ws1"))
  // forward: the second again, as it was
  t.key(@ui.key_of_char(']'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.picked.get(), "ws2")
  assert_true(app.nav.pages() == second)
}

///|
test "wide, settings opened from a chat, then another chat: back goes through each place, forward again" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.draw()
  t.tap_text("整理发布清单")
  t.frame()
  let first = app.nav.pages()
  // 设置 (⌘,), then a chat chosen from the list again
  t.key(@ui.key_of_char(','), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let settings = app.nav.pages()
  assert_false(settings == first)
  @sfbase.go_place("chats") |> ignore
  t.run_for(@ui.move_most_ms)
  t.tap_text("夜里的构建又失败了")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat({ title: "夜里的构建又失败了", .. }))
  // back: the chats gone to (a new chat beside them), settings, then the first chat
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.pages() == [Home, NewChat])
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.pages() == settings)
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.pages() == first)
  t.key(@ui.key_of_char(']'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.pages() == settings)
}

///|
test "wide, the chat shown chosen again: no entry of its own; what the frame lands on alone, none either" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.draw()
  // (landed beside the chats as the app opens: no person's act, so nothing to go back to)
  assert_false(@sfbase.back_step() is Some(_))
  let landed = app.nav.pages()
  t.tap_text("整理发布清单")
  t.frame()
  t.tap_text("整理发布清单")
  t.frame()
  t.key(@ui.key_of_char('['), mods=@ui.mod_cmd)
  t.frame()
  assert_true(app.nav.pages() == landed)
}

///|
/// A finger's tap at (x, y) on a phone's Home just shown (its search tucked under the top bar), the press done with:
/// whether it opened the search.
fn tucked_tap(x : Double, y : Double) -> Bool {
  let t = screen_in("home", corner_windows[0], "zh")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  @sfpages.search_opened()
}

///|
test "a phone's Home: its search tucked under the top bar out of sight takes no finger, below the bar's keys nor on the bar between them; scrolled into sight, it does" {
  let t = screen_in("home", corner_windows[0], "zh")
  let tree = @ui.view_tree().unwrap()
  let boxes = tree.press_boxes()
  let named = fn(b : (@view.NodeId, (Double, Double, Double, Double), Int, Int)) {
    match tree.said_of(b.0) {
      Some(s) => s.label
      None => ""
    }
  }
  // (found as a screen reader finds it: what takes presses where it is found does not count it, tucked)
  let (fx, fy, fw, fh) = t.get(Button, label="搜索全部内容").rect
  let field = (fx, fy, fx + fw, fy + fh)
  // (the bar's keys: what takes presses whose top is above the field's foot, the field's line under them)
  let keys = boxes.filter(fn(b) { b.1.1 < field.3 && named(b) != "搜索全部内容" }).map(fn(b) { (named(b), b.1) })
  assert_true(keys.length() >= 3, msg="the bar's keys: \{Repr(keys)}")
  // (tucked: its foot no lower than the bar's keys' feet are, past them by 8)
  let bar_foot = keys.fold(init=0.0, fn(m, k) { if k.1.3 > m { k.1.3 } else { m } })
  assert_true(field.3 <= bar_foot + 8.0, msg="tucked: the field \{Repr(field)}, the keys' foot \{bar_foot}")
  // (the bar between its keys, a finger's room clear of each, at its keys' middle line: the first such place over the
  // field's middle third)
  let my = (keys[0].1.1 + keys[0].1.3) / 2.0
  let mut clear : Double? = None
  let mut x = field.0 + (field.2 - field.0) / 3.0
  while x < field.2 && clear is None {
    if keys.iter().all(fn(k) { x < k.1.0 - 22.0 || x > k.1.2 + 22.0 }) {
      clear = Some(x)
    }
    x += 2.0
  }
  // (read all of this one before the next is made)
  assert_false(@sfpages.search_opened(), msg="open as Home shows")
  ignore(t)
  for k in keys {
    let (name, (x0, _, x1, y1)) = k
    for d in [1.0, 7.0] {
      assert_false(tucked_tap((x0 + x1) / 2.0, y1 + d), msg="\{d} below \{name} at \{Repr(k.1)}")
    }
  }
  match clear {
    Some(x) => assert_false(tucked_tap(x, my), msg="on the bar at \{x},\{my}")
    None => ()
  }
  // (scrolled down into sight under the bar: pressed, it opens the search)
  let t = screen_in("home", corner_windows[0], "zh")
  list_up_to_top(t)
  t.draw()
  tap_search_field(t)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfpages.search_opened(), msg="the field in sight, pressed")
}
