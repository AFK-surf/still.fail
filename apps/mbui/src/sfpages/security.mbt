// 安全, one page in every frame (web/src/cloud/Security.tsx SecuritySettings, Off, On, StationRow, DeviceRow,
// SecurityOpen; the narrow app's mobile/Security.tsx), laid out by its width (page_look.mbt): what the lock is; off, a
// card of what it is now and once on, and the way to turn it on; on, a card of how many sign and what it protects, this
// device's own pairing where it waits, the devices waiting to be confirmed, its people and their devices, its stations,
// what a web page may do, and turning it off. All of it the core's (`lock`, `lockDraft`, their words included);
// confirming a device, taking a station in and turning it off asked first (the presenters). Turning it on is a page of
// its own (SecurityOpen).

///|
/// A section's rows together: narrow, on a rounded card (ListCard); wide, on the web's card, 12 apart. A button in
/// the first or last row sits in the card's corner, concentric with it.
fn sec_group(c : @ui.Ctx, look : Look, body : () -> Unit, top_button? : Bool = false, bottom_button? : Bool = false) -> Unit {
  match look {
    Narrow => @sf.group(c, body)
    Wide => {
      let inset = @sf.room_of(@sf.card_foot_in(@sf.button_height()))
      let card = @sf.desk_card
      let card = if top_button { card.then(@ui.style(pt=inset)) } else { card }
      let card = if bottom_button { card.then(@ui.style(pb=inset)) } else { card }
      c.box(style=card, fn() { c.box(style=sec_rows, body) |> ignore }) |> ignore
    }
  }
}

///|
/// A row of a section, going nowhere: `mark` before it, its title, `note` under it (narrow) or after it (wide; amber
/// where `warn`; where `drops`, whole or not at all where the row has not the room), `end` at its end; `acts`, what
/// it does where its title is words of no length known (a device's name): at its end wide, narrow a line of its own
/// under its words, the title never squeezed by it (docs/ui-panels.md 字和别的东西并排时). `over`: the name of the
/// rows it starts, over it at its mark (a person's devices of one app: still.fail 桌面版), `apart` from the rows
/// before it.
fn sec_line(
  c : @ui.Ctx,
  look : Look,
  title : String,
  note? : String = "",
  warn? : Bool = false,
  strong? : Bool = true,
  drops? : Bool = false,
  indent? : Bool = false,
  mark? : () -> Unit,
  end? : () -> Unit,
  acts? : () -> Unit,
  over? : String = "",
  apart? : Bool = false,
) -> Unit {
  match look {
    Narrow => {
      if over != "" {
        c.box(style=sec_narrow_over, fn() { c.text(over, style=sec_narrow_over_words) |> ignore }) |> ignore
      }
      let words = fn() {
        match mark {
          Some(f) => f()
          None => ()
        }
        // its title and what is at its end on its first line, its note under them as wide as its words (a line of its
        // own)
        @sf.row_lines(c, fn() {
          c.box(style=sec_title_room, fn() { c.text(title, style=narrow_row_title) |> ignore }) |> ignore
          // (at the row's top: at a card's first row's end in its corner as far from its top as from its side, and
          // clear of its last's foot corner)
          match end {
            Some(f) => c.box(style=sec_end_top, f) |> ignore
            None => ()
          }
        }, fn() {
          if note != "" {
            c.text(note, style=if warn { sec_narrow_warn } else { @sf.pg_link_note }) |> ignore
          }
        })
      }
      c.box(style=if indent { sec_narrow_row_in } else { @sf.pg_said_row }, fn() {
        match acts {
          None => words()
          // (its mark beside its title and its note as in a row doing nothing, what it does under them all from
          // where its words start)
          Some(f) =>
            c.box(style=sec_with_acts, fn() {
              c.box(style=sec_mark_words, words) |> ignore
              c.box(style=if mark is Some(_) { sec_acts_past_mark } else { sec_acts_under }, f) |> ignore
            })
            |> ignore
        }
      })
      |> ignore
    }
    Wide => {
      if over != "" {
        c.box(style=if apart { sec_over_apart } else { sec_over }, fn() { c.text(over, style=sec_over_words) |> ignore })
        |> ignore
      }
      c.box(style=sec_row, fn() {
        match mark {
          Some(f) => f()
          None => ()
        }
        c.box(style=sec_row_text, keep=true, fn() {
          if title != "" {
            c.text(title, style=if strong { sec_row_name } else { sec_row_words }) |> ignore
          }
          if note != "" {
            let style = if warn { sec_warn } else { sec_row_meta }
            if drops {
              c.box(style=sec_meta_slot, drop=sec_drop_meta, fn() { c.text(note, style=sec_row_state) |> ignore }) |> ignore
            } else {
              c.text(note, style~) |> ignore
            }
          }
        })
        |> ignore
        match end {
          Some(f) => f()
          None => ()
        }
        match acts {
          Some(f) => f()
          None => ()
        }
      })
      |> ignore
    }
  }
}

