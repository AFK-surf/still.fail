// What the last update brought (changelog_news's card) and what the update wants of the person (update_card's), at the
// top of the chats' lists, as nodes of the window's tree made once: as tall as they are laid out there, nothing of the
// old frame's measured for them.

///|
/// The room round a card at a list's top (news_room's): 4 over it, 10 under; its sides those of what stands over the
/// list (the theme's band_in).
fn news_room_node(parent : @view.View, card : (@view.View) -> Unit) -> Unit {
  parent.box(fn(r) {
    r
    .width_share(Is(1.0))
    .padding(By(fn() {
      let side = @sf.theme().chat_list.band_in
      (side, @ui.Space::px(S1), side, @ui.Space::px(S2_5))
    }))
    |> ignore
    r.box(fn(c) {
      // (news_card's: the ladder's card corner, on the surface, what it holds cut to it)
      c
      .width_share(Is(1.0))
      .radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
      .ground(By(fn() { @ui.tree_theme().color(Surface) }))
      .clips(Is(true))
      |> ignore
      card(c)
    })
    |> ignore
  })
  |> ignore
}

///|
/// A card's head (news_head's): its icon and its title, 6 apart, 2 over what it says under.
fn news_head_node(parent : @view.View, icon : String, title : () -> String) -> Unit {
  parent.box(fn(h) {
    h.row(Is(true)).padding(Is((0.0, 0.0, 0.0, @ui.Space::px(S0_5)))).gap(Is(@ui.Space::px(S1_5))).lines_up(Is(Some(Middle)))
    |> ignore
    @sf.icon_node(h, icon, 16.0, By(fn() { @sf.theme().p.text })) |> ignore
    @sf.words_node(h, title, fn() { news_title }) |> ignore
  })
  |> ignore
}

///|
/// The news card (changelog_news's) in `parent` while there is news: the build it is now and its first three changes,
/// a press opens the changelog; its × (tip in `tips`) lets it go at once and tells the core.
pub fn changelog_news_node(parent : @view.View, src : Source, tips : @sf.TipLayer) -> Unit {
  let lines = fn() -> Array[String] {
    let out : Array[String] = []
    for e in items(news_of(src), "entries") {
      for l in items(Some(e), "text") {
        match l {
          String(s) => out.push(s)
          _ => ()
        }
      }
    }
    out
  }
  news_room_node(parent, fn(card) {
    card.box(fn(w) {
      // (news_words's: 16 in, 44 on the right for the ×, 12 over and under, its lines 2 apart; pressed whole)
      w
      .width_share(Is(1.0))
      .padding(Is((@ui.Space::px(S4), @ui.Space::px(S3), @ui.Space::px(S11), @ui.Space::px(S3))))
      .gap(Is(@ui.Space::px(S0_5)))
      |> ignore
      @sf.pressed_node(w, fn() { open_page(Setting(@settings.Route::Changelog)) }, Is(0.0), Button, fn() {
        news_title_words(src)
      })
      news_head_node(w, "sparks", fn() { news_title_words(src) })
      for i in 0..<news_lines_most {
        w.show(fn() { lines().length() > i }, fn(l) {
          @sf.words_node(l, fn() { lines().get(i).unwrap_or("") }, fn() { news_line }) |> ignore
        })
      }
      w.show(fn() { lines().length() > news_lines_most }, fn(l) {
        @sf.words_node(
          l,
          fn() {
            @sf.t("android-settings.changelog.more", args=[("n", (lines().length() - news_lines_most).to_string())])
          },
          fn() { news_line },
        )
        |> ignore
      })
    })
    |> ignore
    // its ×, over the card in its top right corner, concentric with it (news_close_place's)
    card.box(fn(o) {
      let inset = @sf.capsule_in(@sf.card_corner, news_close_side)
      o.over(Is(true)).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Start))).padding(Is((inset, inset, inset, inset)))
      |> ignore
      @sf.icon_button_node(
        o,
        "close",
        fn() { @sf.t("android-settings.changelog.dismiss") },
        fn() {
          news_gone.set(news_of(src))
          (src.call)("changelog.seen", Json::object({}), fn(_) {  })
        },
        tips~,
        size=news_close_side,
      )
      |> ignore
    })
    |> ignore
  })
}

///|
/// The news card's title: the build it is now, where it says one.
fn news_title_words(src : Source) -> String {
  match news_of(src).bind(fn(n) { @sfbase.opt_text(Some(n), "build") }) {
    Some(b) => @sf.t("android-settings.changelog.updatedTo", args=[("build", b)])
    None => @sf.t("android-settings.changelog.updated")
  }
}

///|
/// What the update wants of the person (update_card's) in `parent`: 允许安装更新 and why; a press does it. No ×: it
/// goes once given.
pub fn update_card_node(parent : @view.View, src : Source) -> Unit {
  news_room_node(parent, fn(card) {
    card.box(fn(w) {
      // (update_card_words's: the news card's, 16 in on both sides)
      w
      .width_share(Is(1.0))
      .padding(Is((@ui.Space::px(S4), @ui.Space::px(S3), @ui.Space::px(S4), @ui.Space::px(S3))))
      .gap(Is(@ui.Space::px(S0_5)))
      |> ignore
      @sf.pressed_node(w, fn() { @sfbase.update_go(src) }, Is(0.0), Button, fn() {
        @sf.t("android-misc.updates.allow")
      })
      news_head_node(w, "download", fn() { @sf.t("android-misc.updates.allow") })
      @sf.words_node(w, fn() { @sf.t("android-misc.updates.allowWhy", args=[("app", "still.fail")]) }, fn() {
        update_card_line
      })
      |> ignore
    })
    |> ignore
  })
}
