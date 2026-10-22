// The menus' page (Radix's third batch): a menu's panel drawn by its looks where it stands (one item lit, a submenu's,
// checked and chosen items, a disabled one), a select's trigger, a menubar and a toolbar; then the menus live.

///|
let fruit : Array[String] = ["", ""]

///|
let bookmarks : Array[Bool] = [true, true]

///|
let file_open : Array[Bool] = [false, false]

///|
fn menus(c : @ui.Ctx) -> Unit {
  let t = c.theme()
  let h = if t.dark { 1 } else { 0 }
  // MBUI_OPEN=menu: the light half's file menu open as the page first shows (a screenshot of it in place)
  if !opened_env.val && h == 0 {
    opened_env.val = true
    if @ui.env("MBUI_OPEN") == "menu" {
      file_open[0] = true
    }
  }
  section(c, "Dropdown menu", fn() {
    c.box(dir=Row, gap=12.0, align=AStart, fn() {
      @kit.menu_look(c, 200.0, fn() {
        let row = fn(e : @kit.Entry, lit : Bool, open : Bool) { @kit.menu_item_look(c, { entry: e, lit, open }) }
        row(@kit.menu_label("File"), false, false)
        row(@kit.menu_item("new", label="New tab", shortcut="⌘T"), true, false)
        row(@kit.menu_item("private", label="Private window", disabled=true), false, false)
        c.box(pady=6.0, padx=4.0, fn() {
          c.box(h=Px(1.0), w=Fill(1.0), bg=@ui.alpha(t.fg, 0.12), fn() {  }) |> ignore
        })
        |> ignore
        row(@kit.menu_sub("Share", []), false, true)
        row(@kit.menu_check("bar", true, label="Show bookmarks"), false, false)
        row(@kit.menu_radio("m", true, label="Medium"), false, false)
      })
      c.box(gap=12.0, fn() {
        c.box(w=Px(200.0), fn() {
          @kit.select_look(c, {
            text: "Banana",
            placeholder: false,
            open: false,
            hovered: false,
            focus_shown: false,
            disabled: false,
            rect: (0.0, 0.0, 0.0, 0.0),
          })
        })
        |> ignore
        c.box(w=Px(200.0), fn() {
          @kit.select_look(c, {
            text: "Pick a fruit",
            placeholder: true,
            open: false,
            hovered: false,
            focus_shown: false,
            disabled: false,
            rect: (0.0, 0.0, 0.0, 0.0),
          })
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  section(c, "Menubar, navigation menu and toolbar", fn() {
    @kit.menubar(c, "bar", [
      ("File", [@kit.menu_item("new", label="New"), @kit.menu_item("open", label="Open…", shortcut="⌘O")]),
      ("Edit", [@kit.menu_item("undo", label="Undo", shortcut="⌘Z"), @kit.menu_item("redo", label="Redo")]),
      ("View", [@kit.menu_check("side", bookmarks[h], label="Sidebar")]),
    ])
    |> ignore
    @kit.navigation_menu(c, "nav", [
      @kit.nav_trigger("Learn", fn() { c.text("Guides and tutorials", size=t.font) |> ignore }),
      @kit.nav_trigger("Overview", fn() { c.text("What it is", size=t.font) |> ignore }),
      @kit.nav_link("github", label="GitHub"),
    ])
    |> ignore
    @kit.toolbar(c, "tools", label="Format", fn() {
      @kit.toggle(c, "B", true, key="tb-b") |> ignore
      @kit.toggle(c, "I", false, key="tb-i") |> ignore
      @kit.toggle(c, "U", false, key="tb-u") |> ignore
      @kit.separator(c, vertical=true)
      @kit.button(c, "Share", key="tb-share", variant=Ghost) |> ignore
    })
  })
  section(c, "Live", fn() {
    line(c, fn() {
      let tr = @kit.button(c, "File", key="file", variant=Outline)
      if tr.clicked {
        file_open[h] = !file_open[h]
      }
      let m = @kit.dropdown_menu(
        c,
        "file-menu",
        file_open[h],
        tr.id,
        [
          @kit.menu_item("new", label="New tab", shortcut="⌘T"),
          @kit.menu_item("window", label="New window"),
          @kit.menu_separator(),
          @kit.menu_sub("Share", [@kit.menu_item("mail", label="Email link"), @kit.menu_item("copy", label="Copy link")]),
          @kit.menu_check("bar", bookmarks[h], label="Show bookmarks"),
        ],
        label="File",
      )
      file_open[h] = m.open
      if m.chosen == Some("bar") {
        bookmarks[h] = !bookmarks[h]
      }
      c.box(w=Px(180.0), fn() {
        fruit[h] = @kit.select(
            c,
            "fruit",
            fruit[h],
            [@kit.item("a", label="Apple"), @kit.item("b", label="Banana"), @kit.item("c", label="Cherry")],
            placeholder="Pick a fruit",
            w=180.0,
            label="Fruit",
          ).value
      })
      |> ignore
      let area = c.id("area")
      c.box(id=area, padx=12.0, h=Px(t.control_h), justify=JCenter, radius=t.radius, border=1.0, border_color=t.line, fn() {
        c.text("Right click", size=t.font, color=t.muted, wrap=false) |> ignore
      })
      |> ignore
      @kit.context_menu(c, "ctx", area, [@kit.menu_item("cut", label="Cut"), @kit.menu_item("paste", label="Paste")])
      |> ignore
    })
  })
}
