// The new chat's choices in its composer's row, wide (new_tools': NewChat.tsx's toolbar), as nodes of the window's
// tree, made once: what it is for (the presets' control), where it runs (the station's) and what it runs on (the
// model's, model_triple's), each a capsule of the row as new_capsule has it, each what it says followed as the page's
// view changes; short of room, each gives up its words in the order new_controls' do (View::drops), never its place.
// Pressed, each opens what new_controls' opens, beside it (Beside::Node); asked from elsewhere (new_chat_ask), opened
// then, as though pressed (`asks`: each says what it opens so, new_opens; not a copy of them that only shows).
// `going`: the page on its way to its chat, pressed for nothing. The composer's copy of it as the page becomes its
// chat is the same, drawn only (composer_node's leaving toolbar).

///|
/// The choices in `row` (the composer's choices part), for workspace `w`'s new chat as `v` (the core's `newChat`
/// view) and `station` (where it starts) say, each as it changes.
fn new_tools_node(
  row : @view.View,
  src : Source,
  w : () -> Workspace?,
  v : () -> Json?,
  station : () -> Json?,
  going? : () -> Bool = fn() { false },
  asks? : Bool = true,
) -> Unit {
  // (as the old row's `choices`: in a line, 4 apart, short of room each giving up its words: View::fits)
  row.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Middle))).grow(Is(1.0)).fits(Is(true)) |> ignore
  let address = fn() { text(station(), "station") }
  new_preset_node(row, src, w, v, address, going, asks)
  row.show(fn() { text(station(), "name") != "" }, fn(s) { new_station_node(s, src, w, v, station, going, asks) })
  new_model_node(row, src, v, address, going, asks)
}

///|
/// A capsule of the row in `parent` (new_capsule's, in its row): 28 high, 8 in, its parts 6 apart, round by the
/// theme's large corner, the hover's ground under the pointer (or while `lit`); read out a button named `label`;
/// `press` as it is pressed, unless `going`. What it holds `body`'s. The node.
fn new_capsule_node(
  parent : @view.View,
  label : () -> String,
  going : () -> Bool,
  press : (@view.View) -> Unit,
  body : (@view.View) -> Unit,
  lit? : () -> Bool = fn() { false },
) -> @view.View {
  parent.box(fn(b) {
    b
    .row(Is(true))
    .height(Is(Some(28.0)))
    .padding(Is((8.0, 0.0, 8.0, 0.0)))
    .gap(Is(6.0))
    .lines_up(Is(Some(Middle)))
    .min_width(Is(Some(0.0)))
    .radius(By(fn() { @ui.tree_theme().corner(Lg) }))
    .ground(By(fn() { if lit() || b.pointed() { @sf.theme().p.hover } else { 0L } }))
    .presses(Is(true))
    .focusable(Is(true))
    .on_press(fn() { if !going() { press(b) } })
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    body(b)
  })
}

///|
/// Words of a capsule's in `parent` (new_capsule_words', or `style`'s), cut short where the capsule has not the room.
fn capsule_words_node(parent : @view.View, words : () -> String, style? : () -> @ui.TextStyle = fn() { new_capsule_words }) -> @view.View {
  parent.box(fn(t) {
    t
    .min_width(Is(Some(0.0)))
    .words(By(words))
    .words_look(By(fn() { @ui.style_words(style()) }))
    .ink(By(fn() { @ui.style_ink(style()) }))
    |> ignore
  })
}

