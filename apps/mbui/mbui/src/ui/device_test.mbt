///|
/// A page with a key catcher, given the focus while `on`: what it caught, frame by frame, into `got` (told once a
/// frame, whichever of its builds read it).
fn catcher_page(got : Array[@ui.KeyIn], on : Ref[Bool]) -> (@ui.Ctx) -> Unit {
  fn(c) {
    c.catch_keys("keys", on.val)
    let k = c.key_catcher("keys")
    if k.keys.length() > 0 {
      let keys = k.keys
      c.tell("caught", fn() { got.append(keys) })
    }
    c.column(fn() {
      c.text(if k.focused { "typing" } else { "idle" }, wrap=false) |> ignore
      c.text(if c.keyboard_up() { "keyboard up" } else { "keyboard down" }, wrap=false) |> ignore
    })
    |> ignore
  }
}

///|
fn tap(key : String, code : String, mods : Int) -> Array[@ui.KeyIn] {
  [Key(down=true, key~, code~, mods~), Key(down=false, key~, code~, mods~)]
}

///|
test "a key catcher takes the keyboard with no text of its own: committed words as text, Enter between lines" {
  let got : Array[@ui.KeyIn] = []
  let on = Ref::new(true)
  let t = @ui.Tester::new(catcher_page(got, on))
  t.draw()
  assert_true(t.find("typing") is Some(_))
  // the host told: the keyboard is a catcher's, its input method on with no text
  assert_true(t.key_catching())
  let (active, text, a, b) = t.ime()
  assert_true(active)
  assert_eq(text, "")
  assert_eq((a, b), (0, 0))
  t.type_text("ab\ncd")
  let want : Array[@ui.KeyIn] = [Text("ab")]
  want.append(tap("Enter", "Enter", 0))
  want.push(Text("cd"))
  assert_eq(got, want)
  // a line's end alone: Enter
  got.clear()
  t.type_text("\n")
  assert_eq(got, tap("Enter", "Enter", 0))
  // let go: the host told so, its input method off
  on.val = false
  t.draw()
  assert_false(t.key_catching())
  assert_false(t.ime().0)
  assert_true(t.find("idle") is Some(_))
  t.assert_idle()
}

///|
test "what the input method composes is sent once committed or finished; deleting shortens it while it composes" {
  let got : Array[@ui.KeyIn] = []
  let on = Ref::new(true)
  let t = @ui.Tester::new(catcher_page(got, on))
  t.draw()
  t.compose("ni")
  t.compose("nihao")
  assert_eq(got, [])
  // committed: its words, not the composition's
  t.type_text("你好")
  assert_eq(got, [Text("你好")])
  got.clear()
  t.compose("shijie")
  t.ime_delete(2, 0)
  assert_eq(got, [])
  t.ime_finish()
  assert_eq(got, [Text("shij")])
  // nothing composed: deleting is Backspace and Delete taps, as many as asked (an empty catcher deletes on the screen)
  got.clear()
  t.ime_delete(2, 1)
  let want = tap("Backspace", "Backspace", 0)
  want.append(tap("Backspace", "Backspace", 0))
  want.append(tap("Delete", "Delete", 0))
  assert_eq(got, want)
  // finished with nothing composed: nothing
  got.clear()
  t.ime_finish()
  assert_eq(got, [])
  t.assert_idle()
}

///|
test "a key catcher's keys: named keys as taps, a character with Ctrl, Alt or Cmd as its key, modifiers as a screen's" {
  let got : Array[@ui.KeyIn] = []
  let on = Ref::new(true)
  let t = @ui.Tester::new(catcher_page(got, on))
  t.draw()
  t.backspace()
  t.key(@ui.key_escape)
  t.key(@ui.key_tab, mods=@ui.mod_shift_key)
  t.key(@ui.key_code_page_down)
  t.key(@ui.key_space)
  let want = tap("Backspace", "Backspace", 0)
  want.append(tap("Escape", "Escape", 0))
  want.append(tap("Tab", "Tab", @ui.key_in_shift))
  want.append(tap("PageDown", "PageDown", 0))
  want.append(tap(" ", "Space", 0))
  assert_eq(got, want)
  got.clear()
  // Ctrl+C, Ctrl+Shift+C, Cmd+1, Alt+-
  t.key(@ui.key_of_char('c'), mods=@ui.mod_ctrl)
  t.key(@ui.key_of_char('c'), mods=@ui.mod_ctrl | @ui.mod_shift_key)
  t.key(@ui.key_of_char('1'), mods=@ui.mod_cmd)
  t.key(@ui.key_of_char('-'), mods=@ui.mod_alt)
  let want = tap("c", "KeyC", @ui.key_in_ctrl)
  want.append(tap("C", "KeyC", @ui.key_in_ctrl | @ui.key_in_shift))
  want.append(tap("1", "Digit1", @ui.key_in_meta))
  want.append(tap("-", "Minus", @ui.key_in_alt))
  assert_eq(got, want)
  // none of them moved the focus (Tab) or reached the page's own keys
  assert_true(t.find("typing") is Some(_))
  t.assert_idle()
}

