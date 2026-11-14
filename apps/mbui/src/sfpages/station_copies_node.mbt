// A station's backups of its chats in its 设置 (StationCopies, the core's copies.ts; the station's replica/), made once
// as nodes: one row saying where they are, nothing to set (the user, 2026-11-10: 「按最简单的交互方式做」). On a
// station with no chats, a backup of a station no longer there takes the row's place, with 恢复到这台, the only thing
// pressed. Everything said is the core's; the press is a call to it.

///|
/// Its backups (`copies`, the overview's) in node `b`: 备份, a row.
fn station_copies_node(b : @view.View, core : Core, address : String, copies : () -> Json?) -> Unit {
  let offers = fn() { items(copies(), "offers") }
  st_section_node(b, fn() { @sf.t("web-pages.stations.copies.section") }, fn(sec) {
    @sf.group_node(sec, fn(g) {
      g.show(fn() { offers().length() == 0 }, fn(r) { said_row_node(r, fn() { text(copies(), "line") }) })
      // (a backup to restore here: its row, 恢复到这台 at its end in the card's corner, concentric with it, asked first;
      // while it is restored, and once it is, the row only says how it goes)
      g.each(offers, fn(x) { text(Some(x), "station") + "/" + text(Some(x), "gen") }, fn(row, x) {
        let can = fn() { flag(copies(), "canRestore") && !flag(Some(x.get()), "busy") }
        row.pick(fn() { can() }, fn(r, live) {
          if live {
            @sf.corner_row_node(r, fn() { text(Some(x.get()), "line") }, fn(e) {
              @sf.button_node(e, fn() { @sf.t("web-pages.stations.copies.restore") }, fn() {
                copies_restore_confirm(core, address, Some(@signals.untracked(fn() { x.get() })))
              }, tone=Primary)
              |> ignore
            })
          } else {
            said_row_node(r, fn() { text(Some(x.get()), "line") })
          }
        })
      })
    })
  })
}

///|
/// 恢复到这台 asked first: what it restores and that the station must stay without chats until it restarts; then
/// `copies.restore` of `copy` (CopyOffer).
pub fn copies_restore_confirm(core : Core, address : String, copy : Json?) -> Unit {
  @sf.confirm(
    @sf.t("web-pages.stations.copies.restoreTitle", args=[("name", text(copy, "name"))]),
    @sf.t("web-pages.stations.copies.restoreBody", args=[("name", text(copy, "name"))]),
    @sf.t("web-pages.stations.copies.restore"),
    fn() {
      @settings.act(
        core,
        @sf.t("web-pages.stations.copies.restoreWhat"),
        "copies.restore",
        obj([
          ("station", str(address)),
          ("origin", str(text(copy, "station"))),
          ("gen", str(text(copy, "gen"))),
          ("fromStation", str(text(copy, "fromStation"))),
        ]),
      )
    },
  )
}