///|
/// What it is for (new_preset_control's): its folders' marks (a quiet mark of what it adds, none picked), the preset's
/// name (预设 while none is), a chevron; pressed, the station's presets as a menu (preset_menu); asked from elsewhere,
/// that menu, a preset made, changed or a folder added to it (preset_dialog). Nothing in a page's bones, nor without a
/// station.
fn new_preset_node(
  row : @view.View,
  src : Source,
  w : () -> Workspace?,
  v : () -> Json?,
  address : () -> String,
  going : () -> Bool,
  asks : Bool,
) -> Unit {
  let picked = fn() { text(v(), "preset") }
  let name = fn() { if picked() == "" { "" } else { text(v(), "presetName") } }
  let label = fn() { if name() == "" { @sf.t("web-main.preset.label") } else { name() } }
  let marks = fn() { if name() == "" { [] } else { items(v(), "presetMarks") } }
  row.show(fn() { address() != "" && !row.in_bones() }, fn(slot) {
    let menu = fn(at : @view.View) {
      match w() {
        Some(ws) => preset_menu(src, ws, address(), v(), picked(), @sf.beside_node(at))
        None => ()
      }
    }
    let capsule = new_capsule_node(slot, label, going, menu, fn(b) {
      b.show(fn() { marks().length() > 0 }, fn(m) {
        m.row(Is(true)).gap(Is(2.0)).lines_up(Is(Some(Middle))) |> ignore
        m.each(marks, fn(k) { text(Some(k), "repo") + "\u{1}" + text(Some(k), "name") }, fn(one, k) {
          let of = fn(key : String) { fn() { text(Some(k.get()), key) } }
          @sf.tile_avatar_node(one, fn() { let r = of("repo")(); if r != "" { r } else { of("name")() } }, of("name"),
            of("icon"), new_mark, corner=@sf.small_corner)
        })
      })
      b.show(fn() { marks().length() == 0 }, fn(i) {
        @sf.icon_node(i, "folder-plus", new_mark, By(fn() { @sf.theme().p.muted })) |> ignore
      })
      // (its words left out first, short of room: its mark says what it is)
      capsule_words_node(b, label, style=fn() { if name() == "" { preset_capsule_quiet } else { new_capsule_words } })
      .max_width(Is(Some(128.0)))
      .drops(Is(preset_drop_words))
      |> ignore
      // (its chevron last, after the station's name: its mark alone, a round, on the narrowest)
      b.box(fn(c) {
        c.drops(Is(preset_drop_chevron)) |> ignore
        @sf.icon_node(c, "chevron-down", new_chevron, By(fn() { @sf.theme().p.muted })) |> ignore
      })
      |> ignore
    })
    // (asked from elsewhere: the menu beside it, or a dialog of the presets', as it is asked: new_chat_ask)
    if asks {
      let dialog = fn(id : () -> String, adding : Bool, browsing : Bool) {
        fn() {
          match w() {
            Some(ws) => preset_dialog(src, ws, address(), id(), items(v(), "stations"), adding~, browsing~)
            None => ()
          }
        }
      }
      let first = fn() { text(items(v(), "presets").get(0), "id") }
      new_opens_said(slot, "preset", fn() { menu(capsule) })
      new_opens_said(slot, "preset-new", dialog(fn() { "" }, false, false))
      new_opens_said(slot, "preset-edit", dialog(first, false, false))
      new_opens_said(slot, "preset-add", dialog(first, true, false))
      new_opens_said(slot, "preset-new-add", dialog(fn() { "" }, true, false))
      new_opens_said(slot, "preset-new-browse", dialog(fn() { "" }, false, true))
    }
  })
}

///|
/// Where it runs (new_station_control's): the station's mark, its name (128 at most), a chevron; pressed, the
/// workspace's stations through the presenters, the one it starts on checked (station_rows); asked from elsewhere, so.
fn new_station_node(
  slot : @view.View,
  src : Source,
  w : () -> Workspace?,
  v : () -> Json?,
  station : () -> Json?,
  going : () -> Bool,
  asks : Bool,
) -> Unit {
  let open = fn(at : @view.View) {
    match w() {
      Some(ws) =>
        @sf.panel(
          @sf.t("android-chat.new.station.pick"),
          fn(c, close) { station_rows(c, src, ws, v(), close) },
          from=@sf.beside_node(at).anchor(),
        )
      None => ()
    }
  }
  let capsule = new_capsule_node(slot, fn() { text(station(), "name") }, going, open, fn(b) {
    @sf.station_mark_node(b, fn() { text(station(), "emoji") }, fn() { text(station(), "icon") }, new_mark, fn() {
      @sf.theme().p.text
    }, fn() { 0 })
    // (its name left out after what the model's control leaves out, its mark kept: the page says where it starts)
    capsule_words_node(b, fn() { text(station(), "name") }).max_width(Is(Some(128.0))).drops(Is(new_drop_station_name))
    |> ignore
    @sf.icon_node(b, "chevron-down", new_chevron, By(fn() { @sf.theme().p.muted })) |> ignore
  })
  if asks {
    new_opens_said(slot, "station", fn() { open(capsule) })
  }
}