///|
test "a key catcher's keys are the same in every build of their frame and gone the frame after" {
  let seen : Array[Int] = []
  let on = Ref::new(true)
  let t = @ui.Tester::new(fn(c) {
    c.catch_keys("keys", on.val)
    let k = c.key_catcher("keys")
    seen.push(k.keys.length())
    // read twice in a build: the same
    if c.key_catcher("keys").keys.length() != k.keys.length() {
      seen.push(-1)
    }
  })
  t.draw()
  seen.clear()
  t.type_text("x")
  assert_true(seen.contains(1))
  seen.clear()
  t.frame()
  assert_eq(seen, [0])
}

///|
test "a press elsewhere leaves a key catcher the focus, as a field's" {
  let got : Array[@ui.KeyIn] = []
  let on = Ref::new(true)
  let t = @ui.Tester::new(catcher_page(got, on))
  t.draw()
  t.tap(200.0, 600.0)
  assert_true(t.find("typing") is Some(_))
  t.type_text("y")
  assert_eq(got, [Text("y")])
}

///|
test "a field takes the input method's deleting as its Backspace" {
  let t = @ui.Tester::new(fn(c) { c.editor("f") |> ignore })
  t.draw()
  t.tap(100.0, 20.0)
  t.type_text("abc")
  assert_eq(t.field_words(), "abc")
  t.ime_delete(1, 0)
  assert_eq(t.field_words(), "ab")
}

///|
test "the soft keyboard's height: read as each frame begins, kept on the tape and given again" {
  let got : Array[@ui.KeyIn] = []
  let on = Ref::new(true)
  let t = @ui.Tester::new(catcher_page(got, on))
  t.start_tape()
  let begun = t.time()
  t.frame()
  assert_true(t.find("keyboard down") is Some(_))
  t.set_ime_inset(291.5)
  t.frame()
  assert_true(t.find("keyboard up") is Some(_))
  t.set_ime_inset(0.0)
  t.frame()
  t.set_ime_inset(120.0)
  t.frame()
  let tape = t.tape()
  assert_true(tape.contains("\"ime\":291.5"))
  let u = @ui.Tester::new(catcher_page([], Ref::new(true)), time=begun)
  let frames = u.replay_frames(tape)
  assert_true(frames.length() >= 4)
  for f in frames {
    assert_eq(f.1, f.2, msg="frame \{f.0}")
  }
  assert_true(u.find("keyboard up") is Some(_))
}

///|
/// A page that reads the clipboard when `ask` is set, keeping what it took.
fn paste_page(ask : Ref[Bool], took : Ref[@ui.Clipboard?]) -> (@ui.Ctx) -> Unit {
  let read : Ref[@ui.ClipboardRead?] = Ref::new(None)
  fn(c) {
    if ask.val {
      ask.val = false
      c.tell("read", fn() { read.val = @ui.clipboard_read() })
    }
    match read.val {
      Some(r) =>
        match r.got() {
          Some(clip) => {
            took.val = Some(clip)
            read.val = None
          }
          None => ()
        }
      None => ()
    }
    c.text(
      match took.val {
        Some({ text, .. }) => "pasted " + text
        None => "nothing"
      },
      wrap=false,
    )
    |> ignore
  }
}

