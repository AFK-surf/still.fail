// The vault client (docs/vault.md: still.fail's vault as agents use it, laid out as 1Password is): the app signed in
// and started as the vault (sfbase's vault_app), the workspace in view's vaults. What has to come first (security
// mode, this device trusted, the vault turned on here, the recovery words written down, this device given the keys)
// a card alone in the window's middle. Then, by the screen: 大屏 the sidebar (现在, every item, each kind, each vault,
// 锁定 at its foot), the list of what it picked with its search over it, and the item shown, or 现在 (the requests
// waiting on the person, the grants agents hold, the latest uses) where the sidebar picked it; 中屏 the list and the
// item, the sidebar's picks as chips over the list; 小屏 the list, the item over it as a page of its own. Made once
// (mbui's view: mbui/docs/retained.md), each part bound to the core's topics through State (state.mbt).

///|
fn p() -> @sf.Palette {
  @sf.theme().p
}

///|
fn look(size : Double, weight : Int, line : Double, wrap? : Bool = false) -> @view.WordsLook {
  { size, weight, line, wrap, tracking: @view.letters_own, balance: false }
}

///|
/// Words in `parent`, `words` as they are now, `size` on `line` in `weight`, in `ink`; cut short past their room
/// unless they wrap.
fn text(
  parent : @view.View,
  words : () -> String,
  size : Double,
  ink : () -> Int64,
  weight? : Int = 400,
  line? : Double,
  wrap? : Bool = false,
) -> @view.View {
  let line = line.unwrap_or((size * 1.45).round())
  parent.box(fn(w) {
    w.words(By(words), look=look(size, weight, line, wrap~)).ink(By(ink)).min_width(Is(Some(0.0))) |> ignore
    if !wrap {
      w.ellipsis_past(Is(true)) |> ignore
    }
  })
}

///|
fn gap(parent : @view.View, h : Double) -> Unit {
  parent.box(fn(g) { g.height(Is(Some(h))) |> ignore }) |> ignore
}

///|
fn grow(parent : @view.View) -> Unit {
  parent.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
}

///|
/// A line between two rows of a card.
fn rule(parent : @view.View, inset? : Double = 0.0) -> Unit {
  parent.box(fn(l) { l.height(Is(Some(1.0))).margin(Is((inset, 0.0, 0.0, 0.0))).ground(By(fn() { p().line })) |> ignore })
  |> ignore
}

///|
/// A card's ground, what it holds made by `body`.
fn card(parent : @view.View, body : (@view.View) -> Unit) -> Unit {
  parent.box(fn(c) {
    c.radius(Is(14.0)).ground(By(fn() { p().card })).clips(Is(true)).min_width(Is(Some(0.0))) |> ignore
    body(c)
  })
  |> ignore
}

///|
/// A section's heading over what it holds.
fn heading(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(h) {
    h.padding(Is((4.0, 8.0, 4.0, 2.0))) |> ignore
    text(h, words, 13.0, fn() { p().muted }, weight=600) |> ignore
  })
  |> ignore
}

///|
/// A quiet line in a card where there is nothing to list.
fn none_line(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(n) {
    n.padding(Is((16.0, 14.0, 16.0, 14.0))) |> ignore
    text(n, words, 13.0, fn() { p().muted }, wrap=true) |> ignore
  })
  |> ignore
}

///|
fn pill(parent : @view.View, words : () -> String, ground : () -> Int64, ink : () -> Int64) -> Unit {
  parent.box(fn(b) {
    b.padding(Is((8.0, 2.0, 8.0, 2.0))).radius(Is(999.0)).ground(By(ground)) |> ignore
    text(b, words, 11.0, ink, weight=500, line=16.0) |> ignore
  })
  |> ignore
}

///|
/// What kind an item is as an icon.
fn kind_icon(kind : String) -> String {
  match kind {
    "token" => "zap"
    "ssh_key" => "key"
    "login" => "user"
    "file" => "file"
    "browser" => "web"
    _ => "shield-check"
  }
}

///|
/// The kinds, in the sidebar's order.
let kinds : Array[String] = ["token", "ssh_key", "login", "file", "browser"]

///|
/// An item's tile, `side` across: its kind's icon on its kind's quiet ground.
fn tile(parent : @view.View, kind : () -> String, side : Double) -> Unit {
  parent.box(fn(t) {
    t
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .radius(Is(side * 0.27))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() {
      match kind() {
        "token" => p().amber_bg
        "ssh_key" => p().green_bg
        "login" => p().blue_bg
        "browser" => p().accent_bg
        _ => p().neutral_bg
      }
    }))
    |> ignore
    @sf.icon_node(t, "", side * 0.5, By(fn() {
      match kind() {
        "token" => p().warn_ink
        "ssh_key" => p().green_ink
        "login" => p().blue
        "browser" => p().accent
        _ => p().muted
      }
    }), name_now=fn() { kind_icon(kind()) })
    |> ignore
  })
  |> ignore
}

// ---- the window ----

///|
/// The vault client in node `v`, over `src` (the app signed in, started as the vault: sfapp's app_tree).
pub fn app(v : @view.View, src : @sfbase.Source) -> Unit {
  let s = State::new(src)
  v.grow(Is(1.0)).width_share(Is(1.0)).min_width(Is(Some(0.0))).ground(By(fn() { p().bg })) |> ignore
  // (what has to come first, else the library)
  v.pick(fn() { gate_of(s) }, fn(g, gate) {
    g.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    match gate {
      Open => library(g, s)
      _ => gate_view(g, s, gate)
    }
  })
}

