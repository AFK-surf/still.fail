// What the last update brought and what the update wants of the person (changelog.mbt's) as nodes of the window's
// tree, made once at the top of a chats' list: the cards the old frame drew there, laid out as it laid them out, what
// they say bound to the core's `changelog` topic and the update's state as they change.

///|
/// The news card in `parent`, while there is news: the build it is now and its first changes, a
/// press opens the changelog; its × (its tip in `tips`) lets it go at once and tells the core.
pub fn changelog_news_node(parent : @view.View, src : Source, tips : @sf.TipLayer) -> Unit {
  let news = fn() { news_of(src) }
  let lines = fn() {
    let out : Array[String] = []
    for e in items(news(), "entries") {
      for l in items(Some(e), "text") {
        match l {
          String(s) => out.push(s)
          _ => ()
        }
      }
    }
    out
  }
  parent.box(fn(room) {
    // (on the line of what stands over the list, as the search's field above it: the theme's band_in from its sides)
    @sf.style_node(room, fn() { news_room.then(@ui.style(px=@sf.room_of(@sf.theme().chat_list.band_in))) })
    room.box(fn(card) {
      @sf.style_node(card, fn() { news_card })
      card.box(fn(words) {
        @sf.style_node(words, fn() { news_words })
        // PageParts.kt ChangelogNews: clickable, cut to the card's corners
        // (read out as the old frame's box was: all it says)
        @sf.rippled_node(words, fn() { open_page(Setting(@settings.Route::Changelog)) }, 0.0, fn() {
          let said = [news_title_now(news())]
          said.append(lines()[:@cmp.minimum(news_lines_most, lines().length())].to_owned())
          if lines().length() > news_lines_most {
            said.push(@sf.t("android-settings.changelog.more", args=[("n", (lines().length() - news_lines_most).to_string())]))
          }
          said.join(" ")
        })
        words.box(fn(head) {
          @sf.style_node(head, fn() { news_head })
          @sf.icon_node(head, "sparks", 16.0, By(fn() { @sf.theme().p.text })) |> ignore
          @sf.words_node(head, fn() { news_title_now(news()) }, fn() { news_title }) |> ignore
        })
        |> ignore
        for i in 0..<news_lines_most {
          words.show(fn() { i < lines().length() }, fn(l) {
            @sf.words_node(l, fn() { lines().get(i).unwrap_or("") }, fn() { news_line }) |> ignore
          })
        }
        words.show(fn() { lines().length() > news_lines_most }, fn(l) {
          @sf.words_node(
            l,
            fn() { @sf.t("android-settings.changelog.more", args=[("n", (lines().length() - news_lines_most).to_string())]) },
            fn() { news_line },
          )
          |> ignore
        })
      })
      |> ignore
      // let go: gone at once, the core told
      card.box(fn(place) {
        @sf.style_node(place, fn() { news_close_place })
        place.over(Is(true)) |> ignore
        place.box(fn(x) {
          @sf.style_node(x, fn() { news_close })
          @sf.rippled_node(x, fn() {
            news_gone.set(@signals.untracked(news))
            (src.call)("changelog.seen", Json::object({}), @sfbase.answer_unread)
          }, news_close_side / 2.0, fn() { @sf.t("android-settings.changelog.dismiss") })
          @sf.icon_node(x, "close", 16.0, By(fn() { @sf.theme().p.muted })) |> ignore
          // (over it)
          @sf.tip_node(tips, x, fn() { @sf.t("android-settings.changelog.dismiss") }, side=Top) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The news's title: the build it brought, where it says one.
fn news_title_now(news : Json?) -> String {
  match @sfbase.opt_text(news, "build") {
    Some(b) => @sf.t("android-settings.changelog.updatedTo", args=[("build", b)])
    None => @sf.t("android-settings.changelog.updated")
  }
}

///|
/// The update's card in `parent`: 允许安装更新 and why; a press does it (@sfbase.update_go). No ×: it
/// goes once given (what holds it shows it while update_card_shown).
pub fn update_card_node(parent : @view.View, src : Source) -> Unit {
  parent.box(fn(room) {
    @sf.style_node(room, fn() { news_room.then(@ui.style(px=@sf.room_of(@sf.theme().chat_list.band_in))) })
    room.box(fn(card) {
      @sf.style_node(card, fn() { news_card })
      card.box(fn(words) {
        @sf.style_node(words, fn() { update_card_words })
        @sf.rippled_node(words, fn() { @sfbase.update_go(src) }, 0.0, fn() { @sf.t("android-misc.updates.allow") })
        words.box(fn(head) {
          @sf.style_node(head, fn() { news_head })
          @sf.icon_node(head, "download", 16.0, By(fn() { @sf.theme().p.text })) |> ignore
          @sf.words_node(head, fn() { @sf.t("android-misc.updates.allow") }, fn() { news_title }) |> ignore
        })
        |> ignore
        @sf.words_node(words, fn() { @sf.t("android-misc.updates.allowWhy", args=[("app", "still.fail")]) }, fn() {
          update_card_line
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