///|
test "the clipboard read is waited on until the test gives it, taken the frame after" {
  let ask = Ref::new(false)
  let took : Ref[@ui.Clipboard?] = Ref::new(None)
  let t = @ui.Tester::new(paste_page(ask, took))
  ask.val = true
  t.draw()
  assert_eq(t.clipboard_reads(), 1)
  // not given: awaited, not at rest
  assert_false(t.at_rest())
  assert_true(t.awaited().iter().any(fn(a) { a.contains("the clipboard read") }))
  t.clipboard_gives("hello")
  t.draw()
  assert_eq(took.val, Some({ text: "hello", picture: NoPicture, files: [] }))
  assert_true(t.find("pasted hello") is Some(_))
  assert_true(t.at_rest())
  // a picture (with words beside it), given before the app asks: its next read's
  took.val = None
  t.clipboard_gives_png(b"\x89PNG\r\n\x1a\nxx", text="caption")
  ask.val = true
  t.draw()
  assert_eq(took.val, Some({ text: "caption", picture: Png(b"\x89PNG\r\n\x1a\nxx"), files: [] }))
  // one too large
  took.val = None
  ask.val = true
  t.draw()
  t.clipboard_gives_clip({ text: "", picture: TooLarge, files: [] })
  t.draw()
  assert_eq(took.val, Some({ text: "", picture: TooLarge, files: [] }))
  // files (as Finder copies them: their names beside)
  took.val = None
  ask.val = true
  t.draw()
  t.clipboard_gives_files([("plan.pdf", b"%PDF-1.7")], text="plan.pdf")
  t.draw()
  assert_eq(took.val, Some({ text: "plan.pdf", picture: NoPicture, files: [("plan.pdf", b"%PDF-1.7")] }))
  t.assert_idle()
}

///|
test "the clipboard as the app took it is kept on the tape and given again to a Tester replaying it" {
  let ask = Ref::new(false)
  let took : Ref[@ui.Clipboard?] = Ref::new(None)
  let t = @ui.Tester::new(paste_page(ask, took))
  t.start_tape()
  let begun = t.time()
  t.frame()
  ask.val = true
  t.draw()
  t.clipboard_gives_clip({
    text: "a\nb",
    picture: Png(b"\x89PNG\r\n\x1a\n01"),
    files: [("plan.pdf", b"%PDF-1.7"), ("a b.txt", b"")],
  })
  t.draw()
  t.frame()
  let tape = t.tape()
  assert_true(tape.contains("CLIPSAID "))
  // replayed with no clipboard given: the run's
  let ask2 = Ref::new(false)
  let took2 : Ref[@ui.Clipboard?] = Ref::new(None)
  let u = @ui.Tester::new(paste_page(ask2, took2), time=begun)
  // (the app's own ask, at its place: as the run's view asked it as its first frame after the tape began)
  ask2.val = true
  let frames = u.replay_frames(tape)
  for f in frames {
    assert_eq(f.1, f.2, msg="frame \{f.0}")
  }
  assert_eq(
    took2.val,
    Some({
      text: "a\nb",
      picture: Png(b"\x89PNG\r\n\x1a\n01"),
      files: [("plan.pdf", b"%PDF-1.7"), ("a b.txt", b"")],
    }),
  )
}

///|
test "what the app writes, keeps awake and fires is the test's to read" {
  let go = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      if go.val {
        go.val = false
        c.tell("effects", fn() {
          @ui.clipboard_set("words", label="Screen")
          @ui.clipboard_set_png(b"\x89PNG\r\n\x1a\n", label="Screen 2")
          @ui.keep_awake(true)
          @ui.haptic(LongPress)
          @ui.haptic(ContextClick)
          @ui.haptic(TextHandleMove)
        })
      }
      c.text(if @ui.copy_shown() { "shown" } else { "say it" }, wrap=false) |> ignore
    },
    copy_shown=true,
  )
  assert_true(t.find("shown") is Some(_))
  assert_false(t.awake())
  go.val = true
  t.draw()
  // the picture last: in place of the words
  assert_eq(t.clipboard_png(), Some(b"\x89PNG\r\n\x1a\n"))
  assert_eq(t.clipboard(), "")
  assert_eq(t.clipboard_label(), "Screen 2")
  assert_true(t.awake())
  assert_eq(t.haptics(), [LongPress, ContextClick, TextHandleMove])
  let u = @ui.Tester::new(fn(c) {
    c.text(if @ui.copy_shown() { "shown" } else { "say it" }, wrap=false) |> ignore
  })
  assert_true(u.find("say it") is Some(_))
}

///|
test "what is copied is felt, once a copy; with haptics off nothing is" {
  let copy = Ref::new(0)
  let t = @ui.Tester::new(fn(c) {
    if copy.val > 0 {
      copy.val -= 1
      c.copy_text("words")
    }
    c.text("x", wrap=false) |> ignore
  })
  copy.val = 1
  t.draw()
  assert_eq(t.clipboard(), "words")
  assert_eq(t.haptics(), [KeyboardTap])
  @ui.set_haptics(false)
  copy.val = 1
  t.draw()
  @ui.haptic(LongPress)
  assert_eq(t.haptics(), [KeyboardTap])
  // (on again, as a new test's Tester has them)
  @ui.set_haptics(true)
  @ui.haptic(LongPress)
  assert_eq(t.haptics(), [KeyboardTap, LongPress])
}
