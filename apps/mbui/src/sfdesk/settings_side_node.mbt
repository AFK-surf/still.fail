// The settings' sidebar made once as nodes of the window's tree, beside the settings' pages on a medium or large
// screen: in the block where its sidebar stands (the block's old view leaves it bare: lists.mbt sidebar), placed where
// the block lays its sidebar out from the same (dock_side_at: off the tape where the block's move has got, on the tape
// its panel's), cut to the block's room and taking presses only there. Its top row; 返回对话, beside the update where
// one is offered; the settings' list as a sidebar's (sfpages' settings_side_rows_node), the row of the page beside it
// lit, a row pressed its page beside it in place of the one there.

///|
/// The settings' sidebar in node `n` (as large as what holds the block, over it), where `at` says the block has it: its
/// box (x, y, w, h), the block's own and its corners (what of it the block's clip lets show), whether what is in it is
/// drawn. Shown while the sidebar is the settings' (side_place) in the workspace in view.
fn settings_side_node(n : @view.View, src : Source, tips : @sf.TipLayer, at : () -> SideAt) -> Unit {
  n.show(fn() { side_place() == "settings" && at().shown }, fn(cut) {
    // (the block's clip: the block's box and corners, cut inside its line as an old view's box is, the line itself
    // drawn over all of the block: dock_edge_node)
    cut
    .clips(Is(true))
    .width(By(fn() { Some(at().block.2) }))
    .height(By(fn() { Some(at().block.3) }))
    .offset(By(fn() { (at().block.0, at().block.1) }))
    .edge(By(fn() { (at().edge.0, 0L) }))
    |> ignore
    dock_round_node(cut, at)
    cut.box(fn(side) {
      side
      .width(By(fn() { Some(at().box.2) }))
      .height(By(fn() { Some(at().box.3) }))
      .offset(By(fn() { (at().box.0 - at().block.0, at().box.1 - at().block.1) }))
      |> ignore
      side.pick(fn() { @sfbase.workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(s, _id) {
        guard @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }) is Some(w) else { return }
        let core = settings_core(src, w)
        let here = fn() { @settings.here_of(core, w.id, w.name) }
        settings_side_parts(s, src, tips, core, here, fn() {
          let a = at()
          ({ brand: a.brand, band: a.band, tape: a.tape, in_bar: a.bar, roots: @ui.tree_corner_roots_now() } : BandAt)
        }, w.id)
      })
    })
    |> ignore
  })
}

///|
/// What the settings' sidebar holds (settings_side_node's), in node `s` as wide as the sidebar: its top row, the band
/// with 返回对话 (and the update key where one is offered), the list; the band laid out as its block stands now
/// (`band_at`: where the block is, SideAt's, its linked corners the tree's), with the old views' styles.
fn settings_side_parts(
  s : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  core : @settings.Core,
  here : () -> @settings.Here,
  band_at : () -> BandAt,
  workspace : String,
) -> Unit {
  // (its top row: beside the rail only a margin; the window's buttons' row where they are in the app's top row, which
  // drags the window: side_top's)
  side_top_node(s, fn() { band_at().brand })
  let back_body = fn(r : @view.View) {
    @sf.icon_node(r, "arrow-left", settings_nav_icon, By(fn() { @sf.theme().p.muted })) |> ignore
    @sf.nav_words_node(r, fn() { @sf.t("web-pages.settings.nav.backToChats") })
  }
  let back_label = fn() { @sf.t("web-pages.settings.nav.backToChats") }
  // (the update beside 返回对话 in the band's line where one is offered; else 返回对话 the list's own first row; none
  // beside the system's tabs, 对话 one of them)
  s.pick(fn() { (update_shown(), @sf.native_on()) }, fn(b, which) {
    match which {
      (true, native) => {
        b.box(fn(band) {
          @sf.style_node(band, fn() {
            let at = band_at()
            if native {
              update_band(at~)
            } else {
              update_back_band(at~)
            }
          })
          band.box(fn(full) {
            full.row(Is(true)).grow(Is(1.0)) |> ignore
            if !native {
              @sf.band_row_node(full, fn() { false }, back_label, settings_back_pressed, back_body)
            }
          })
          |> ignore
          // (the update key: progress while it comes, then 重启更新; the progress pressed opens its details, a ready or
          // failed update does what it says: update_in_row's)
          @sf.update_key_node(
            band,
            tips,
            update_key_side,
            update_key_mark,
            fn() { update_said().0 },
            fn() { update_said().1 },
            fn() { update_said().2 },
            fn() {
              match update_now() {
                Coming(_, part) => Some(part)
                _ => None
              }
            },
            fn() {
              match @signals.untracked(update_now) {
                Coming(_, _) => @sfbase.update_dialog(src)
                _ => update_go(src)
              }
            },
          )
        })
        |> ignore
      }
      (false, false) =>
        b.box(fn(band) {
          @sf.style_node(band, fn() { @sf.side_list().then(settings_back_band) })
          @sf.nav_row_node(band, fn() { false }, back_label, settings_back_pressed, back_body, across=true) |> ignore
        })
        |> ignore
      (false, true) => ()
    }
  })
  let lit = fn() {
    match app.nav.top() {
      Setting(r) => Some(@sfpages.settings_row_of(r))
      // (the settings come to: their first row's page, settings_landing)
      Settings => Some(settings_landing)
      _ => None
    }
  }
  // (where it is scrolled to kept for the workspace while the app runs: the sidebar shown again, folded and opened or
  // come back to from the chats, where it was left, as the old view's list kept it by its key)
  let scroll = match settings_side_scrolls.get(workspace) {
    Some(s) => s
    None => {
      let s = @view.Scroll::list()
      settings_side_scrolls[workspace] = s
      s
    }
  }
  @sf.side_scroll_node(s, scroll, fn(list) {
    // (a row's page in place of the one open; on the tape brought over to show it)
    @sfpages.settings_side_rows_node(list, core, here, lit, fn(r) {
      @sfbase.history_push()
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      app.nav.push(Setting(r))
      @sfbase.show_chosen()
    })
  })
  |> ignore
}

///|
/// Where each workspace's settings' sidebar is scrolled to (settings_side_parts'), by its id.
// kept across runs: put back as a run begins (frame.mbt's reset)
let settings_side_scrolls : Map[String, @view.Scroll] = {}