///|
/// What it runs on (new_controls' model part): while its profiles are read, a made-up model's control in its bones;
/// with nothing to run it with, the way to where models are enabled; else the model's control (model_triple's, small,
/// in a row: new_triple_node).
fn new_model_node(row : @view.View, src : Source, v : () -> Json?, address : () -> String, going : () -> Bool, asks : Bool) -> Unit {
  let pick = fn() { field(v(), "pick") }
  let none = fn() {
    let p = pick()
    p is None || items(p, "options").length() == 0 || text(v(), "runtime") == "" || field(v(), "model") is None
  }
  row.pick(fn() { if flag(v(), "waiting") { 0 } else if none() { 1 } else { 2 } }, fn(slot, which) {
    match which {
      // (its profiles read: a made-up model's, in its bones)
      0 => {
        // (breathing, as @sf.bones does: from whole to its faintest and back over a breath)
        slot.bones(By(fn() { @sf.theme().p.line })).alpha(By(fn() {
          let f = slot.cycle(@sf.breath_ms)
          let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
          1.0 - (1.0 - @sf.wait_low) * @ui.Ease::InOut.at(way)
        })) |> ignore
        new_triple_node(slot, @sfbase.sample_source, fn() { "sample" }, fn() { field(Some(new_sample_view()), "pick") }, going, false)
      }
      // nothing to run it with: the way to where models are enabled
      1 => {
        let words = fn() { @sf.t("web-main.newChat.noModels") }
        new_capsule_node(slot, words, going, fn(_) { open_page(Place("profiles")) }, fn(b) {
          capsule_words_node(b, words) |> ignore
        })
        |> ignore
      }
      _ => new_triple_node(slot, src, address, pick, going, asks)
    }
  })
}