///|
/// What has to come first before the library can be used here.
priv enum Gate {
  /// the vaults read still (or no workspace yet)
  Reading
  NoWorkspace
  /// a web page: names only
  AppOnly
  NeedsLock
  NotSigner
  /// not turned on on this device yet
  Off
  /// the recovery words to write down
  Words
  /// this device holds no vault's key yet
  NotKeyed
  Open
} derive(Eq)

///|
fn gate_of(s : State) -> Gate {
  if s.words.get() != "" {
    return Words
  }
  if s.ws() == "" {
    return NoWorkspace
  }
  let v = s.vaults()
  match v {
    None => Reading
    Some(_) if @sfbase.flag(v, "plain") => Open
    Some(_) if !@sfbase.flag(v, "available") => AppOnly
    Some(_) if !@sfbase.flag(v, "locked") => NeedsLock
    Some(_) if !@sfbase.flag(v, "canSign") => NotSigner
    Some(_) if !@sfbase.flag(v, "setUp") => Off
    Some(_) if s.vault_rows().length() > 0 && !s.vault_rows().iter().any(fn(r) { @sfbase.flag(Some(r), "keyed") }) =>
      NotKeyed
    Some(_) => Open
  }
}

///|
/// A card alone in the window's middle: the vault's mark, what stands in the way, and the way on.
fn gate_view(v : @view.View, s : State, gate : Gate) -> Unit {
  v.lines_up(Is(Some(Middle))).lies_along(Is(Middle)).padding(Is((24.0, 24.0, 24.0, 24.0))) |> ignore
  v.box(fn(col) {
    col.width_share(Is(1.0)).max_width(Is(Some(400.0))).lines_up(Is(Some(Middle))) |> ignore
    col.box(fn(m) {
      m
      .width(Is(Some(64.0)))
      .height(Is(Some(64.0)))
      .radius(Is(20.0))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .ground(By(fn() { p().accent_bg }))
      |> ignore
      @sf.icon_node(m, "shield-check", 32.0, By(fn() { p().accent })) |> ignore
    })
    |> ignore
    gap(col, 18.0)
    let (title, why) = match gate {
      Reading => ("web-pages.vaultApp.loading", "")
      NoWorkspace => ("web-pages.vaultApp.noWorkspace", "")
      AppOnly => ("web-pages.vault.appOnly", "web-pages.vault.appOnlyWhy")
      NeedsLock => ("web-pages.vault.needsLock", "web-pages.vault.needsLockWhy")
      NotSigner => ("web-pages.vault.notSigner", "web-pages.vault.notSignerWhy")
      Off => ("web-pages.vault.setUpTitle", "web-pages.vault.point.zeroHow")
      Words => ("web-pages.vault.words.title", "web-pages.vault.words.lead")
      NotKeyed => ("web-pages.vault.notKeyed", "web-pages.vault.notKeyedWhy")
      Open => ("", "")
    }
    if gate == Reading {
      @sf.spinner_node(col, size=20.0) |> ignore
      gap(col, 14.0)
    }
    text(col, fn() { @sf.t(title) }, 20.0, fn() { p().text }, weight=600, line=28.0) |> ignore
    if why != "" {
      gap(col, 6.0)
      col.box(fn(w) {
        w.width_share(Is(1.0)) |> ignore
        text(w, fn() { @sf.t(why) }, 13.0, fn() { p().muted }, wrap=true, line=20.0).words_centered(Is(true)) |> ignore
      })
      |> ignore
    }
    gap(col, 22.0)
    col.box(fn(f) {
      f.width_share(Is(1.0)).gap(Is(10.0)) |> ignore
      match gate {
        Off =>
          @sf.button_node(f, fn() { @sf.t("web-pages.vault.setUp") }, fn() { s.set_up() }, tone=Primary, across=true, busy=fn() {
            doing("vault/setup")
          })
          |> ignore
        Words => {
          card(f, fn(k) {
            k.padding(Is((18.0, 16.0, 18.0, 16.0))) |> ignore
            text(k, fn() { s.words.get() }, 15.0, fn() { p().text }, wrap=true, line=26.0) |> ignore
          })
          text(f, fn() { @sf.t("web-pages.vault.words.once") }, 12.0, fn() { p().muted }) |> ignore
          @sf.button_node(f, fn() { @sf.t("web-pages.vault.words.done") }, fn() { s.words.set("") }, tone=Primary, across=true) |> ignore
        }
        NotKeyed =>
          @sf.button_node(f, fn() { @sf.t("web-pages.vault.ask") }, fn() { s.ask_keys() }, tone=Primary, across=true, busy=fn() {
            doing("vault/ask")
          })
          |> ignore
        _ => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// Which screen the window is: 2 大屏, 1 中屏, 0 小屏.
fn tier(v : @view.View) -> Int {
  match @sf.layout(v.window().0) {
    Large => 2
    Medium => 1
    Small => 0
  }
}

///|
/// The library: the panes the screen has room for.
fn library(v : @view.View, s : State) -> Unit {
  v.pick(fn() { tier(v) }, fn(w, t) {
    w.grow(Is(1.0)).row(Is(true)).min_width(Is(Some(0.0))) |> ignore
    match t {
      2 => {
        sidebar(w, s)
        w.pick(fn() { s.pick.get() == Now }, fn(m, now) {
          m.grow(Is(1.0)).row(Is(true)).min_width(Is(Some(0.0))) |> ignore
          if now {
            now_pane(m, s)
          } else {
            list_pane(m, s, Some(320.0))
            rule_across(m)
            detail_pane(m, s, back=false)
          }
        })
      }
      1 =>
        w.pick(fn() { s.pick.get() == Now }, fn(m, now) {
          m.grow(Is(1.0)).row(Is(true)).min_width(Is(Some(0.0))) |> ignore
          if now {
            now_pane(m, s, with_chips=true)
          } else {
            list_pane(m, s, Some(320.0))
            rule_across(m)
            detail_pane(m, s, back=false)
          }
        })
      _ =>
        w.pick(fn() { (s.opened.get() && (s.chosen.get().1 != "" || s.editing.get() is Some(_)), s.pick.get() == Now) }, fn(
          o,
          at,
        ) {
          o.grow(Is(1.0)).row(Is(true)).min_width(Is(Some(0.0))) |> ignore
          match at {
            (true, _) => detail_pane(o, s, back=true)
            (false, true) => now_pane(o, s, with_chips=true)
            (false, false) => list_pane(o, s, None)
          }
        })
    }
  })
}

///|
fn rule_across(parent : @view.View) -> Unit {
  parent.box(fn(l) { l.width(Is(Some(1.0))).ground(By(fn() { p().line })) |> ignore }) |> ignore
}

///|
fn pick_name(s : State, pk : Pick) -> String {
  match pk {
    Now => @sf.t("web-pages.vaultApp.now")
    All => @sf.t("web-pages.vault.all")
    OfKind(k) => @sf.t("web-pages.vault.kind." + k)
    InVault(id) => @sfbase.text(s.vault(id), "name")
  }
}

// ---- the sidebar ----

///|
fn sidebar(parent : @view.View, s : State) -> Unit {
  parent.box(fn(side) {
    side.width(Is(Some(236.0))).ground(By(fn() { p().sidebar })) |> ignore
    side.box(fn(h) {
      h.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(10.0)).padding(Is((16.0, 18.0, 16.0, 10.0))) |> ignore
      h.box(fn(m) {
        m
        .width(Is(Some(28.0)))
        .height(Is(Some(28.0)))
        .radius(Is(8.0))
        .lines_up(Is(Some(Middle)))
        .lies_along(Is(Middle))
        .ground(By(fn() { p().primary }))
        |> ignore
        @sf.icon_node(m, "shield-check", 16.0, By(fn() { p().on_primary })) |> ignore
      })
      |> ignore
      h.box(fn(c) {
        c.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        text(c, fn() { @sf.t("web-pages.vaultApp.title") }, 14.0, fn() { p().text }, weight=600) |> ignore
        text(c, fn() {
          match @sfbase.workspace_in_view(s.src).0 {
            Some(w) => w.name
            None => ""
          }
        }, 11.0, fn() { p().muted })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    let scroll = @view.Scroll::new()
    @sf.side_scroll_node(side, scroll, fn(list) {
      side_row(list, s, Now, "zap")
      side_row(list, s, All, "list")
      @sf.side_heading_node(list, fn() { @sf.t("web-pages.vaultApp.kinds") })
      for k in kinds {
        side_row(list, s, OfKind(k), kind_icon(k))
      }
      @sf.side_heading_node(list, fn() { @sf.t("web-pages.vault.vaults") })
      list.each(fn() { s.vault_rows().map(fn(r) { @sfbase.text(Some(r), "id") }) }, fn(id) { id }, fn(r, id) {
        side_row(r, s, InVault(@signals.untracked(fn() { id.get() })), "users")
      })
    })
    |> ignore
    // (at its foot: whether its vaults are unlocked here, and locking them now)
    side.box(fn(f) {
      f.padding(Is((8.0, 8.0, 8.0, 12.0))) |> ignore
      rule(f)
      gap(f, 8.0)
      f.pick(fn() { s.vault_rows().iter().any(fn(r) { @sfbase.flag(Some(r), "open") }) && !s.plain_library() }, fn(o, open) {
        if open {
          @sf.nav_row_node(o, fn() { false }, fn() { @sf.t("web-pages.vault.lockNow") }, fn() { s.lock() }, fn(r) {
            r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(10.0)) |> ignore
            @sf.icon_node(r, "power", 16.0, By(fn() { p().muted })) |> ignore
            @sf.nav_words_node(r, fn() { @sf.t("web-pages.vault.lockNow") })
          })
          |> ignore
        } else {
          o.box(fn(r) {
            r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(10.0)).padding(Is((10.0, 8.0, 10.0, 8.0))) |> ignore
            @sf.icon_node(r, "shield-check", 16.0, By(fn() { p().muted })) |> ignore
            text(r, fn() {
              @sf.t(if s.plain_library() { "web-pages.vault.lib.plain" } else { "web-pages.vault.lib.sealed" })
            }, 13.0, fn() { if s.plain_library() { p().warn_ink } else { p().muted } })
            |> ignore
          })
          |> ignore
        }
      })
    })
    |> ignore
  })
  |> ignore
}

///|
fn side_row(list : @view.View, s : State, pk : Pick, icon : String) -> Unit {
  @sf.nav_row_node(list, fn() { s.pick.get() == pk }, fn() { pick_name(s, pk) }, fn() { choose(s, pk) }, fn(r) {
    r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(10.0)) |> ignore
    @sf.icon_node(r, icon, 16.0, By(fn() { if s.pick.get() == pk { p().text } else { p().muted } })) |> ignore
    @sf.nav_words_node(r, fn() { pick_name(s, pk) })
    text(r, fn() {
      let n = s.count(pk)
      if pk == Now && n == 0 {
        ""
      } else {
        n.to_string()
      }
    }, 12.0, fn() { if pk == Now { p().accent } else { p().subtle } }, weight=if pk == Now { 600 } else { 400 })
    |> ignore
  })
  |> ignore
}

///|
fn choose(s : State, pk : Pick) -> Unit {
  s.pick.set(pk)
  s.search.set("")
  s.opened.set(false)
}

///|
/// 中屏 and 小屏: the sidebar's picks as chips.
fn chips(parent : @view.View, s : State) -> Unit {
  parent.box(fn(c) {
    c.row(Is(true)).gap(Is(6.0)).padding(Is((12.0, 0.0, 12.0, 10.0))).wraps(Is(Some(6.0))) |> ignore
    for pk in [Now, All, ..kinds.map(fn(k) { OfKind(k) })] {
      @sf.chip_node(c, fn() {
        let n = s.count(pk)
        if pk == Now && n > 0 {
          "\{pick_name(s, pk)} \{n}"
        } else {
          pick_name(s, pk)
        }
      }, fn() { choose(s, pk) }, ink=fn() { if s.pick.get() == pk { p().accent } else { p().muted } })
      |> ignore
    }
  })
  |> ignore
}

// ---- the list ----

///|
/// The list of what is picked: its name and how many, 添加, the search, the rows; `width` as said (None: all the room).
fn list_pane(parent : @view.View, s : State, width : Double?) -> Unit {
  parent.box(fn(pane) {
    match width {
      Some(w) => pane.width(Is(Some(w))) |> ignore
      None => pane.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
    }
    pane.min_height(Is(Some(0.0))).ground(By(fn() { p().canvas })) |> ignore
    pane.box(fn(h) {
      h.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(8.0)).padding(Is((16.0, 14.0, 10.0, 6.0))) |> ignore
      h.box(fn(c) {
        c.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        text(c, fn() { pick_name(s, s.pick.get()) }, 17.0, fn() { p().text }, weight=600, line=24.0) |> ignore
        text(c, fn() { @sf.t("web-pages.vault.count", args=[("n", s.listed().length().to_string())]) }, 12.0, fn() {
          p().muted
        })
        |> ignore
      })
      |> ignore
      @sf.icon_button_node(h, "plus", fn() { @sf.t("web-pages.vault.add") }, fn() { start_new(s) }) |> ignore
    })
    |> ignore
    pane.box(fn(f) {
      f.padding(Is((12.0, 4.0, 12.0, 10.0))) |> ignore
      @sf.input_node(f, s.search, placeholder_by=fn() { @sf.t("web-pages.vault.find") }) |> ignore
    })
    |> ignore
    pane.show(fn() { tier(pane) < 2 }, fn(c) { chips(c, s) })
    let scroll = @view.Scroll::new()
    pane.box(fn(col) {
      col.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      col.scrolls(scroll, bar=@ui.tree_scroll_bar(), fn(body) {
        body.box(fn(rows) {
          rows.padding(Is((8.0, 0.0, 8.0, 16.0))).gap(Is(2.0)) |> ignore
          rows.each(fn() { s.listed() }, fn(r) { r.vault + "/" + @sfbase.text(Some(r.row), "id") }, fn(r, it) {
            list_row(r, s, fn() { it.get() })
          })
          rows.show(fn() { s.listed().length() == 0 }, fn(none) {
            none.padding(Is((16.0, 40.0, 16.0, 0.0))).lines_up(Is(Some(Middle))).gap(Is(6.0)) |> ignore
            text(none, fn() {
              let q = s.search.text()
              if q == "" {
                @sf.t("web-pages.vault.empty")
              } else {
                @sf.t("web-pages.vault.noMatch", args=[("q", q)])
              }
            }, 14.0, fn() { p().muted }, weight=500)
            |> ignore
          })
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
fn list_row(r : @view.View, s : State, it : () -> Row) -> Unit {
  let id = fn() { @sfbase.text(Some(it().row), "id") }
  r.box(fn(row) {
    row.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(12.0)).padding(Is((10.0, 8.0, 10.0, 8.0))).radius(Is(10.0)) |> ignore
    @sf.nav_ground_node(row, fn() { s.chosen.get() == (it().vault, id()) && s.editing.get() is None })
    @sf.presses_node(row, fn() { s.show(it().vault, id()) })
    row.says(By(fn() { Some(@view.said(Link, label=row_name(it().row))) })) |> ignore
    tile(row, fn() { @sfbase.text(Some(it().row), "kind") }, 36.0)
    row.box(fn(c) {
      c.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(1.0)) |> ignore
      text(c, fn() { row_name(it().row) }, 14.0, fn() { p().text }, weight=500, line=20.0) |> ignore
      text(c, fn() { @sfbase.text(Some(it().row), "lineText") }, 12.0, fn() { p().muted }, line=17.0) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A new item: its editor, of a token first.
fn start_new(s : State) -> Unit {
  s.chosen.set(("", ""))
  s.plain.set(None)
  s.editing.set(Some(("", "token")))
  s.opened.set(true)
  if @signals.untracked(fn() { s.pick.get() }) == Now {
    s.pick.set(All)
  }
}

// ---- the item ----

///|
fn detail_pane(parent : @view.View, s : State, back~ : Bool) -> Unit {
  parent.box(fn(pane) {
    pane.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    pane.pick(fn() { (s.editing.get(), s.chosen.get()) }, fn(v, at) {
      v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      match at {
        (Some((id, kind)), _) => editor(v, s, id, kind, back)
        (None, (_, "")) => {
          v.lines_up(Is(Some(Middle))).lies_along(Is(Middle)).gap(Is(8.0)) |> ignore
          @sf.icon_node(v, "shield-check", 40.0, By(fn() { p().subtle })) |> ignore
          text(v, fn() { @sf.t("web-pages.vaultApp.pick") }, 14.0, fn() { p().muted }) |> ignore
        }
        (None, (vault, id)) => item_view(v, s, vault, id, back)
      }
    })
  })
  |> ignore
}

///|
/// A bar over a pane: back where it is a page of its own, then what `acts` puts at its end.
fn pane_bar(v : @view.View, s : State, back : Bool, acts : (@view.View) -> Unit) -> Unit {
  v.box(fn(bar) {
    bar.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(6.0)).padding(Is((12.0, 10.0, 12.0, 6.0))).min_height(Is(Some(52.0))) |> ignore
    if back {
      @sf.icon_button_node(bar, "chevron-left", fn() { @sf.t("common.back") }, fn() {
        s.opened.set(false)
        s.editing.set(None)
      })
      |> ignore
    }
    grow(bar)
    acts(bar)
  })
  |> ignore
}

///|
/// A column scrolling in the room left, `body` in it, as wide as a reading column at most.
fn column(v : @view.View, body : (@view.View) -> Unit) -> Unit {
  let scroll = @view.Scroll::new()
  v.box(fn(col) {
    col.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
    col.scrolls(scroll, bar=@ui.tree_scroll_bar(), fn(b) {
      b.box(fn(room) {
        room.width_share(Is(1.0)).min_width(Is(Some(0.0))).lines_up(Is(Some(Middle))).padding(Is((20.0, 8.0, 20.0, 40.0))) |> ignore
        room.box(fn(c) {
          c.width_share(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(16.0)) |> ignore
          // (a reading column's width at most, and never wider than the window leaves it: what it holds wraps in it)
          c.max_width(By(fn() { Some(if c.window().0 - 40.0 < 640.0 { c.window().0 - 40.0 } else { 640.0 }) })) |> ignore
          body(c)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
fn item_view(v : @view.View, s : State, vault : String, id : String, back : Bool) -> Unit {
  let row = fn() { s.chosen_row() }
  let r = fn() { row() }
  let opened = fn() {
    match s.plain.get() {
      Some((at, o)) if at == id => Some(o)
      _ => None
    }
  }
  pane_bar(v, s, back, fn(bar) {
    @sf.icon_button_node(bar, "trash", fn() { @sf.t("common.delete") }, fn() { s.deleting.set(!s.deleting.get()) }) |> ignore
    @sf.button_node(bar, fn() { @sf.t("common.edit") }, fn() {
      let kind = @sfbase.text(@signals.untracked(r), "kind")
      s.open(then=fn() { s.editing.set(Some((id, kind))) })
    }, icon="edit", busy=fn() { doing("vault/open/" + id) })
    |> ignore
  })
  column(v, fn(c) {
    // (its delete asked first)
    c.show(fn() { s.deleting.get() }, fn(d) {
      card(d, fn(k) {
        k.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(10.0)).padding(Is((16.0, 12.0, 12.0, 12.0))) |> ignore
        text(k, fn() { @sf.t("web-pages.vaultApp.deleteConfirm") }, 13.0, fn() { p().red }, wrap=true).grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore
        @sf.button_node(k, fn() { @sf.t("common.cancel") }, fn() { s.deleting.set(false) }, tone=Ghost) |> ignore
        @sf.button_node(k, fn() { @sf.t("common.delete") }, fn() { s.delete() }, tone=DangerSolid, busy=fn() { doing("vault/delete/" + id) }) |> ignore
      })
    })
    // its tile, name, kind and vault
    c.box(fn(h) {
      h.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(16.0)).padding(Is((4.0, 0.0, 4.0, 4.0))) |> ignore
      tile(h, fn() { @sfbase.text(r(), "kind") }, 56.0)
      h.box(fn(t) {
        t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(6.0)) |> ignore
        text(t, fn() {
          match r() {
            Some(x) => row_name(x)
            None => ""
          }
        }, 22.0, fn() { p().text }, weight=600, line=28.0)
        |> ignore
        t.box(fn(m) {
          m.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
          pill(m, fn() { @sfbase.text(r(), "kindText") }, fn() { p().accent_bg }, fn() { p().accent })
          pill(m, fn() { @sfbase.text(s.vault(vault), "name") }, fn() { p().neutral_bg }, fn() { p().muted })
          m.show(fn() { s.plain_library() }, fn(u) {
            pill(u, fn() { @sf.t("web-pages.vault.risk.row") }, fn() { p().amber_bg }, fn() { p().warn_ink })
          })
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // its fields: as its row says them (dots) until opened, then as opened
    card(c, fn(k) {
      k.each(
        fn() {
          let fs = match opened() {
            Some(o) => @sfbase.items(Some(o), "shown")
            None => @sfbase.items(r(), "shut")
          }
          fs.mapi(fn(i, f) { (i, f, opened() is Some(_)) })
        },
        fn(x) { "\{x.0}/\{@sfbase.text(Some(x.1), "key")}/\{x.2}" },
        fn(fr, x) {
          let (i, f, open) = @signals.untracked(fn() { x.get() })
          if i > 0 {
            rule(fr, inset=16.0)
          }
          field_row(fr, s, id, f, open)
        },
      )
      k.show(fn() { opened() is None }, fn(u) {
        u.padding(Is((16.0, 4.0, 16.0, 14.0))) |> ignore
        @sf.button_node(u, fn() { @sf.t("web-pages.vaultApp.unlockToSee") }, fn() { s.open() }, icon="eye", busy=fn() {
          doing("vault/open/" + id)
        })
        |> ignore
      })
    })
    // how agents may use it
    heading(c, fn() { @sf.t("web-pages.vaultApp.agent") })
    card(c, fn(k) {
      k.padding(Is((16.0, 12.0, 16.0, 14.0))).gap(Is(6.0)) |> ignore
      text(k, fn() { @sfbase.text(r(), "agentText") }, 14.0, fn() { p().text }, weight=500, wrap=true) |> ignore
      k.show(fn() { @sfbase.flag(r(), "listed") }, fn(l) {
        l.gap(Is(4.0)) |> ignore
        text(l, fn() { @sf.t("web-pages.vault.how") + " · " + @sfbase.text(r(), "howText") }, 13.0, fn() { p().muted }, wrap=true) |> ignore
        text(l, fn() { @sf.t("web-pages.vault.editor.lasts") + " · " + @sfbase.text(r(), "lastsText") }, 13.0, fn() {
          p().muted
        })
        |> ignore
      })
    })
    // when agents used it
    heading(c, fn() { @sf.t("web-pages.vault.uses.title") })
    card(c, fn(k) {
      k.each(fn() { s.item_uses(vault, id).mapi(fn(i, u) { (i, u) }) }, fn(x) { x.0 }, fn(ur, x) {
        let (i, u) = @signals.untracked(fn() { x.get() })
        if i > 0 {
          rule(ur, inset=16.0)
        }
        use_row(ur, u, item=false)
      })
      k.show(fn() { s.item_uses(vault, id).length() == 0 }, fn(n) { none_line(n, fn() { @sf.t("web-pages.vault.uses.none") }) })
    })
  })
}

///|
/// A field on an item's card: its label over its value (dots while hidden), at its end its eye (a secret one, opened)
/// and its copy key (opened).
fn field_row(k : @view.View, s : State, id : String, f : Json, open : Bool) -> Unit {
  let key = @sfbase.text(Some(f), "key")
  let label = @sfbase.text(Some(f), "label")
  let value = @sfbase.text(Some(f), "value")
  let secret = @sfbase.flag(Some(f), "secret")
  let mono = @sfbase.flag(Some(f), "mono")
  let clear = fn() { !secret || s.clear.get().contains(id + "/" + key) }
  k.box(fn(r) {
    r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(4.0)).padding(Is((16.0, 10.0, 8.0, 10.0))).min_height(Is(Some(56.0))) |> ignore
    r.box(fn(c) {
      c.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(2.0)) |> ignore
      text(c, fn() { label }, 12.0, fn() { p().muted }) |> ignore
      c.pick(fn() { open && clear() }, fn(w, shown) {
        if shown && mono {
          // (in the code face, its digits blue and its symbols red, as a password manager tells them apart)
          w.box(fn(m) {
            m.words_runs(Is(secret_runs(value)), look=look(14.0, 400, 21.0, wrap=true)).ink(By(fn() { p().text })).min_width(Is(Some(0.0))) |> ignore
          })
          |> ignore
        } else if shown {
          text(w, fn() { value }, 14.0, fn() { p().text }, wrap=true, line=21.0) |> ignore
        } else {
          text(w, fn() { "••••••••••••" }, 15.0, fn() { p().text }, line=21.0) |> ignore
        }
      })
    })
    |> ignore
    if open && secret {
      @sf.icon_button_node(r, "eye", fn() { @sf.t(if clear() { "web-pages.vaultApp.hide" } else { "web-pages.vaultApp.show" }) }, fn() {
        s.toggle_clear(id + "/" + key)
      })
      |> ignore
    }
    if open {
      @sf.icon_button_node(r, "copy", fn() { @sf.t("common.copy") + label }, fn() { s.copy(label, value, secret) }) |> ignore
    }
  })
  |> ignore
}

///|
/// A secret's words shown: each character in the code face, digits in blue, symbols in red.
fn secret_runs(v : String) -> Array[@text.Run] {
  let out : Array[@text.Run] = []
  for ch in v {
    let color = if ch >= '0' && ch <= '9' {
      p().blue
    } else if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == ' ' || ch == '\n' {
      0L
    } else {
      p().red
    }
    out.push(@ui.span(ch.to_string(), mono=true, color~))
  }
  out
}

///|
/// A use: in which chat and how, when; turned down, said so. `item`: the item's name first (a whole vault's uses).
fn use_row(parent : @view.View, u : Json, item~ : Bool) -> Unit {
  let v = Some(u)
  parent.box(fn(r) {
    r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(10.0)).padding(Is((16.0, 10.0, 16.0, 10.0))) |> ignore
    r.box(fn(c) {
      c.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(2.0)) |> ignore
      let title = if item {
        let n = @sfbase.text(v, "itemName")
        if n == "" { @sfbase.text(v, "chatTitle") } else { n + " · " + @sfbase.text(v, "chatTitle") }
      } else {
        @sfbase.text(v, "chatTitle")
      }
      text(c, fn() { title }, 14.0, fn() { p().text }, weight=500) |> ignore
      text(c, fn() { @sfbase.text(v, "howText") }, 12.0, fn() { p().muted }) |> ignore
    })
    |> ignore
    if @sfbase.flag(v, "denied") {
      pill(r, fn() { @sf.t("web-pages.vault.uses.denied") }, fn() { p().red_bg }, fn() { p().red })
    }
    text(r, fn() { @sfbase.text(@sfbase.field(v, "at"), "ago") }, 12.0, fn() { p().subtle }) |> ignore
  })
  |> ignore
}

// ---- 现在 ----

///|
/// What is going on now: the requests waiting on the person, the grants agents hold, the latest uses.
fn now_pane(parent : @view.View, s : State, with_chips? : Bool = false) -> Unit {
  parent.box(fn(pane) {
    pane.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    pane.box(fn(h) {
      h.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(8.0)).padding(Is((20.0, 16.0, 12.0, 4.0))) |> ignore
      h.box(fn(c) {
        c.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        text(c, fn() { @sf.t("web-pages.vaultApp.now") }, 20.0, fn() { p().text }, weight=600, line=28.0) |> ignore
        text(c, fn() { @sf.t("web-pages.vaultApp.nowLead") }, 12.0, fn() { p().muted }) |> ignore
      })
      |> ignore
      @sf.icon_button_node(h, "plus", fn() { @sf.t("web-pages.vault.add") }, fn() { start_new(s) }) |> ignore
    })
    |> ignore
    if with_chips {
      chips(pane, s)
    }
    column(pane, fn(c) {
      heading(c, fn() { @sf.t("web-pages.vault.requests") })
      c.box(fn(list) {
        list.gap(Is(10.0)).min_width(Is(Some(0.0))) |> ignore
        list.each(fn() { s.requests().map(fn(r) { @sfbase.text(Some(r), "id") }) }, fn(id) { id }, fn(rr, id) {
          let rid = @signals.untracked(fn() { id.get() })
          request_card(rr, s, fn() { s.requests().search_by(fn(r) { @sfbase.text(Some(r), "id") == rid }).map(fn(i) { s.requests()[i] }) })
        })
        list.show(fn() { s.requests().length() == 0 }, fn(n) {
          card(n, fn(k) { none_line(k, fn() { @sf.t("web-pages.vaultApp.requestsNone") }) })
        })
      })
      |> ignore
      heading(c, fn() { @sf.t("web-pages.vaultApp.held") })
      card(c, fn(k) {
        k.each(fn() { s.grants().map(fn(g) { @sfbase.text(Some(g), "request") }) }, fn(x) { x }, fn(gr, x) {
          let rid = @signals.untracked(fn() { x.get() })
          // (a line over it while another is over it: the first one gone, the next has none)
          gr.show(fn() { s.grants().search_by(fn(g) { @sfbase.text(Some(g), "request") == rid }).unwrap_or(0) > 0 }, fn(l) {
            rule(l, inset=16.0)
          })
          grant_row(gr, s, rid)
        })
        k.show(fn() { s.grants().length() == 0 }, fn(n) { none_line(n, fn() { @sf.t("web-pages.vaultApp.heldNone") }) })
      })
      heading(c, fn() { @sf.t("web-pages.vaultApp.recent") })
      card(c, fn(k) {
        k.each(fn() { s.recent().mapi(fn(i, u) { (i, u) }) }, fn(x) { x.0 }, fn(ur, x) {
          let (i, u) = @signals.untracked(fn() { x.get() })
          if i > 0 {
            rule(ur, inset=16.0)
          }
          use_row(ur, u, item=true)
        })
        k.show(fn() { s.recent().length() == 0 }, fn(n) { none_line(n, fn() { @sf.t("web-pages.vault.uses.none") }) })
      })
    })
  })
  |> ignore
}

///|
/// A request waiting on the person: which item, which chat asks and why, how it would be given (the command, the
/// domains); 拒绝, 仅这一次 and allowed for the time the agent asked (an hour's idle where it said none), as far as the
/// item allows. One to keep a secret: 存入 or 不存 (one the person types in, on its card in the chat).
fn request_card(parent : @view.View, s : State, r : () -> Json?) -> Unit {
  let v = fn() { r() }
  let id = @sfbase.text(@signals.untracked(v), "id")
  let save = @sfbase.field(@signals.untracked(v), "save") is Some(Object(_))
  let typed = @sfbase.flag(@sfbase.field(@signals.untracked(v), "save"), "typed")
  card(parent, fn(k) {
    k.padding(Is((16.0, 14.0, 16.0, 14.0))).gap(Is(8.0)) |> ignore
    k.box(fn(h) {
      h.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(12.0)) |> ignore
      tile(h, fn() {
        match @sfbase.field(v(), "save") {
          Some(sv) => @sfbase.text(Some(sv), "kind")
          None => "token"
        }
      }, 36.0)
      h.box(fn(t) {
        t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(1.0)) |> ignore
        text(t, fn() { @sfbase.text(v(), "itemName") }, 15.0, fn() { p().text }, weight=600) |> ignore
        text(t, fn() {
          let chat = @sfbase.text(v(), "chatTitle")
          let chat = if chat == "" { @sfbase.text(v(), "chat") } else { chat }
          @sf.t(if save { "web-pages.vaultApp.wantsSave" } else { "web-pages.vaultApp.wantsUse" }, args=[("chat", chat)])
        }, 12.0, fn() { p().muted })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    text(k, fn() { @sfbase.text(v(), "reason") }, 14.0, fn() { p().text }, wrap=true, line=21.0) |> ignore
    k.show(fn() { !save }, fn(w) {
      text(w, fn() {
        let cmd = @sfbase.text(v(), "command")
        @sfbase.text(v(), "howText") + (if cmd == "" { "" } else { " · " + cmd })
      }, 12.0, fn() { p().muted }, wrap=true)
      |> ignore
    })
    gap(k, 2.0)
    if save && typed {
      text(k, fn() { @sf.t("web-pages.vaultApp.typedThere") }, 12.0, fn() { p().muted }, wrap=true) |> ignore
    }
    k.box(fn(acts) {
      // (its buttons at its end, onto another line where the card has not the room for them)
      acts.row(Is(true)).lines_up(Is(Some(Middle))).lies_along(Is(End)).gap(Is(8.0)).wraps(Is(Some(8.0))) |> ignore
      let busy = fn() { doing("vault/approve/" + id) || doing("vault/deny/" + id) }
      @sf.button_node(acts, fn() {
        @sf.t(if save { "android-settings.vault.act.dontSave" } else { "android-settings.vault.act.deny" })
      }, fn() { s.deny(id) }, tone=Ghost, disabled=busy)
      |> ignore
      if save {
        if !typed {
          @sf.button_node(acts, fn() { @sf.t("android-settings.vault.act.save") }, fn() { s.approve(id) }, tone=Primary, busy=busy) |> ignore
        }
      } else {
        @sf.button_node(acts, fn() { @sf.t("android-settings.vault.scope.once") }, fn() { s.approve(id) }, disabled=busy) |> ignore
        acts.show(fn() { @sfbase.text(v(), "lasts") != "once" }, fn(a) {
          @sf.button_node(a, fn() { @sf.t("web-pages.vaultApp.allowFor", args=[("time", asked_words(v()))]) }, fn() {
            s.approve(id, timeout=asked_time(@signals.untracked(v)))
          }, tone=Primary, busy=busy)
          |> ignore
        })
      }
    })
    |> ignore
  })
}

///|
/// How long the agent asked for (its kind and seconds), as far as the item allows: an hour's idle where it asked
/// none; an item given for an hour at most, an hour at most.
fn asked_time(r : Json?) -> (String, Int) {
  let kind = match @sfbase.text(r, "timeoutKind") {
    "" => "idle"
    k => k
  }
  let asked = @sfbase.number(r, "timeoutSeconds").to_int()
  let most = if @sfbase.text(r, "lasts") == "hour" { 3600 } else { 30 * 86400 }
  let seconds = if asked <= 0 { 3600 } else if asked > most { most } else { asked }
  (kind, seconds)
}

///|
/// That time in words (闲置 1 小时后失效, 2 天后失效).
fn asked_words(r : Json?) -> String {
  let (kind, seconds) = asked_time(r)
  let minutes = seconds / 60
  let duration = if minutes % 1440 == 0 {
    @sf.t("android-settings.vault.timeout.nDays", args=[("n", (minutes / 1440).to_string())])
  } else if minutes % 60 == 0 {
    @sf.t("android-settings.vault.timeout.nHours", args=[("n", (minutes / 60).to_string())])
  } else {
    @sf.t("android-settings.vault.timeout.nMinutes", args=[("n", minutes.to_string())])
  }
  @sf.t("android-settings.vault.timeout.button." + kind, args=[("time", duration)])
}

///|
/// A grant an agent holds: its item and chat, how it is given, until when and how often used; 收回.
fn grant_row(parent : @view.View, s : State, rid : String) -> Unit {
  let g = fn() { s.grants().search_by(fn(x) { @sfbase.text(Some(x), "request") == rid }).map(fn(i) { s.grants()[i] }) }
  parent.box(fn(r) {
    r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(12.0)).padding(Is((16.0, 10.0, 12.0, 10.0))) |> ignore
    tile(r, fn() {
      match @sfbase.text(g(), "mode") {
        "ssh" => "ssh_key"
        "browser" => "browser"
        "file" => "file"
        _ => "token"
      }
    }, 32.0)
    r.box(fn(c) {
      c.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).gap(Is(2.0)) |> ignore
      text(c, fn() {
        let n = @sfbase.text(g(), "itemName")
        (if n == "" { @sfbase.text(g(), "vaultName") } else { n }) + " · " + @sfbase.text(g(), "chatTitle")
      }, 14.0, fn() { p().text }, weight=500)
      |> ignore
      text(c, fn() { @sfbase.text(g(), "howText") }, 12.0, fn() { p().muted }) |> ignore
      text(c, fn() {
        let when = @sfbase.text(@sfbase.field(g(), "until"), "ago")
        let ends = @sf.t(if @sfbase.flag(g(), "idle") { "web-pages.vaultApp.endsIdle" } else { "web-pages.vaultApp.ends" }, args=[
          ("when", when),
        ])
        let n = @sfbase.number(g(), "uses").to_int()
        ends + " · " + @sf.t("web-pages.vaultApp.used", args=[("n", n.to_string())])
      }, 12.0, fn() { p().subtle })
      |> ignore
    })
    |> ignore
    @sf.button_node(r, fn() { @sf.t("web-pages.vaultApp.revoke") }, fn() { s.revoke(rid) }, tone=GhostDanger, busy=fn() {
      doing("vault/revoke/" + rid)
    })
    |> ignore
  })
  |> ignore
}
