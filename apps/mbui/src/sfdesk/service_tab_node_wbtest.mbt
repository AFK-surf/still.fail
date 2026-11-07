// A service or file tab's page remains alive across tab switches and until all of its closing nodes are gone.

///|
test "service tab node lifetime follows closing, reopening and all holders" {
  @sfbase.reset()
  sv_reset()
  let src = @sfbase.made_source()
  let r : ChatRef = { station: "ws/st", session: "s1", title: "", station_name: "" }
  let key = service_key(r.station, "job")
  let holders = @signals.signal(2)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore; sv_sweep(c, src) }, w=500.0, h=500.0, stable=false)
  @ui.set_view_app(fn(root) {
    root.show(fn() { holders.get() >= 1 }, fn(v) { service_node_held(v, src, r.station, "job") })
    root.show(fn() { holders.get() >= 2 }, fn(v) { service_node_held(v, src, r.station, "job") })
  })
  service_page_for(r.station, "job") |> ignore
  t.draw()
  assert_eq(sv_nodes[key].length(), 2)
  // Closing while the panel moves out keeps the page while either node still shows it.
  tab_let_go(src, r, "service:job")
  holders.set(1)
  t.draw()
  assert_true(@sfbase.service_pages.contains(key))
  // Opening the tab again cancels the pending close, including if the old node now leaves.
  tab_kept(r, "service:job")
  holders.set(0)
  t.draw()
  assert_true(@sfbase.service_pages.contains(key))
  // A switch away without closing keeps it too; an inactive tab closes through the usual sweep.
  tab_let_go(src, r, "service:job")
  assert_false(@sfbase.service_pages.contains(key))
  // Closing with two holders waits for the last one, even when another frame's sweep runs first.
  service_page_for(r.station, "job") |> ignore
  holders.set(2)
  t.draw()
  tab_let_go(src, r, "service:job")
  holders.set(1)
  t.draw()
  assert_true(@sfbase.service_pages.contains(key))
  holders.set(0)
  t.draw()
  assert_false(@sfbase.service_pages.contains(key))
  sv_reset()
}
