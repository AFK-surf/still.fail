// 安全, one page in every frame (web/src/cloud/Security.tsx SecuritySettings, Off, On, StationRow, DeviceRow,
// SecurityOpen; the narrow app's mobile/Security.tsx), laid out by its width: what the lock is; off, a
// card of what it is now and once on, and the way to turn it on; on, a card of how many sign and what it protects, this
// device's own pairing where it waits, the devices waiting to be confirmed, its people and their devices, its stations,
// what a web page may do, and turning it off. All of it the core's (`lock`, `lockDraft`, their words included);
// confirming a device, taking a station in and turning it off asked first (the presenters). Turning it on is a page of
// its own (SecurityOpen).

///|
/// 安全 (SecuritySettings, SecurityScreen), made once in node `v` as wide as `width` gives it, in the frame it is given:
/// the workspace's lock as the core's `lock` says it (the person's own lock is no row of its own: to people there is one
/// safe mode, the user, 2026-11-10), each part of it a block of its own come and gone as that changes (read the first time: the page as it is
/// while the lock is off, in its bones). `stint`: the page's time on top, what a station's picture is asked for on.
pub fn security_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  stint? : () -> Int = fn() { 0 },
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let ws = fn() { here().workspace }
  let topic = fn() { (core.topic)("lock", { "workspace": str(ws()) }).get() }
  let lock = fn() { topic().value }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.security.title") },
    on_back~,
    frame~,
    said?,
    width?,
    lead=fn() { @sf.t("web-pages.security.lead") },
    fn() {
      let out : Array[String] = []
      let l = lock()
      match l {
        None => out.push("waiting")
        Some(_) if !flag(l, "available") => out.push("unavailable")
        Some(_) if flag(l, "locked") => {
          let me = field(l, "me")
          out.push("on")
          // not confirmed yet, or in the lock without signing (let in before it kept a key): asked for here too
          if flag(me, "waiting") || flag(me, "unsigned") {
            out.push("pair")
          }
          // (what was just done and is not in effect: first after the state)
          if items(l, "pending").length() > 0 {
            out.push("pending")
          }
          out.push("people")
          out.push("stations")
          out.push("web")
          if flag(l, "owner") && flag(l, "signs") {
            out.push("turn-off")
          }
        }
        Some(_) => {
          out.push("off")
          if items(l, "pending").length() > 0 {
            out.push("pending")
          }
          out.push("signing")
        }
      }
      out
    },
    fn(b, key) {
      match key {
        "waiting" =>
          // (read the first time: the page as it is while the lock is off, the commonest, in its bones)
          @sf.waiting_node(
            b,
            fn(s) {
              lock_off_node(s, core.quiet(), fn() { Some({ "available": true }) })
              signing_node(s)
            },
            error=fn() {
              match topic().error {
                Some(e) => error_text(e)
                None => ""
              }
            },
          )
        "unavailable" =>
          @sf.page_card_node(b, fn(k) {
            @sf.words_node(k, fn() { @sf.t("web-pages.security.unavailable") }, fn() { sec_said }) |> ignore
          })
        "off" => lock_off_node(b, core, lock)
        "signing" => signing_node(b)
        "on" => lock_on_node(b, lock)
        "pair" => pair_node(b, core, ws, lock)
        "pending" => pending_node(b, core, ws, lock)
        "people" => people_node(b, core, ws, lock)
        "stations" => stations_node(b, core, ws, lock, stint)
        "web" =>
          @sf.section_node(b, fn() { @sf.t("web-pages.security.webTitle") }, fn(s) {
            @sf.page_card_node(s, fn(k) {
              @sf.words_node(k, fn() { @sf.t("web-pages.security.webRisk") }, fn() { sec_said }) |> ignore
            })
          })
        "turn-off" => turn_off_node(b, core, ws, here)
        _ => ()
      }
    },
  )
}

///|
/// Off (Off): the lock's state, what it is now and once on and how new devices come in, a line each with its mark; the
/// way to turn it on (where this device signs), or who may.
fn lock_off_node(parent : @view.View, core : Core, lock : () -> Json?) -> Unit {
  sec_lead_node(parent, fn(k) {
    sec_state_node(k, false, fn() { @sf.t("web-pages.security.off") })
    k.box(fn(p) {
      @sf.style_node(p, fn() { sec_points })
      sec_point_node(p, "server", fn() { @sf.t("web-pages.security.now") }, fn() { @sf.t("web-pages.security.nowRisk") })
      sec_point_node(p, "key", fn() { @sf.t("web-pages.security.then") }, fn() { @sf.t("web-pages.security.thenSafe") })
      sec_point_node(p, "devices", fn() { @sf.t("web-pages.security.newDevices") }, fn() {
        @sf.t("web-pages.security.newDevicesHow")
      })
    })
    |> ignore
    k.pick(
      fn() {
        if !flag(lock(), "owner") {
          0
        } else if flag(lock(), "canSign") {
          1
        } else {
          2
        }
      },
      fn(q, which) {
        match which {
          0 => @sf.words_node(q, fn() { @sf.t("web-pages.security.ownerOnly") }, fn() { sec_note }) |> ignore
          1 =>
            q.box(fn(a) {
              @sf.style_node(a, fn() { sec_actions })
              a.wraps(Is(Some(sec_actions_gap))) |> ignore
              @sf.button_node(a, fn() { @sf.t("web-pages.security.turnOn") }, fn() { (core.push)(SecurityOpen) }, tone=Primary)
              |> ignore
              @sf.words_node(a, fn() { @sf.t("web-pages.security.signsHere") }, fn() { sec_note_line }) |> ignore
            })
            |> ignore
          _ => @sf.words_node(q, fn() { @sf.t("web-pages.security.webCannotSign") }, fn() { sec_note }) |> ignore
        }
      },
    )
  })
}