///|
/// What a row says of itself at its end (受保护, a role): quieter, never cut.
fn sec_end_words(c : @ui.Ctx, look : Look, words : String, warn? : Bool = false) -> Unit {
  let style = match (look, warn) {
    (Narrow, false) => sec_narrow_end
    (Narrow, true) => sec_narrow_end_warn
    (Wide, false) => sec_row_state
    (Wide, true) => sec_warn_state
  }
  c.text(words, style~) |> ignore
}

///|
/// A section whose title says how many it holds (narrow: after its title, quieter; wide: the accent's count beside it).
pub fn sec_section(c : @ui.Ctx, look : Look, title : String, count~ : Int, body : () -> Unit) -> Unit {
  match look {
    Narrow => {
      @sf.heading(c, title + " · " + count.to_string())
      body()
    }
    Wide =>
      @sf.section(
        c,
        title,
        title_after=fn() {
          c.box(style=sec_count, fn() { c.text(count.to_string(), style=sec_count_words) |> ignore }) |> ignore
        },
        body,
      )
  }
}

///|
/// 移除「…」？ (Security.tsx's): a device taken out of the lock, said what that means first.
pub fn remove_dialog(core : Core, ws : String, device : String, name : String) -> Unit {
  @sf.confirm(
    @sf.t("web-pages.security.removeTitle", args=[("name", name)]),
    @sf.t("web-pages.security.removeBody"),
    @sf.t("web-pages.security.remove"),
    danger=true,
    fn() {
      lock_call(core, ws, "removeDevice", @sf.t("web-pages.security.remove"), [("device", device)], done=@sf.t("web-pages.security.removed"))
    },
  )
}

///|
/// 开启安全模式 (SecurityOpen, SecurityOpenScreen; the core's `lockDraft`): its members, the devices and stations it
/// would sign (each ticked in or out: `lock.toggle`), then 签名并开启 (`lock.open`); back to 安全 once it is on.
pub fn security_open_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let look = look_of(c)
  let ws = here.workspace
  let topic = (core.topic)("lockDraft", { "workspace": str(ws) })
  let draft = topic.value
  let blocks : Array[() -> Unit] = []
  if draft is None || flag(draft, "loading") {
    blocks.push(fn() {
      block_waiting(
        c,
        fn() {
          for b in open_blocks(c, core.quiet(), look, ws, Some(open_sample())) {
            b()
          }
        },
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
    })
  } else {
    blocks.append(open_blocks(c, core, look, ws, draft))
  }
  @sf.page(c, on_back=core.pop, frame~, "security-open",
    @sf.t("web-pages.security.openTitle"),
    blocks,
    lead=@sf.t("web-pages.security.openLead"),
  )
}