///|
/// The model's control (model_triple's, small, in a row) in `parent`, of the pick "new" on `station` as `page` (the
/// page's `pick`) says: the maker's mark, the model's name (cut short last, never left out), then, each left out in turn
/// short of room (triple_drop_*), the runtime, how hard it thinks, fast, the account (its mark, its name, its
/// allowance), a ring while what was picked is saved, else a chevron; the hover's ground while its panel is open.
/// Pressed, its panel beside it (open_triple_panel); asked from elsewhere (open_triple), so.
fn new_triple_node(
  parent : @view.View,
  src : Source,
  station : () -> String,
  page : () -> Json?,
  going : () -> Bool,
  asks : Bool,
) -> Unit {
  let me = fn() { station() + "\u{1}new" }
  let saving = fn() { doing("pick.save/" + station() + "/new") }
  // (its panel open: followed by what follows the presenters, opened and let go in the same change)
  let open = fn() {
    @sf.presenting() |> ignore
    triple.open == me()
  }
  let value = fn() { field(page(), "value") }
  let vo = fn() { field(page(), "valueOption") }
  let account = fn() { field(page(), "account") }
  let runtime = fn() { text(value(), "runtime") }
  let can = fn() { items(page(), "options").length() > 0 && !saving() }
  let press = fn(at : @view.View) {
    if can() && !open() {
      triple.asked = ""
      open_triple_panel(src, station(), "new", @sf.beside_node(at).anchor(), page=page())
    }
  }
  let dot = fn(p : @view.View) {
    capsule_words_node(p, fn() { "·" }, style=fn() { triple_muted_xs }) |> ignore
  }
  let part = fn(p : @view.View, drop : Int, body : (@view.View) -> Unit) {
    p.box(fn(q) {
      q.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))).drops(Is(drop)) |> ignore
      body(q)
    })
    |> ignore
  }
  let capsule = new_capsule_node(parent, fn() { text(vo(), "name") }, going, press, lit=open, fn(b) {
    b.show(fn() { items(page(), "options").length() == 0 }, fn(n) {
      capsule_words_node(n, fn() { @sf.t("web-main.model.none") }, style=fn() { triple_muted_xs }) |> ignore
    })
    b.show(fn() { items(page(), "options").length() > 0 }, fn(m) {
      m.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))).min_width(Is(Some(0.0))).fits(Is(true)) |> ignore
      @sf.maker_mark_node(m, fn() { text(field(vo(), "maker"), "id") }, runtime, 14.0) |> ignore
      capsule_words_node(m, fn() {
        let model = text(value(), "model")
        if model == "" {
          @sf.t("web-main.model.pick")
        } else {
          match text(vo(), "name") {
            "" => model
            n => n
          }
        }
      }, style=fn() { triple_name_xs })
      |> ignore
      m.show(fn() { !flag(page(), "runtimeFixed") && items(vo(), "runtimes").length() > 1 }, fn(s) {
        part(s, triple_drop_runtime, fn(q) {
          dot(q)
          capsule_words_node(q, fn() { @settings.runtime_label(runtime()) }, style=fn() { triple_words_xs }) |> ignore
        })
      })
      m.show(fn() { text(value(), "effort") != "" || items(page(), "efforts").length() > 0 }, fn(s) {
        part(s, triple_drop_effort, fn(q) {
          dot(q)
          capsule_words_node(q, fn() {
            let effort = text(value(), "effort")
            if effort == "" { @sf.t("web-main.model.defaultEffort") } else { effort_text(effort) }
          }, style=fn() { triple_words_xs })
          |> ignore
        })
      })
      m.show(fn() { text(page(), "fastText") != "" }, fn(s) {
        part(s, triple_drop_effort, fn(q) {
          dot(q)
          capsule_words_node(q, fn() { text(page(), "fastText") }, style=fn() { triple_words_xs }) |> ignore
        })
      })
      m.show(fn() { account() is Some(Object(_)) }, fn(a) {
        let profile = fn() { field(account(), "profile") }
        let marked = fn() { profile() is Some(Object(_)) }
        a.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
        // (the dot before it goes with what follows it: its mark where it has one, else its name)
        a.show(marked, fn(s) {
          part(s, triple_drop_account, fn(q) {
            dot(q)
            @sf.maker_mark_node(q, fn() { text(profile(), "mark") }, runtime, 14.0) |> ignore
          })
        })
        a.box(fn(q) {
          q.row(Is(true)).gap(By(fn() { if marked() { 0.0 } else { 6.0 } })).lines_up(Is(Some(Middle)))
          .drops(Is(triple_drop_name)) |> ignore
          q.show(fn() { !marked() }, fn(d) { dot(d) })
          capsule_words_node(q, fn() { text(account(), "text") }, style=fn() {
            match text(account(), "level") {
              "amber" => triple_amber
              "red" => triple_red
              _ => triple_words_xs
            }
          })
          |> ignore
        })
        |> ignore
        a.show(marked, fn(s) {
          part(s, triple_drop_account, fn(q) { @sf.quota_chips_node(q, fn() { field(profile(), "quota") }, small=true) })
        })
      })
    })
    // what was picked on its way: a ring in place of the chevron
    b.show(saving, fn(s) { @sf.spinner_node(s, size=12.0) |> ignore })
    b.show(fn() { !saving() }, fn(c) {
      @sf.icon_node(c, "chevron-down", 12.0, By(fn() { @sf.theme().p.muted })) |> ignore
    })
  })
  if asks {
    new_opens_said(parent, "model", fn() { press(capsule) })
  }
}
