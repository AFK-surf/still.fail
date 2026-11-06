// The station facts shared by the station selector and sidebar, made in the window's retained tree.

///|
/// The online dot and running count, or the offline ring and last-seen summary. Both station data and the theme are
/// followed for as long as the row is present.
pub fn station_state_node(parent : @view.View, station : () -> Json?) -> Unit {
  let online = fn() { flag(station(), "online") }
  let running = fn() { number(field(field(station(), "overview"), "counts"), "running") }
  let words = fn() {
    if online() {
      @sf.t("web-pages.stations.page.runningShort", args=[("n", running().to_int().to_string())])
    } else {
      text(station(), "summary")
    }
  }
  parent.box(fn(row) {
    @sf.style_node(row, fn() { station_state_box })
    row.box(fn(dot) {
      dot.width(Is(Some(6.0))).height(Is(Some(6.0))).radius(Is(3.0))
      .ground(By(fn() { if online() { @ui.tree_theme().color(Positive) } else { 0L } }))
      .edge(By(fn() { if online() { (0.0, 0L) } else { (1.5, @ui.tree_theme().color(Muted)) } }))
      .says(By(fn() { Some(@view.said(Text, label=@sf.t(if online() { "web-pages.stations.online" } else { "web-pages.stations.offline" }))) })) |> ignore
    }) |> ignore
    row.show(fn() { !online() || running() > 0.0 }, fn(slot) {
      @sf.words_node(slot, words, fn() { if online() { station_words().then(station_busy) } else { station_words() } })
      .says(By(fn() { Some(@view.said(Text, label=words())) })) |> ignore
    })
  }) |> ignore
}

///|
/// While online, two fixed-height lines: the station's meters and this device's path and round-trip time to it. The
/// stationNet topic belongs to the current station's node, and is let go when it changes, goes offline or is removed.
/// Meter details use the window's `tips` layer when supplied.
pub fn station_figures_node(
  parent : @view.View,
  src : Source,
  station : () -> Json?,
  tips? : @sf.TipLayer,
) -> Unit {
  parent.each(
    fn() { if flag(station(), "online") { [text(station(), "station")] } else { [] } },
    fn(id) { id },
    fn(lines, id) {
      let station_id = @signals.untracked(fn() { id.get() })
      let params : Map[String, Json] = { "station": Json::string(station_id) }
      @sfbase.hold_node(lines, src, "stationNet", params) |> ignore
      @sf.list_row_line_node(lines, fn(line) {
        @sf.meter_chips_node(line, fn() { items(field(station(), "host"), "meters") }, brief=true, tips?)
      })
      @sf.list_row_line_node(lines, fn(line) {
        let words = fn() {
          let net = (src.topic)("stationNet", params).value
          match net {
            Some(Object(_)) =>
              match text(field(net, "rtt"), "text") {
                "" => text(net, "path")
                rtt => text(net, "path") + " · " + rtt
              }
            _ => @sf.t("web-pages.stations.netNone")
          }
        }
        @sf.words_node(line, words, station_words).says(By(fn() { Some(@view.said(Text, label=words())) })) |> ignore
      })
    },
  )
}