///|
/// What turning the lock on would sign (`draft`, the core's `lockDraft`): its members, the devices and stations (each
/// ticked in or out), and 签名并开启 at its foot.
fn open_blocks(c : @ui.Ctx, core : Core, look : Look, ws : String, draft : Json?) -> Array[() -> Unit] {
  let blocks : Array[() -> Unit] = []
  let toggle = fn(id : String) {
    @settings.act(core, @sf.t("web-pages.security.turnOn"), "lock.toggle", obj([("workspace", str(ws)), ("id", str(id))]))
  }
  let members = items(draft, "members")
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.security.members"),
      heads=true,
      note=@sf.t("web-pages.security.peopleCount", args=[("n", members.length().to_string())]),
      fn() {
        sec_group(c, look, fn() {
          for m in members {
            let mv = Some(m)
            sec_line(c, look, text(mv, "nameText"), note=text(mv, "email"), end=fn() { sec_end_words(c, look, text(mv, "roleText")) })
          }
        })
      },
    )
  })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.security.devices"), heads=true, note=@sf.t("web-pages.security.devicesWhich"), fn() {
      sec_group(c, look, fn() {
        for d in items(draft, "devices") {
          let dv = Some(d)
          sec_check_line(c, look, "draft-device/" + text(dv, "id"), text(dv, "nameText"), text(dv, "howText"), dv, fn() {
            toggle(text(dv, "id"))
          })
        }
      })
    })
  })
  blocks.push(fn() {
    @sf.section(c, "Station", heads=true, fn() {
      sec_group(c, look, fn() {
        for st in items(draft, "stations") {
          let sv = Some(st)
          let note = match (text(sv, "stateText"), text(sv, "version")) {
            ("", v) => v
            (why, "") => why
            (why, v) => why + " · " + v
          }
          sec_check_line(c, look, "draft-station/" + text(sv, "id"), text(sv, "name"), note, sv, fn() { toggle(text(sv, "id")) })
        }
      })
      @sf.page_note(c, @sf.t("web-pages.security.unprotectedNote"))
    })
  })
  // what signing it means for a web page, cancel, 签名并开启 (foot)
  blocks.push(fn() {
    c.box(style=if look == Wide { sec_open_foot } else { sec_open_foot_narrow }, flow=true, fn() {
      c.text(
        @sf.t(if flag(draft, "canSign") { "web-pages.security.webExpiry" } else { "web-pages.security.webCannotSign" }),
        style=sec_open_foot_note,
      )
      |> ignore
      c.box(style=sec_actions, fn() {
        if @sf.button(c, @sf.t("common.cancel"), key="lock-open-cancel", tone=Ghost) {
          (core.pop)()
        }
        let opening = is_doing(core, ["lock.open"], [("workspace", ws)])
        if @sf.button(
            c,
            @sf.t("web-pages.security.signAndTurnOn"),
            key="lock-open",
            tone=Primary,
            busy=opening,
            disabled=!(flag(draft, "ready") && flag(draft, "owner") && flag(draft, "canSign")),
          ) {
          @settings.act(
            core,
            @sf.t("web-pages.security.turnOn"),
            "lock.open",
            obj([("workspace", str(ws))]),
            done=@sf.t("web-pages.security.turnedOn"),
            then=fn(_) { (core.pop)() },
          )
        }
      })
      |> ignore
    })
    |> ignore
  })
  blocks
}

///|
/// What turning the lock on would sign, made up, for what its page shows while it is read (open_blocks in its bones):
/// three people, two devices, two stations.
fn open_sample() -> Json {
  let line = fn(i : Int, name : Int, note : Int) -> Json {
    {
      "id": Json::string("sample" + i.to_string()),
      "nameText": Json::string(@sf.sample_words(name)),
      "name": Json::string(@sf.sample_words(name)),
      "email": Json::string(@sf.sample_words(note)),
      "howText": Json::string(@sf.sample_words(note)),
      "roleText": Json::string(@sf.sample_words(2)),
    }
  }
  {
    "members": [line(0, 3, 12), line(1, 4, 14), line(2, 3, 10)],
    "devices": [line(3, 6, 9), line(4, 5, 11)],
    "stations": [line(5, 4, 0), line(6, 5, 0)],
  }
}

///|
/// A row ticked in or out (SecurityOpen's label with its checkbox): the box, its title and what it is under it (narrow)
/// or after it (wide); fixed ones can't be changed. `toggle` goes on when it is pressed.
fn sec_check_line(c : @ui.Ctx, look : Look, key : String, title : String, note : String, v : Json?, toggle : () -> Unit) -> Unit {
  sec_line(c, look, title, note~, mark=fn() {
    let on = flag(v, "on")
    let now = @kit.checkbox(c, key, if on { On } else { Off }, label=title, disabled=flag(v, "fixed")).value
    if (now == On) != on {
      toggle()
    }
  })
}

///|
/// A station of the workspace not in the lock, taken in once its owner says it is theirs (Security.tsx's join dialog).
pub fn join_dialog(core : Core, ws : String, station : String, name : String) -> Unit {
  @sf.confirm(
    @sf.t("web-pages.security.joinTitle", args=[("name", name)]),
    @sf.t("web-pages.security.joinBody"),
    @sf.t("web-pages.security.join"),
    fn() {
      lock_call(
        core,
        ws,
        "joinStation",
        @sf.t("web-pages.security.join"),
        [("station", station)],
        done=@sf.t("web-pages.security.joined", args=[("name", name)]),
      )
    },
  )
}