///|
/// 签名: who signs, under the lock's state while it is off.
fn signing_node(parent : @view.View) -> Unit {
  @sf.section_node(parent, fn() { @sf.t("web-pages.security.signing") }, fn(s) {
    @sf.page_card_node(s, fn(k) {
      @sf.words_node(k, fn() { @sf.t("web-pages.security.signingWho") }, fn() { sec_said }) |> ignore
    })
  })
}

///|
/// The state's card, first on the page (lead: a card, as far from what follows as a section is): narrow a page's card,
/// wide the web's (sec_lead).
fn sec_lead_node(parent : @view.View, body : (@view.View) -> Unit) -> Unit {
  match @sf.look_node(parent) {
    Narrow => @sf.page_card_node(parent, body)
    Wide =>
      parent.box(fn(k) {
        @sf.style_node(k, fn() { sec_lead })
        body(k)
      })
      |> ignore
  }
}

///|
/// The lock's state on its line: its dot (green while `on`, else amber), what it is.
fn sec_state_node(parent : @view.View, on : Bool, words : () -> String) -> Unit {
  parent.box(fn(l) {
    @sf.style_node(l, fn() { sec_state_line })
    sec_dot_node(l, fn() { on })
    @sf.words_node(l, words, fn() { sec_state }) |> ignore
  })
  |> ignore
}

///|
/// A dot (dot: 7 round, the online green; amber where not `on`).
fn sec_dot_node(parent : @view.View, on : () -> Bool) -> Unit {
  parent.box(fn(d) { @sf.style_node(d, fn() { if on() { sec_dot_on } else { sec_dot_amber } }) }) |> ignore
}

