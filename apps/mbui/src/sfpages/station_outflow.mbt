///|
/// A station page's 数据外流 (docs/data-outflow.md): the programs of its machine granted its data, each a row naming
/// it, who signed it as the system said (an unsigned one in red), what it may read, when it was granted and last read,
/// and 取消授权 at its end, asked first. Nothing when there are none (or the station is from before them).
fn station_outflow(c : @ui.Ctx, core : Core, station : String) -> Unit {
  let grants = outflow_grants(core, station)
  if grants.length() == 0 {
    return
  }
  st_section(c, @sf.t("web-main.outflow.title"), description=@sf.t("web-main.outflow.lead"), fn() {
    @sf.group(c, fn() {
      for g in grants {
        let gv = Some(g)
        let id = text(gv, "id")
        let program = text(gv, "program")
        let kinds = join(items(gv, "scopes").map(fn(s) { text(Some(s), "text") }), @sf.t("web-main.outflow.and"))
        @sf.link_row(
          c,
          "outflow/" + id,
          program,
          note=join([text(gv, "signedText"), kinds, text(gv, "grantedText"), text(gv, "lastReadText")], " · "),
          goes=false,
          lead=fn() { st_row_mark(c, "key") },
          tail=fn() {
            if !flag(gv, "signed") {
              @sf.pill(c, @sf.t("web-main.outflow.unsigned"), tone=Red)
            }
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
    })
  })
}

///|
/// The programs granted the station's data, as the core holds them: none from a station from before them.
fn outflow_grants(core : Core, station : String) -> Array[Json] {
  let view = (core.topic)("outflowGrants", { "station": str(station) }).value
  if flag(view, "supported") { items(view, "grants") } else { [] }
}