///|
/// 关闭安全模式？ (Security.tsx TurnOff): what turning it off gives up, a line each, and the workspace's name typed
/// before it can go (`lock.disable`, Enter too); written in as it opens.
pub fn turn_off_dialog(core : Core, ws : String, name : String) -> Unit {
  let key = "lock-off/" + (desk_dialogs.val + 1).to_string()
  let named = fn() { field_of(key).text().trim(chars=" \t\n").to_owned() == name.trim(chars=" \t\n").to_owned() }
  let typed_in = Ref(false)
  let go = fn(c : @ui.Ctx, shut : () -> Unit) {
    c.blur()
    shut()
    @settings.act(core, @sf.t("web-pages.security.turnOff"), "lock.disable", obj([("workspace", str(ws))]))
  }
  open_dialog(
    @sf.t("web-pages.security.turnOffTitle"),
    description=@sf.t("web-pages.security.turnOffBody"),
    fn(c, shut) {
      c.box(style=sec_points, fn() {
        sec_off_point(c, "server", @sf.t("web-pages.security.nowRisk"))
        sec_off_point(c, "devices", @sf.t("web-pages.security.turnOffApproval"))
        sec_off_point(c, "key", @sf.t("web-pages.security.turnOffVault"))
      })
      |> ignore
      @sf.field(c, @sf.t("web-pages.security.turnOffType", args=[("name", name)]), fn() {
        if @sf.input(c, key, field=field_of(key)).submitted && named() {
          go(c, shut)
        }
      })
      if !typed_in.val {
        typed_in.val = true
        c.focus_editor(key)
      }
    },
    fn(c, shut) {
      if @sf.button(c, @sf.t("common.cancel"), key="off-cancel", tone=Ghost) {
        c.blur()
        shut()
      }
      if @sf.button(c, @sf.t("web-pages.security.turnOff"), key="off-go", tone=DangerSolid, disabled=!named()) {
        go(c, shut)
      }
    },
  )
}

