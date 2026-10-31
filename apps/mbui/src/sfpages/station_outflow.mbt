///|
/// A station page's 数据外流 (docs/data-outflow.md): the programs of its machine asking for its data, then those
/// granted it. A request is a row naming the program, who signed it as the system said, what it said of itself and
/// when it asked; for an admin of the workspace (`answers`), each kind it asks for with what it gives away, a tick each,
/// and 这个 workspace 的所有 station where it asks for that, then 不允许 and 允许, which asks once more, saying all
/// that is given and to whom, before it is. A grant is a row naming it, who signed it, what it may read and how far,
/// who allowed it and when, and when it last read, 取消授权 at its end, asked first. Nothing when there are none (or
/// the station is from before them).
fn station_outflow(c : @ui.Ctx, core : Core, station : String, answers : Bool) -> Unit {
  let view = outflow_view(core, station)
  let requests = items(view, "requests")
  let grants = items(view, "grants")
  if requests.length() == 0 && grants.length() == 0 {
    return
  }
  st_section(c, @sf.t("web-main.outflow.title"), description=@sf.t("web-main.outflow.lead"), fn() {
    for q in requests {
      outflow_request(c, core, station, Some(q), answers)
    }
    if grants.length() > 0 {
      @sf.group(c, fn() {
        for g in grants {
          outflow_grant(c, core, station, Some(g))
        }
      })
    }
  })
}

///|
/// The kinds an admin took out of a request, and its whole workspace (`<station>/<request>/<kind>`, `…/workspace`):
/// ticked again, gone from here.
// kept across runs: said by the ticks; reset (pages.mbt) empties it
let outflow_left : Map[String, Bool] = {}

///|
fn outflow_request(c : @ui.Ctx, core : Core, station : String, qv : Json?, answers : Bool) -> Unit {
  let id = text(qv, "id")
  let program = text(qv, "program")
  let at = station + "/" + id + "/"
  let scopes = items(qv, "scopes")
  let whole = text(qv, "reach") == "workspace"
  @sf.group(c, fn() {
    let notes = [text(qv, "signedText"), text(qv, "said"), text(qv, "askedText")].filter(fn(s) { s != "" })
    if !answers {
      notes.push(@sf.t("web-main.outflow.waitingAdmin"))
    }
    @sf.link_row(c, "outflow-ask/" + at, program, note=join(notes, " · "), goes=false, lead=fn() { st_row_mark(c, "key") })
    |> ignore
    if !answers {
      return
    }
    for s in scopes {
      let kind = text(Some(s), "id")
      let on = !outflow_left.contains(at + kind)
      if @sf.check_row(c, "outflow-ask/" + at + kind, text(Some(s), "text"), on, note=text(Some(s), "why")) != on {
        outflow_tick(at + kind, on)
      }
    }
    if whole {
      let on = !outflow_left.contains(at + "workspace")
      if @sf.check_row(
          c,
          "outflow-ask/" + at + "workspace",
          @sf.t("web-main.outflow.wholeWorkspace"),
          on,
          note=@sf.t("web-main.outflow.wholeWorkspaceNote"),
        ) !=
        on {
        outflow_tick(at + "workspace", on)
      }
    }
    let kept = scopes.filter(fn(s) { !outflow_left.contains(at + text(Some(s), "id")) })
    let workspace = whole && !outflow_left.contains(at + "workspace")
    c.box(style=outflow_answer, fn() {
      if @sf.button(c, @sf.t("web-main.outflow.refuse"), key="outflow-refuse/" + at, tone=Ghost) {
        @settings.act(
          core,
          @sf.t("web-main.outflow.refuse"),
          "outflow.answer",
          obj([("station", str(station)), ("id", str(id)), ("allow", Json::boolean(false))]),
          done=@sf.t("web-main.outflow.refused", args=[("program", program)]),
        )
      }
      if @sf.button(c, @sf.t("web-main.outflow.allow"), key="outflow-allow/" + at, tone=Primary, disabled=kept.length() == 0) {
        let kinds = join(
          kept.map(fn(s) { @sf.t("web-main.outflow.kind", args=[("kind", text(Some(s), "text"))]) }),
          @sf.t("web-main.outflow.and"),
        )
        let where_ = @sf.t(if workspace { "web-main.outflow.whereWorkspace" } else { "web-main.outflow.whereStation" })
        let signer = text(qv, "signedText")
        @sf.confirm(
          @sf.t("web-main.outflow.allowConfirm", args=[("program", program)]),
          @sf.t("web-main.outflow.allowBody", args=[("kinds", kinds), ("where", where_), ("program", program), ("signer", signer)]),
          @sf.t("web-main.outflow.allow"),
          fn() {
            @settings.act(
              core,
              @sf.t("web-main.outflow.allow"),
              "outflow.answer",
              obj([
                ("station", str(station)),
                ("id", str(id)),
                ("allow", Json::boolean(true)),
                ("scopes", Json::array(kept.map(fn(s) { str(text(Some(s), "id")) }))),
                ("workspace", Json::boolean(workspace)),
              ]),
              done=@sf.t("web-main.outflow.allowed", args=[("program", program)]),
            )
          },
        )
      }
    })
    |> ignore
  })
}

///|
fn outflow_tick(key : String, was : Bool) -> Unit {
  if was {
    outflow_left[key] = true
  } else {
    outflow_left.remove(key)
  }
}

///|
fn outflow_grant(c : @ui.Ctx, core : Core, station : String, gv : Json?) -> Unit {
  let id = text(gv, "id")
  let program = text(gv, "program")
  let kinds = join(items(gv, "scopes").map(fn(s) { text(Some(s), "text") }), @sf.t("web-main.outflow.and"))
  @sf.link_row(
    c,
    "outflow/" + id,
    program,
    note=join([text(gv, "signedText"), kinds, text(gv, "reachText"), text(gv, "grantedText"), text(gv, "lastReadText")], " · "),
    goes=false,
    lead=fn() { st_row_mark(c, "key") },
    tail=fn() {
      if @sf.button(c, @sf.t("web-main.outflow.revoke"), key="outflow-revoke/" + station + "/" + id, tone=Ghost) {
        @sf.confirm(
          @sf.t("web-main.outflow.revokeConfirm", args=[("program", program)]),
          @sf.t("web-main.outflow.revokeBody"),
          @sf.t("web-main.outflow.revoke"),
          danger=true,
          fn() {
            @settings.act(
              core,
              @sf.t("web-main.outflow.revoke"),
              "outflow.revoke",
              obj([("station", str(station)), ("id", str(id))]),
              done=@sf.t("web-main.outflow.revoked", args=[("program", program)]),
            )
          },
        )
      }
    },
  )
  |> ignore
}

///|
/// 不允许 and 允许 at a request's end, 8 apart, the last in its list card's foot corner concentric with it, as a small
/// panel's buttons stand (panel_corner_foot: a list card's corner and padding are a small panel's).
// kept across runs: a value (no field of it changes)
let outflow_answer : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter justify=JEnd pt=S2_5").then(@sf.panel_corner_foot())

///|
/// The programs granted the station's data, and those asking for it, as the core holds them: none from a station from
/// before them.
fn outflow_view(core : Core, station : String) -> Json? {
  let view = (core.topic)("outflowGrants", { "station": str(station) }).value
  if flag(view, "supported") { view } else { None }
}