///|
/// What it changes, a line (point): its mark 18 muted, its words and the rest quieter under them.
fn sec_point_node(parent : @view.View, icon : String, words : () -> String, rest : () -> String) -> Unit {
  parent.box(fn(l) {
    @sf.style_node(l, fn() { sec_point_line })
    l.box(fn(i) {
      @sf.style_node(i, fn() { sec_point_icon }, in_row=true)
      @sf.icon_node(i, icon, sec_point_glyph, By(fn() { @sf.theme().p.muted })) |> ignore
    })
    |> ignore
    l.box(fn(w) {
      @sf.style_node(w, fn() { sec_point_words }, in_row=true)
      @sf.words_node(w, words, fn() { sec_point_text }) |> ignore
      @sf.words_node(w, rest, fn() { sec_point_rest }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// On (On): its state with how many sign and what it protects (a line of its own under it), what that means, and
/// where this device does not sign, why.
fn lock_on_node(parent : @view.View, lock : () -> Json?) -> Unit {
  sec_lead_node(parent, fn(k) {
    sec_state_node(k, true, fn() { @sf.t("web-pages.security.on") })
    @sf.words_node(
      k,
      fn() {
        @sf.t("web-pages.security.onMeta", args=[
          ("signers", count(lock(), "signers").to_string()),
          ("stations", count(lock(), "protected").to_string()),
        ])
      },
      fn() { sec_state_meta },
    )
    |> ignore
    @sf.words_node(k, fn() { @sf.t("web-pages.security.onLead") }, fn() { sec_said }) |> ignore
    let me = fn() { field(lock(), "me") }
    k.show(fn() { !flag(lock(), "signs") && !flag(me(), "waiting") && !flag(me(), "unsigned") }, fn(n) {
      @sf.words_node(
        n,
        fn() {
          @sf.t(if flag(lock(), "canSign") { "web-pages.security.notSignerApp" } else { "web-pages.security.notSignerWeb" })
        },
        fn() { sec_note },
      )
      |> ignore
    })
  })
}

///|
/// This device's own pairing, where it waits or was let in without signing: what is so, then the steps (pair_steps,
/// the waiting page's too: its old view, hosted, as tall as it lays out, waiting for a code's boxes as nodes), last on
/// the card, in its foot corner.
fn pair_node(parent : @view.View, core : Core, ws : () -> String, lock : () -> Json?) -> Unit {
  sec_lead_node(parent, fn(k) {
    @sf.words_node(
      k,
      fn() {
        @sf.t(
          if flag(field(lock(), "me"), "unsigned") {
            "web-pages.security.upgradeTitle"
          } else {
            "web-pages.security.waitingTitle"
          },
        )
      },
      fn() { sec_state_lines },
    )
    |> ignore
    let look = @sf.look_node(k)
    // (out to the card's sides and foot, the same room inside it: its button reaching into the card's foot corner,
    // concentric with it (foot_reach), within the island's bounds, which cut what it holds)
    let pad = @sf.card_pad
    @ui.old(k, natural=true, fn(c) {
      c.box(style=@ui.style(w=Full, px=@sf.room_of(pad), pb=@sf.room_of(pad)), fn() {
        @sf.with_look(look, fn() { pair_steps(c, core, ws(), in_card=true) })
      })
      |> ignore
    })
    .margin(Is((-pad, 0.0, -pad, -pad)))
    |> ignore
  })
}

///|
/// 以下改动还没有生效: the changes this device made that no station took yet (the core's `pending`, oldest first, of the
/// workspace's lock and the person's own alike), a row each by its id, so one going leaves the others where they are.
fn pending_node(parent : @view.View, core : Core, ws : () -> String, lock : () -> Json?) -> Unit {
  @sf.section_node(parent, fn() { text(lock(), "pendingText") }, fn(s) {
    sec_group_node(s, fn(g) {
      g.each(fn() { items(lock(), "pending") }, fn(x) { text(Some(x), "id") }, fn(row, x) {
        sec_pending_node(row, core, ws, fn() { Some(x.get()) })
      })
    })
  })
}

///|
/// A change not in effect, `pv` as it is now: its mark (waiting, the time's; failed, the warning's in amber), its
/// sentence whole on as many lines as it takes, why it failed under it where the core says; a failed one's
/// `dismissText` drops it (`lock.pendingDismiss`), on a line of its own under its words. A waiting one does nothing
/// pressed: it is taken by itself as a station takes it.
fn sec_pending_node(parent : @view.View, core : Core, ws : () -> String, pv : () -> Json?) -> Unit {
  let id = fn() { text(pv(), "id") }
  let failed = fn() { text(pv(), "state") == "failed" }
  let dropping = fn() { is_doing(core, ["lock.pendingDismiss"], [("workspace", ws()), ("id", id())]) }
  let mark = fn() { if failed() { "info" } else { "wait" } }
  sec_line_node(
    parent,
    fn() { text(pv(), "text") },
    note=fn() { text(pv(), "why") },
    wraps=true,
    mark=fn(m) {
      m.box(fn(b) {
        @sf.style_node(b, fn() { sec_pending_mark }, in_row=true)
        @sf.icon_node(b, @signals.untracked(mark), sec_device_glyph, By(fn() {
          if failed() {
            @sf.theme().p.warn_ink
          } else {
            @sf.theme().p.muted
          }
        }), name_now=mark)
        |> ignore
      })
      |> ignore
    },
    // (one look at either width: the accent's words, starting where the sentence starts)
    acts=fn(a) {
      sec_tap_do_node(
        a,
        fn() { text(pv(), "dismissText") },
        fn() {
          @settings.act(
            core,
            @signals.untracked(fn() { text(pv(), "dismissText") }),
            "lock.pendingDismiss",
            obj([("workspace", str(@signals.untracked(ws))), ("id", str(@signals.untracked(id)))]),
          )
        },
        dropping,
      )
    },
    acts_shown=fn() { failed() && text(pv(), "dismissText") != "" },
  )
}

///|
/// 成员: its people (DeviceRow's people), each with what they are, and their devices by the app each is, its name over
/// the first (still.fail 桌面版: which machine each is).
fn people_node(parent : @view.View, core : Core, ws : () -> String, lock : () -> Json?) -> Unit {
  @sf.section_node(parent, fn() { @sf.t("web-pages.security.people") }, fn(s) {
    sec_group_node(s, fn(g) {
      g.each(fn() { indexed(items(lock(), "members")) }, fn(e) { e.0 }, fn(row, e) {
        let mv = fn() { Some(e.get().1) }
        let name = fn() { text(mv(), "nameText") }
        let role = fn() { text(mv(), "roleText") }
        let wide = @sf.look_node(row) is Wide
        let body = fn(p : @view.View) {
          if wide {
            sec_line_node(p, name, note=role)
          } else {
            sec_line_node(p, name, end=fn(e) { sec_end_words_node(e, role) })
          }
          // (by the app each is, its name over its first: which machine each is)
          let devices = fn() {
            let out : Array[(Int, String, Bool, Json)] = []
            for i, gr in items(mv(), "groups") {
              let gv = Some(gr)
              for j, d in items(gv, "devices") {
                out.push((out.length(), if j == 0 { text(gv, "appText") } else { "" }, i > 0 && j == 0, d))
              }
            }
            out
          }
          p.show(fn() { devices().length() > 0 }, fn(d) {
            d.box(fn(list) {
              @sf.style_node(list, fn() { if wide { sec_devices } else { @sf.full_width } })
              list.each(devices, fn(x) { x.0 }, fn(dr, x) {
                sec_device_node(
                  dr,
                  core,
                  ws,
                  fn() { Some(x.get().3) },
                  fn() { flag(lock(), "signs") },
                  over=fn() { x.get().1 },
                  apart=fn() { x.get().2 },
                )
              })
            })
            |> ignore
          })
        }
        if wide {
          row.box(fn(r) {
            @sf.style_node(r, fn() { sec_rows })
            body(r)
          })
          |> ignore
        } else {
          body(row)
        }
      })
    })
  })
}

///|
/// `a`'s each by where it stands (a list's rows keyed by their place: each made again only as what is there changes).
fn indexed(a : Array[Json]) -> Array[(Int, Json)] {
  a.mapi(fn(i, x) { (i, x) })
}

///|
/// A section's rows together: narrow, on a rounded card (ListCard); wide, on the web's card, 12 apart. A button in the
/// first or last row sits in the card's corner, concentric with it (`top_button`, `bottom_button`, as they say now).
fn sec_group_node(
  parent : @view.View,
  rows : (@view.View) -> Unit,
  top_button? : () -> Bool = fn() { false },
  bottom_button? : () -> Bool = fn() { false },
) -> Unit {
  match @sf.look_node(parent) {
    Narrow => @sf.group_node(parent, rows)
    Wide =>
      parent.box(fn(k) {
        @sf.style_node(k, fn() {
          let inset = @sf.room_of(@sf.card_foot_in(@sf.button_height()))
          let card = @sf.desk_card
          let card = if top_button() { card.then(@ui.style(pt=inset)) } else { card }
          if bottom_button() {
            card.then(@ui.style(pb=inset))
          } else {
            card
          }
        })
        k.box(fn(r) {
          @sf.style_node(r, fn() { sec_rows })
          rows(r)
        })
        |> ignore
      })
      |> ignore
  }
}

///|
/// A row of a section, going nowhere (sec_line's): `mark` before it, its title, `note` under it (narrow) or after it
/// (wide; amber while `warn`), `end` at its end; `acts`, what it does (while `acts_shown` says) where its title is
/// words of no length known (a device's name): at its end wide, narrow a line of its own under its words, the title
/// never squeezed by it. `over`: the name of the rows it starts, over it at its mark while it says one (a person's
/// devices of one app: still.fail 桌面版), `apart` from the rows before it. Its words as they are said. `wraps`: its
/// title a sentence, whole on as many lines as it takes, its note under it and what it does under them at either width
/// (beside it, that took the room the sentence needs), its mark at its first line (a change not in effect).
fn sec_line_node(
  parent : @view.View,
  title : () -> String,
  note? : () -> String = fn() { "" },
  warn? : () -> Bool = fn() { false },
  strong? : Bool = true,
  indent? : Bool = false,
  mark? : (@view.View) -> Unit,
  end? : (@view.View) -> Unit,
  acts? : (@view.View) -> Unit,
  acts_shown? : () -> Bool = fn() { true },
  over? : () -> String = fn() { "" },
  apart? : () -> Bool = fn() { false },
  wraps? : Bool = false,
) -> Unit {
  match @sf.look_node(parent) {
    Narrow => {
      parent.show(fn() { over() != "" }, fn(o) {
        o.box(fn(b) {
          @sf.style_node(b, fn() { sec_narrow_over })
          @sf.words_node(b, over, fn() { sec_narrow_over_words }) |> ignore
        })
        |> ignore
      })
      // (its title and what is at its end on its first line, its note under them as wide as its words: a line of its
      // own)
      let words = fn(w : @view.View) {
        match mark {
          Some(f) => f(w)
          None => ()
        }
        w.box(fn(lines) {
          @sf.style_node(lines, fn() { @sf.pg_row_words }, in_row=true)
          lines.box(fn(first) {
            @sf.style_node(first, fn() { sec_first_line })
            first.box(fn(t) {
              @sf.style_node(t, fn() { sec_title_room }, in_row=true)
              @sf.words_node(t, title, fn() { if wraps { sec_pending_body } else { narrow_row_title } }) |> ignore
            })
            |> ignore
            // (at the row's top: at a card's first row's end in its corner as far from its top as from its side, and
            // clear of its last's foot corner)
            match end {
              Some(f) =>
                first.box(fn(e) {
                  @sf.style_node(e, fn() { sec_end_top }, in_row=true)
                  f(e)
                })
                |> ignore
              None => ()
            }
          })
          |> ignore
          lines.show(fn() { note() != "" }, fn(n) {
            @sf.words_node(n, note, fn() { if warn() { sec_narrow_warn } else { @sf.pg_link_note } }) |> ignore
          })
        })
        |> ignore
      }
      parent.box(fn(r) {
        @sf.style_node(r, fn() {
          let row = (if indent { sec_narrow_row_in } else { @sf.pg_said_row }).then(sec_narrow_round)
          if wraps {
            row.then(sec_pending_top)
          } else {
            row
          }
        })
        match acts {
          None => words(r)
          // (its mark beside its title and its note as in a row doing nothing, what it does under them all from where
          // its words start)
          Some(f) =>
            r.box(fn(wa) {
              @sf.style_node(wa, fn() { sec_with_acts }, in_row=true)
              wa.box(fn(mw) {
                @sf.style_node(mw, fn() { if wraps { sec_mark_words.then(sec_pending_top) } else { sec_mark_words } })
                words(mw)
              })
              |> ignore
              wa.show(acts_shown, fn(a) {
                a.box(fn(ab) {
                  @sf.style_node(ab, fn() { if mark is Some(_) { sec_acts_past_mark } else { sec_acts_under } })
                  f(ab)
                })
                |> ignore
              })
            })
            |> ignore
        }
      })
      |> ignore
    }
    Wide => {
      parent.show(fn() { over() != "" }, fn(o) {
        o.box(fn(b) {
          @sf.style_node(b, fn() { if apart() { sec_over_apart } else { sec_over } })
          @sf.words_node(b, over, fn() { sec_over_words }) |> ignore
        })
        |> ignore
      })
      parent.box(fn(r) {
        @sf.style_node(r, fn() { if wraps { sec_pending_row } else { sec_row } })
        match mark {
          Some(f) => f(r)
          None => ()
        }
        r.box(fn(t) {
          @sf.style_node(t, fn() { if wraps { sec_pending_words } else { sec_row_text } }, in_row=true)
          t.show(fn() { title() != "" }, fn(w) {
            @sf.words_node(w, title, fn() {
              if wraps {
                sec_pending_ui
              } else if strong {
                sec_row_name
              } else {
                sec_row_words
              }
            })
            |> ignore
          })
          t.show(fn() { note() != "" }, fn(w) {
            @sf.words_node(w, note, fn() {
              if wraps {
                sec_pending_why
              } else if warn() {
                sec_warn
              } else {
                sec_row_meta
              }
            })
            |> ignore
          })
          match acts {
            Some(f) if wraps =>
              t.show(acts_shown, fn(a) {
                a.box(fn(ab) {
                  @sf.style_node(ab, fn() { sec_acts_under })
                  f(ab)
                })
                |> ignore
              })
            _ => ()
          }
        })
        |> ignore
        match end {
          Some(f) => f(r)
          None => ()
        }
        match acts {
          Some(f) if !wraps => r.show(acts_shown, f)
          _ => ()
        }
      })
      |> ignore
    }
  }
}

///|
/// What a row does at its end (sec_do's): narrow, words in the link's ink (a spinner in their place while it is at
/// work); wide, the web's quiet button (`primary`: its main one). `press` done as it is pressed.
fn sec_do_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  busy? : () -> Bool = fn() { false },
  primary? : Bool = false,
) -> Unit {
  match @sf.look_node(parent) {
    Narrow => sec_tap_do_node(parent, label, press, busy)
    Wide => @sf.button_node(parent, label, press, tone=if primary { Primary } else { Ghost }, busy~) |> ignore
  }
}

///|
/// What a row does as words in the link's ink (the library's tap_text_node: its words where the row's start, its room
/// to be pressed round them), a spinner in their place while it is at work: a narrow row's at its end, and a change
/// not in effect's 知道了 at either width.
fn sec_tap_do_node(parent : @view.View, label : () -> String, press : () -> Unit, busy : () -> Bool) -> Unit {
  parent.pick(busy, fn(p, at_work) {
    if at_work {
      @sf.spinner_node(p, size=sec_spin) |> ignore
    } else {
      @sf.tap_text_node(p, label, press)
    }
  })
}

///|
/// What a row says of itself at its end (受保护, a role): quieter, never cut; amber where `warn`.
fn sec_end_words_node(parent : @view.View, words : () -> String, warn? : Bool = false) -> Unit {
  let look = @sf.look_node(parent)
  @sf.words_node(parent, words, fn() {
    match (look, warn) {
      (Narrow, false) => sec_narrow_end
      (Narrow, true) => sec_narrow_end_warn
      (Wide, false) => sec_row_state
      (Wide, true) => sec_warn_state
    }
  })
  |> ignore
}

///|
/// A device in the lock (DeviceRow), `d` as it is now: its mark (a web page's, an app's), which machine it is (`over`:
/// the app over the first of its group), this device or when it was last used and the rest in a line (amber where it is
/// to be renewed soon); 续期 where this device signs (`can_renew`), 移除 (asked first) where it may take it out.
fn sec_device_node(
  parent : @view.View,
  core : Core,
  ws : () -> String,
  d : () -> Json?,
  can_renew : () -> Bool,
  over~ : () -> String,
  apart~ : () -> Bool,
) -> Unit {
  let id = fn() { text(d(), "id") }
  let renewing = fn() { is_doing(core, ["lock.renew"], [("workspace", ws()), ("device", id())]) }
  let removing = fn() { is_doing(core, ["lock.removeDevice"], [("workspace", ws()), ("device", id())]) }
  let renews = fn() { has(d(), "daysLeft") && can_renew() }
  let removes = fn() { flag(d(), "removable") }
  let kind = fn() { if text(d(), "kind") == "web" { "web" } else { "monitor" } }
  sec_line_node(
    parent,
    fn() { text(d(), "nameText") },
    note=fn() { text(d(), "metaText") },
    warn=fn() { flag(d(), "renewSoon") },
    strong=false,
    indent=true,
    over~,
    apart~,
    mark=fn(m) {
      @sf.icon_node(m, @signals.untracked(kind), sec_device_glyph, By(fn() { @sf.theme().p.muted }), name_now=kind) |> ignore
    },
    acts=fn(a) {
      a.show(renews, fn(x) {
        sec_do_node(x, fn() { @sf.t("web-pages.security.renew") }, busy=renewing, fn() {
          let now = @signals.untracked(id)
          lock_call(core, @signals.untracked(ws), "renew", @sf.t("web-pages.security.renew"), [("device", now)], done=@sf.t(
            "web-pages.security.renewed",
          ))
        })
      })
      a.show(removes, fn(x) {
        sec_do_node(x, fn() { @sf.t("web-pages.security.remove") }, busy=removing, fn() {
          remove_dialog(core, @signals.untracked(ws), @signals.untracked(id), @signals.untracked(fn() { text(d(), "fullText") }))
        })
      })
    },
    acts_shown=fn() { renews() || removes() },
  )
}

///|
/// Station: the workspace's stations and whether the lock protects each (StationRow); none, said so.
fn stations_node(parent : @view.View, core : Core, ws : () -> String, lock : () -> Json?, stint : () -> Int) -> Unit {
  @sf.section_node(parent, fn() { "Station" }, fn(s) {
    let stations = fn() { items(lock(), "stations") }
    s.pick(fn() { stations().length() == 0 }, fn(p, none) {
      if none {
        @sf.page_card_node(p, fn(k) {
          @sf.words_node(k, fn() { @sf.t("web-pages.security.noStations") }, fn() { sec_said }) |> ignore
        })
        return
      }
      let can = fn() { flag(lock(), "owner") && flag(lock(), "signs") }
      sec_group_node(
        p,
        top_button=fn() { can() && !flag(stations().get(0), "protected") },
        bottom_button=fn() { can() && !flag(stations().last(), "protected") },
        fn(g) {
          g.each(fn() { indexed(stations()) }, fn(e) { e.0 }, fn(row, e) {
            sec_station_node(row, core, ws, fn() { Some(e.get().1) }, can, stint)
          })
        },
      )
    })
  })
}

///|
/// A station and whether the lock protects it (StationRow), `sv` as it is now: a dot (green, amber where not), its mark
/// and name (wide, the two together) and why not; 受保护, or 加入 (where `can`: the owner's signing device), or 未保护 in
/// amber.
fn sec_station_node(
  parent : @view.View,
  core : Core,
  ws : () -> String,
  sv : () -> Json?,
  can : () -> Bool,
  stint : () -> Int,
) -> Unit {
  let wide = @sf.look_node(parent) is Wide
  let id = fn() { text(sv(), "id") }
  let guarded = fn() { flag(sv(), "protected") }
  let joining = fn() { is_doing(core, ["lock.joinStation"], [("workspace", ws()), ("station", id())]) }
  let emoji = fn() { text(sv(), "emoji") }
  let icon = fn() { text(sv(), "icon") }
  // (wide: its mark before its name, the two together)
  let marked = fn() { wide && @sf.has_station_mark(emoji(), icon()) }
  sec_line_node(
    parent,
    fn() { if marked() { "" } else { text(sv(), "name") } },
    note=fn() { if guarded() { "" } else { @sf.t("web-pages.security.unprotectedWhy") } },
    mark=fn(m) {
      sec_dot_node(m, guarded)
      m.show(marked, fn(n) {
        n.box(fn(b) {
          @sf.style_node(b, fn() { @sf.desk_named }, in_row=true)
          @sf.station_mark_node(b, emoji, icon, @sf.desk_mark, fn() { @sf.theme().p.text }, stint)
          @sf.words_node(b, fn() { text(sv(), "name") }, fn() { sec_row_name }) |> ignore
        })
        |> ignore
      })
    },
    end=fn(e) {
      e.pick(
        fn() {
          if guarded() {
            0
          } else if can() {
            1
          } else {
            2
          }
        },
        fn(p, which) {
          match which {
            0 => sec_end_words_node(p, fn() { @sf.t("web-pages.security.protected") })
            // (kept a button while its spinner turns, at either width; wide, out into the card's corner)
            1 =>
              p.box(fn(r) {
                if wide {
                  r.margin(Is((0.0, 0.0, @sf.card_foot_in(@sf.button_height()) - @sf.card_pad, 0.0))) |> ignore
                }
                @sf.button_node(
                  r,
                  fn() { @sf.t("web-pages.security.join") },
                  fn() { join_dialog(core, @signals.untracked(ws), @signals.untracked(id), @signals.untracked(fn() { text(sv(), "name") })) },
                  tone=Ghost,
                  busy=joining,
                )
                |> ignore
              })
              |> ignore
            _ => sec_end_words_node(p, fn() { @sf.t("web-pages.security.unprotected") }, warn=true)
          }
        },
      )
    },
  )
}

///|
/// 关闭安全模式, asked first (turn_off_dialog): wide, a danger button; narrow, at the foot, in red, a row on a card of
/// its own; a spinner while it goes, pressed none then.
fn turn_off_node(parent : @view.View, core : Core, ws : () -> String, here : () -> Here) -> Unit {
  let off = fn() { is_doing(core, ["lock.disable"], [("workspace", ws())]) }
  let press = fn() {
    if !@signals.untracked(off) {
      turn_off_dialog(core, @signals.untracked(ws), @signals.untracked(here).name)
    }
  }
  let label = fn() { @sf.t("web-pages.security.turnOff") }
  match @sf.look_node(parent) {
    Wide =>
      parent.box(fn(a) {
        @sf.style_node(a, fn() { sec_actions })
        @sf.button_node(a, label, press, tone=Danger, busy=off) |> ignore
      })
      |> ignore
    Narrow =>
      parent.box(fn(f) {
        @sf.style_node(f, fn() { acc_narrow_foot })
        @sf.group_node(f, fn(g) { @sf.danger_row_node(g, label, press, busy=off) })
      })
      |> ignore
  }
}

///|
/// 开启安全模式 (SecurityOpen, SecurityOpenScreen; the core's `lockDraft`), made once in node `v` as wide as `width`
/// gives it: its members, the devices and stations it would sign (each ticked in or out: `lock.toggle`), then 签名并开启
/// (`lock.open`); back to 安全 once it is on. Read the first time, a draft made up in its bones.
pub fn security_open_node(
  v : @view.View,
  core : Core,
  here : () -> Here,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let ws = fn() { here().workspace }
  let topic = fn() { (core.topic)("lockDraft", { "workspace": str(ws()) }).get() }
  let draft = fn() { topic().value }
  let read = fn() { !(draft() is None || flag(draft(), "loading")) }
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.security.openTitle") },
    on_back~,
    frame~,
    said?,
    width?,
    lead=fn() { @sf.t("web-pages.security.openLead") },
    fn() { if read() { ["members", "devices", "stations", "foot"] } else { ["waiting"] } },
    fn(b, key) {
      if key == "waiting" {
        @sf.waiting_node(
          b,
          fn(s) {
            for k in ["members", "devices", "stations", "foot"] {
              open_block_node(s, core.quiet(), ws, fn() { Some(open_sample()) }, k)
            }
          },
          error=fn() {
            match topic().error {
              Some(e) => error_text(e)
              None => ""
            }
          },
        )
      } else {
        open_block_node(b, core, ws, draft, key)
      }
    },
  )
}

///|
/// A block of what turning the lock on would sign (`draft`, the core's `lockDraft`, as it is now), by its key: its
/// members, the devices, the stations (each ticked in or out), 签名并开启 at its foot.
fn open_block_node(parent : @view.View, core : Core, ws : () -> String, draft : () -> Json?, key : String) -> Unit {
  let toggle = fn(id : String) {
    @settings.act(core, @sf.t("web-pages.security.turnOn"), "lock.toggle", obj([("workspace", str(@signals.untracked(ws))), ("id", str(id))]))
  }
  let checks = fn(g : @view.View, list : () -> Array[Json], name : String, note : (Json?) -> String) {
    g.each(fn() { indexed(list()) }, fn(e) { e.0 }, fn(row, e) {
      let sv = fn() { Some(e.get().1) }
      let title = fn() { text(sv(), name) }
      sec_line_node(row, title, note=fn() { note(sv()) }, mark=fn(m) {
        @sf.check_node(m, fn() { flag(sv(), "on") }, fn(_) { toggle(text(@signals.untracked(sv), "id")) }, title, disabled=fn() {
          flag(sv(), "fixed")
        })
      })
    })
  }
  match key {
    "members" =>
      @sf.section_node(
        parent,
        fn() { @sf.t("web-pages.security.members") },
        note=fn() { @sf.t("web-pages.security.peopleCount", args=[("n", items(draft(), "members").length().to_string())]) },
        fn(s) {
          sec_group_node(s, fn(g) {
            g.each(fn() { indexed(items(draft(), "members")) }, fn(e) { e.0 }, fn(row, e) {
              let mv = fn() { Some(e.get().1) }
              sec_line_node(row, fn() { text(mv(), "nameText") }, note=fn() { text(mv(), "email") }, end=fn(x) {
                sec_end_words_node(x, fn() { text(mv(), "roleText") })
              })
            })
          })
        },
      )
    "devices" =>
      @sf.section_node(
        parent,
        fn() { @sf.t("web-pages.security.devices") },
        note=fn() { @sf.t("web-pages.security.devicesWhich") },
        fn(s) { sec_group_node(s, fn(g) { checks(g, fn() { items(draft(), "devices") }, "nameText", fn(dv) { text(dv, "howText") }) }) },
      )
    "stations" =>
      @sf.section_node(parent, fn() { "Station" }, fn(s) {
        sec_group_node(s, fn(g) {
          checks(g, fn() { items(draft(), "stations") }, "name", fn(sv) {
            match (text(sv, "stateText"), text(sv, "version")) {
              ("", v) => v
              (why, "") => why
              (why, v) => why + " · " + v
            }
          })
        })
        @sf.page_note_node(s, fn() { @sf.t("web-pages.security.unprotectedNote") })
      })
    // what signing it means for a web page, cancel, 签名并开启 (foot)
    _ => {
      let wide = @sf.look_node(parent) is Wide
      let opening = fn() { is_doing(core, ["lock.open"], [("workspace", ws())]) }
      parent.box(fn(f) {
        @sf.style_node(f, fn() { if wide { sec_open_foot } else { sec_open_foot_narrow } })
        f.wraps(Is(Some(sec_open_foot_gap))) |> ignore
        @sf.words_node(
          f,
          fn() { @sf.t(if flag(draft(), "canSign") { "web-pages.security.webExpiry" } else { "web-pages.security.webCannotSign" }) },
          fn() { sec_open_foot_note },
        )
        |> ignore
        f.box(fn(a) {
          @sf.style_node(a, fn() { sec_actions })
          @sf.button_node(a, fn() { @sf.t("common.cancel") }, fn() { (core.pop)() }, tone=Ghost) |> ignore
          @sf.button_node(
            a,
            fn() { @sf.t("web-pages.security.signAndTurnOn") },
            fn() {
              @settings.act(
                core,
                @sf.t("web-pages.security.turnOn"),
                "lock.open",
                obj([("workspace", str(@signals.untracked(ws)))]),
                done=@sf.t("web-pages.security.turnedOn"),
                then=fn(_) { (core.pop)() },
              )
            },
            tone=Primary,
            busy=opening,
            disabled=fn() { !(flag(draft(), "ready") && flag(draft(), "owner") && flag(draft(), "canSign")) },
          )
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  }
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
/// 移除「…」？: a device taken out of the lock, said what that means first.
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
/// A station of the workspace not in the lock, taken in once its owner says it is theirs.
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
/// 关闭安全模式？: what turning it off gives up, a line each, and the workspace's name typed
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
        @sf.input(c, key, field=field_of(key), on_submit=fn(_) { if named() { go(c, shut) } }) |> ignore
      })
      if !typed_in.val {
        typed_in.val = true
        c.focus_editor(key)
      }
    },
    fn(c, shut) {
      @sf.button(c, @sf.t("common.cancel"), key="off-cancel", tone=Ghost, on_press=fn() {
        c.blur()
        shut()
      }) |> ignore
      @sf.button(c, @sf.t("web-pages.security.turnOff"), key="off-go", tone=DangerSolid, disabled=!named(), on_press=fn() {
        go(c, shut)
      }) |> ignore
    },
  )
}

///|
/// One thing turning it off gives up: its icon, muted, beside a line of it.
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
/// A spinner in place of what a narrow row does (@settings.spinner's 14).
let sec_spin : Double = 14.0

///|
/// The lines apart where a row of buttons and words goes on under (sec_actions' gap, sec_open_foot's).
let sec_actions_gap : Double = 10.0

///|
let sec_open_foot_gap : Double = 12.0

///|
/// A change not in effect (pending_node's rows): wide, a card's row with its words from its top; narrow, a group's row
/// so. Its mark beside its first line, its words the body's on as many lines as they take, why under them the meta's.
// kept across runs: a value (no field of it changes)
let sec_pending_row : @ui.Style = @ui.style(row=true, w=Full, min_h=Fixed(sec_row_least), gap=S3, align=AStart)

///|
// kept across runs: a value (no field of it changes)
let sec_pending_top : @ui.Style = @ui.css("align=AStart")

///|
// kept across runs: a value (no field of it changes)
let sec_pending_mark : @ui.Style = @ui.css("pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let sec_pending_words : @ui.Style = @ui.style(w=@sf.grow, gap=S1)

///|
// kept across runs: a value (no field of it changes)
let sec_pending_ui : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let sec_pending_body : @ui.TextStyle = @sf.body.then(@sf.full_words)

///|
// kept across runs: a value (no field of it changes)
let sec_pending_why : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, w=Full)

///|
/// A narrow row's first line: its title and what is at its end (row_lines' row_first_line).
// kept across runs: a value (no field of it changes)
let sec_first_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// The state's card, first on the page, as far from what follows as a section is (lead: a card, 28 under it).
// kept across runs: a value (no field of it changes)
let sec_lead : @ui.Style = @sf.desk_card.then(@ui.css("mb=S7"))

///|
/// The state (state: the body's 14 in 500; its meta the ui's 13 muted).
// kept across runs: a value (no field of it changes)
let sec_state : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, weight=Medium, color=Fg, wrap=false)

///|
/// The state said alone on its line, the card's first (pair_node's: waiting to be approved, to be made trusted): on
/// as many lines as it takes where the card has not the room, never cut (a phone's words set larger, in English).
// kept across runs: a value (no field of it changes)
let sec_state_lines : @ui.TextStyle = sec_state.then(@sf.in_lines)

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
/// group 14 from the one before it (deviceGroup, deviceApp).
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
/// Narrow: a person's device under them, further in; what it is amber where
/// it is to be renewed soon; what a row says at its end (the secondary's, on one line).
// kept across runs: a value (no field of it changes)
let sec_narrow_row_in : @ui.Style = @ui.css("row w=Full pl=S6 pr=S3 py=S2_5 gap=S3 radius=Inner align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sec_narrow_round : @ui.Style = @ui.style(radius=@sf.group_row_end_radius)

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