///|
/// One thing turning it off gives up (Security.css.ts point): its icon, muted, beside a line of it.
fn sec_off_point(c : @ui.Ctx, icon : String, words : String) -> Unit {
  let t = @sf.theme()
  c.box(style=sec_point_line, fn() {
    c.box(style=sec_point_icon, fn() { @sf.icon(c, icon, size=sec_point_glyph, color=t.p.muted) |> ignore }) |> ignore
    c.box(style=sec_point_words, fn() { c.text(words, style=sec_point_text) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// The sizes: what it changes, its marks 18 in a column of 20; a device's mark 16.
let sec_point_glyph : Double = 18.0

///|
let sec_device_glyph : Double = 16.0

///|
let sec_dot_side : Double = 7.0

///|
let sec_row_least : Double = 30.0

///|
/// The state's card, first on the page, as far from what follows as a section is (lead: a card, 28 under it).
// kept across runs: a value (no field of it changes)
let sec_lead : @ui.Style = @sf.desk_card.then(@ui.css("mb=S7"))

///|
/// The state (state: the body's 14 in 500; its meta the ui's 13 muted).
// kept across runs: a value (no field of it changes)
let sec_state : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_state_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_state_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sec_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sec_actions : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// What it changes (points: 10 apart; each its mark in a 20 column, 8 from its words, the body's 14).
// kept across runs: a value (no field of it changes)
let sec_points : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let sec_point_line : @ui.Style = @ui.css("row w=Full gap=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let sec_point_icon : @ui.Style = @ui.css("w=S5 pt=SPx align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_point_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let sec_point_text : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sec_point_rest : @ui.TextStyle = @ui.text_style(size=Meta, leading=L7, color=Muted, w=Full)

///|
/// A card's rows (rows: 12 apart; a row 30 high at least, 12 apart, the ui's 13; its words in a line, the name in 500,
/// what it is the meta's 12 muted 6 after it); a person's devices 42 in, 8 apart.
// kept across runs: a value (no field of it changes)
let sec_rows : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// A narrow row's title, taking what its first line leaves what is at its end.
// kept across runs: a value (no field of it changes)
let sec_title_room : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A narrow row with what it does under it: its mark and its words, then that.
// kept across runs: a value (no field of it changes)
let sec_with_acts : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A narrow row's mark and words over what it does, as a row doing nothing has them.
// kept across runs: a value (no field of it changes)
let sec_mark_words : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// What a narrow row does (a device's: 续期, 移除), a line of its own under its words (Security.tsx's mDeviceActs: 6
/// under them, 20 apart).
// kept across runs: a value (no field of it changes)
let sec_acts_under : @ui.Style = @ui.css("row gap=S5 pt=S1_5")

///|
/// The same from where its words start, past its mark (a device's glyph, `sec_device_glyph`, and the row's 12 after it).
// kept across runs: a value (no field of it changes)
let sec_acts_past_mark : @ui.Style = @ui.css("row gap=S5 pt=S1_5 pl=S7")

///|
/// What a narrow row has at its end, at its top.
// kept across runs: a value (no field of it changes)
let sec_end_top : @ui.Style = @ui.css("row h=Full gap=S2 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let sec_row : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(sec_row_least), gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let sec_row_text : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S1_5, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let sec_row_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_row_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_row_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)

///|
/// What leaves a waiting device's row first, short of room: which device it is and when it asked; whole on its line.
let sec_drop_meta : Int = 1

///|
// kept across runs: a value (no field of it changes)
let sec_meta_slot : @ui.Style = @ui.css("row")

///|
/// What a row says of itself at its end (受保护): the meta's words, never cut.
// kept across runs: a value (no field of it changes)
let sec_row_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sec_warn : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=WarnInk, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let sec_warn_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=WarnInk, wrap=false)

///|
/// A person's devices, 42 in, 8 apart; by app, its name (the meta's 12 in 500, muted, on a line) over the first, a
/// group 14 from the one before it (Security.tsx's devices, deviceGroup, deviceApp).
// kept across runs: a value (no field of it changes)
let sec_devices : @ui.Style = @ui.css("w=Full pl=S10 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let sec_over : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let sec_over_apart : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let sec_over_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false, w=Cut)

///|
/// The count of those waiting (count: the meta's 12 in 500 on the accent's ground, 7 in, round).
// kept across runs: a value (no field of it changes)
let sec_count : @ui.Style = @ui.css("px=S1_5 radius=Full bg=AccentBg")

///|
// kept across runs: a value (no field of it changes)
let sec_count_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=AccentText, wrap=false)

///|
/// A station's dot (dot: 7 round, the online green, amber where it is not protected).
// kept across runs: a value (no field of it changes)
let sec_dot_on : @ui.Style = @ui.style(w=Fixed(sec_dot_side), h=Fixed(sec_dot_side), radius=Full, bg=Positive)

///|
// kept across runs: a value (no field of it changes)
let sec_dot_amber : @ui.Style = sec_dot_on.then(@ui.css("bg=Warn"))

///|
/// A card's words (the web's sub: the ui's 13, muted).
// kept across runs: a value (no field of it changes)
let sec_said : @ui.TextStyle = desk_muted

///|
/// A note beside a button, as wide as it is (the row goes on under where it has not the room).
// kept across runs: a value (no field of it changes)
let sec_note_line : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
/// Narrow: a person's device under them, further in (Security.tsx's mobile DeviceRow: 14 more); what it is amber where
/// it is to be renewed soon; what a row says at its end (the secondary's, on one line).
// kept across runs: a value (no field of it changes)
let sec_narrow_row_in : @ui.Style = @ui.css("row w=Full pl=S6 pr=S3 py=S2_5 gap=S3 radius=Inner align=ACenter")

///|
/// Narrow: the app a person's devices under it are, at their marks (sec_narrow_row_in's), 6 over the first (Security.tsx's
/// mobile mDeviceApp): the secondary's in 500, on a line.
// kept across runs: a value (no field of it changes)
let sec_narrow_over : @ui.Style = @ui.css("w=Full pl=S6 pr=S3 pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_over_words : @ui.TextStyle = @sf.secondary.then(@ui.text_style(weight=Medium, wrap=false, w=Cut))

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_warn : @ui.TextStyle = @sf.pg_link_note.then(@ui.text_style(color=WarnInk))

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_end : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_end_warn : @ui.TextStyle = sec_narrow_end.then(@ui.text_style(color=WarnInk))

///|
/// 开启安全模式's foot (foot: what signing means for a web page, then cancel and 签名并开启; narrow, 16 from the page's
/// sides, 4 in its room).
// kept across runs: a value (no field of it changes)
let sec_open_foot : @ui.Style = @ui.css("row w=Full pt=S5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_open_foot_narrow : @ui.Style = @ui.css("row w=Full px=S1 pt=S4 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_open_foot_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)
