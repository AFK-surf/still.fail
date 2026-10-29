// What a link in a message is, while it is pointed at (ember web/src/Peeks.tsx LinkHover, LinkCard; ChatRef.tsx
// RefChip's RefPreview; Hover.css.ts): a small card over it. A web link's as the core reads it from the link's station
// (the `linkPreview` topic: GET /link-preview, kept, read again each time a card shows it): a page by its title, its
// site and icon, its picture over them; a GitHub pull request or issue as GitHub says it: its state, where it is and
// when it last changed, its title, who opened it and a few facts. A chat's as the workspace's list has it: its title,
// state and when it was last active, where it is, and the last thing said. Asked for as the pointer comes onto the
// link, so the card mostly opens with it there.

///|
/// A link a message's words draw (`id`: its words' own, @ui's rich text `on_link_shown`; `words`: what they say of it)
/// in a chat of station `station`: its card over it while the pointer rests on it, a file's its message's agent
/// `agent` names (file_peek), a chat's (chat_peek: as the message's `chats` say it, one archived) or a web link's.
pub fn link_peek(
  c : @ui.Ctx,
  src : Source,
  station : String,
  href : String,
  words : String,
  id : Int,
  agent? : String = "",
  chats? : Array[LinkedChat] = [],
) -> Unit {
  if station == "" {
    return
  }
  match @sf.path_of_link(href) {
    Some((path, line)) => {
      if agent != "" {
        file_peek(c, src, station, agent, path, line, id)
      }
      return
    }
    None => ()
  }
  if @sf.is_chat_link(href) {
    chat_peek(c, src, station, href, id, chats.iter().find_first(fn(l) { l.href == href }))
    return
  }
  web_peek(c, src, station, href, words, id)
}

///|
/// A web link's card over what draws it (`id`) while the pointer rests on it, as the link's station reads it (a page's
/// tile, a pull request's or an issue's card), opened at its `side` (under it, else beside a list it would cover: a
/// chat's things'); nothing for what is no web link. On the card its address to copy (the user, 2026-10-29: 快捷操作放
/// hover 的卡片上; 丑: a row of words of its own under it, gone for a mark at the card's end).
pub fn web_peek(
  c : @ui.Ctx,
  src : Source,
  station : String,
  href : String,
  words : String,
  id : Int,
  side? : @ui.Side = Bottom,
) -> Unit {
  if station == "" || !(href.has_prefix("https://") || href.has_prefix("http://")) {
    return
  }
  let scope = "link-peek/" + id.to_string()
  let params = link_params(station, href)
  peek_read(c, src, scope, "linkPreview", params, id, fn(read) {
    hover(c, scope, id, tile=!rich_link(href), side~, fn() {
      read()
      link_card(c, src, scope, params, href, words, copy=fn() { link_copy(c, href) })
    })
    |> ignore
  })
}

///|
/// What card `scope` over `id` shows (`name` with `params`): read as the pointer comes onto `id` (Peeks.tsx Hover's
/// `warm`) and while the card is drawn (`card`, given what it calls as it draws its body), let go of once neither, so
/// the next time it shows it is read again (sync.ts `cardShown`: a pull request's checks move, a file is written).
/// Held for as long as the app ran, it was read once: a pull request's card said its first checks for good.
fn peek_read(
  c : @ui.Ctx,
  src : Source,
  scope : String,
  name : String,
  params : Map[String, Json],
  id : Int,
  card : (() -> Unit) -> Unit,
) -> Unit {
  let drawn = Ref(false)
  if c.hovered(id) {
    ignore(@sfbase.hold(src, scope, name, params))
  }
  card(fn() { drawn.val = true })
  if !c.hovered(id) && !drawn.val {
    @sfbase.let_go(src, scope)
  }
}

///|
/// A web link's address to copy, on its card (link_card `copy`): 复制链接 to press, 已复制 a moment once copied, as a
/// file's path is copied (file_foot).
fn link_copy(c : @ui.Ctx, href : String) -> Unit {
  let key = "link-peek/copy/" + href
  let said = copied_paths.contains(href) &&
    (if @kit.after(c, key + "/said", true, @sf.copied_ms) {
      copied_paths.remove(href)
      false
    } else {
      true
    })
  // (its words, as a file's path's copy: the user, 2026-10-29: 图标改成文字复制链接吧)
  if @sf.panel_button(c, key, @sf.t(if said { "common.copied" } else { "common.link.copy" }), tone=Quiet) {
    c.copy_text(href)
    @kit.after(c, key + "/said", false, @sf.copied_ms) |> ignore
    copied_paths.add(href)
  }
}

///|
fn link_params(station : String, href : String) -> Map[String, Json] {
  { "station": Json::string(station), "url": Json::string(href) }
}

///|
/// Whether a link's card is a rich one (read before it shows, bars meanwhile): a GitHub pull request's or issue's
/// (Peeks.tsx RICH); any other shows its tile at once.
fn rich_link(href : String) -> Bool {
  guard href.has_prefix("https://github.com/") else { return false }
  let parts = href.view(start_offset="https://github.com/".length()).split("/").to_array()
  parts.length() >= 4 &&
  parts[0].length() > 0 &&
  parts[1].length() > 0 &&
  (parts[2] == "pull" || parts[2] == "issues") &&
  {
    let n = parts[3].to_owned()
    let digits = match n.find("?") {
      Some(i) => n.view(end_offset=i).to_owned()
      None =>
        match n.find("#") {
          Some(i) => n.view(end_offset=i).to_owned()
          None => n
        }
    }
    digits.length() > 0 && digits.iter().all(fn(ch) { ch >= '0' && ch <= '9' })
  }
}

///|
/// The card (LinkCard): a pull request's or an issue's; else a page's tile (its picture over it where it has one);
/// bars where a rich one's lines will be while it is read; `copy`, what is pressed to copy it, at its foot's end.
fn link_card(
  c : @ui.Ctx,
  src : Source,
  scope : String,
  params : Map[String, Json],
  href : String,
  words : String,
  copy? : () -> Unit = fn() {  },
) -> Unit {
  let read = @sfbase.hold(src, scope, "linkPreview", params)
  let v = match read.value {
    Some(Object(_)) as v => v
    _ => None
  }
  match text(v, "kind") {
    "github_pull_request" => change_card(c, v, true, copy)
    "github_issue" => change_card(c, v, false, copy)
    _ =>
      if v is None && read.error is None && rich_link(href) {
        // (while it is read: a made-up one's, in its bones)
        @sf.bones(c, fn() {
          change_card(c, Some({
            "repository": Json::string(@sf.sample_words(8)),
            "number": 1,
            "title": Json::string(@sf.sample_words(18)),
            "time": { "updatedAt": { "ago": Json::string(@sf.sample_words(3)) } },
          }), href.contains("/pull/"), fn() {  })
        })
      } else {
        page_tile(c, href, words, if text(v, "kind") == "page" { v } else { None }, copy)
      }
  }
}

///|
/// Where a link goes, as a card says it: its host and path (Peeks.tsx destination).
fn destination(href : String) -> String {
  let rest = match href.find("://") {
    Some(i) => href.view(start_offset=i + 3).to_owned()
    None => href
  }
  let rest = match rest.find("?") {
    Some(i) => rest.view(end_offset=i).to_owned()
    None => rest
  }
  let rest = match rest.find("#") {
    Some(i) => rest.view(end_offset=i).to_owned()
    None => rest
  }
  if rest.has_suffix("/") {
    rest.view(end_offset=rest.length() - 1).to_owned()
  } else {
    rest
  }
}

///|
/// A page's tile (Hover.css.ts tile): its icon in a 36 square on the hover's ground (GitHub's mark for a GitHub page,
/// the globe for any other), 10 from its title (two lines at most, 500) over where it goes (its site's name before it,
/// muted, one line); the page's picture over it, 16:9, where it has one.
fn page_tile(c : @ui.Ctx, href : String, words : String, page : Json?, copy : () -> Unit) -> Unit {
  let t = @sf.theme()
  let tile = fn() {
    c.box(style=peek_tile, fn() {
      c.box(style=peek_thumb, fn() {
        match @sf.data_image(text(page, "icon")) {
          "" =>
            if href.has_prefix("https://github.com/") || href.contains(".github.com/") {
              github_mark(c, peek_thumb_mark, t.p.muted)
            } else {
              @sf.icon(c, "web", size=peek_thumb_icon, color=t.p.muted) |> ignore
            }
          key => c.image(key, w=Px(peek_thumb_mark), h=Px(peek_thumb_mark), bg=0L, fit=FitContain) |> ignore
        }
      })
      |> ignore
      c.box(style=peek_tile_body, fn() {
        let title = match text(page, "title") {
          "" => if words != "" { words } else { href }
          x => x
        }
        c.text(title, style=peek_tile_title) |> ignore
        let site = text(page, "site")
        c.text(if site != "" { site + " · " + destination(href) } else { destination(href) }, style=peek_tile_url)
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  match @sf.data_image(text(page, "image")) {
    "" => tile()
    key =>
      c.box(style=peek_with_picture, fn() {
        c.image(key, w=Fill(1.0), h=Px(peek_picture_h), radius=peek_picture_r, bg=t.p.hover, fit=FitCover) |> ignore
        tile()
      })
      |> ignore
  }
  // (its copy in its foot's end corner, as a file's card's is: file_foot)
  c.box(style=peek_file_foot, fn() {
    c.box(style=peek_ref, fn() {  }) |> ignore
    copy()
  })
  |> ignore
}

///|
/// A pull request's (`pr`) or an issue's card (PullRequestCard, IssueCard): its state in a tinted pill with GitHub's
/// glyph for it, where it is (repository #n) and when it last changed, muted; its title, one line, 500; who opened it
/// and a few facts (a pull request's size and files and how its checks stand; an issue's labels and comments).
fn change_card(c : @ui.Ctx, v : Json?, pr : Bool, copy : () -> Unit) -> Unit {
  let state = text(v, "state")
  c.box(style=peek_rich, fn() {
    c.box(style=peek_change_meta, fn() {
      state_pill(
        c,
        state,
        if pr {
          pr_glyph(state)
        } else {
          issue_glyph(state)
        },
        @sf.t(if pr { pr_state_key(state) } else { issue_state_key(state) }),
      )
      c.box(style=peek_ref, fn() {
        c.text(text(v, "repository") + " #" + count(v, "number").to_string(), style=peek_meta_words) |> ignore
      })
      |> ignore
      match text(field(field(v, "time"), "updatedAt"), "ago") {
        "" => ()
        ago => c.text(ago, style=peek_meta_words) |> ignore
      }
    })
    |> ignore
    c.text(text(v, "title"), style=peek_title) |> ignore
    // its facts, and at their line's end what is pressed to copy it (in the card's bottom end corner, as a file's is)
    c.box(style=peek_facts_line, fn() {
    c.box(style=peek_facts, flow=true, line_gap=@ui.Space::S2.px(), fn() {
      match field(v, "author") {
        Some(Object(_)) as a =>
          c.box(style=peek_person, fn() {
            match @sf.data_image(text(a, "avatar")) {
              "" => c.box(style=peek_avatar, fn() {  }) |> ignore
              key => c.image(key, w=Px(peek_avatar_d), h=Px(peek_avatar_d), radius=peek_avatar_d / 2.0, bg=@sf.theme().p.hover) |> ignore
            }
            c.text(text(a, "login"), style=peek_person_words) |> ignore
          })
          |> ignore
        _ => ()
      }
      if pr {
        if field(v, "additions") is Some(Number(_, ..)) || field(v, "deletions") is Some(Number(_, ..)) {
          c.box(style=peek_chip, fn() {
            c.text("+" + count(v, "additions").to_string(), style=peek_add) |> ignore
            c.text("\u{2212}" + count(v, "deletions").to_string(), style=peek_del) |> ignore
          })
          |> ignore
        }
        if field(v, "changedFiles") is Some(Number(_, ..)) {
          fact_chip(c, @sf.t("web-main.preview.files", args=[("count", count(v, "changedFiles").to_string())]))
        }
        match field(v, "checks") {
          Some(Object(_)) as ch => {
            let (said, how) = if count(ch, "failed") > 0 {
              (@sf.t("web-main.preview.checks.failed", args=[("count", count(ch, "failed").to_string())]), "failed")
            } else if count(ch, "pending") > 0 {
              (@sf.t("web-main.preview.checks.pending", args=[("count", count(ch, "pending").to_string())]), "pending")
            } else {
              (@sf.t("web-main.preview.checks.passed", args=[("count", count(ch, "passed").to_string())]), "passed")
            }
            state_pill(c, how, None, said)
          }
          _ => ()
        }
      } else {
        for l in items(v, "labels") {
          match l {
            String(s) => fact_chip(c, s)
            _ => ()
          }
        }
        if count(v, "comments") > 0 {
          fact_chip(c, @sf.t("web-main.preview.comments", args=[("count", count(v, "comments").to_string())]))
        }
      }
    })
    |> ignore
    c.box(style=peek_copy_end, fn() { copy() }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A fact in a pill on the hover's ground (Hover.css.ts chip).
fn fact_chip(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=peek_chip, fn() { c.text(words, style=peek_meta_words) |> ignore }) |> ignore
}

///|
/// A state in a tinted pill (Hover.css.ts state): its glyph (GitHub's, 12) and its name, 500, in the state's colours:
/// open and passed green, merged and completed purple, closed and failed red, pending amber, a draft or not planned
/// grey.
fn state_pill(c : @ui.Ctx, state : String, glyph : String?, words : String) -> Unit {
  let (ink, ground) = state_colours(state)
  c.box(style=peek_state.then(@ui.style(bg=Data(ground))), fn() {
    match glyph {
      Some(d) => @sf.vector(c, "peek-state/" + state, glyph_of(d, ink), peek_glyph) |> ignore
      None => ()
    }
    c.text(words, style=peek_state_words.then(@ui.text_style(color=Data(ink)))) |> ignore
  })
  |> ignore
}

///|
/// A state's ink and ground (Hover.css.ts state's data-state).
fn state_colours(state : String) -> (Int64, Int64) {
  let p = @sf.theme().p
  match state {
    "open" | "passed" => (p.green_ink, p.green_bg)
    "merged" | "completed" => {
      let ink = if @sf.theme().dark { merged_dark } else { merged_light }
      (ink, @sf.tone_ground(ink))
    }
    "closed" | "failed" => (p.red, p.red_bg)
    "pending" => (p.warn_ink, p.amber_bg)
    _ => (p.muted, p.hover)
  }
}

///|
/// GitHub's purple for what was merged or completed (Hover.css.ts), each theme's a step deeper or lighter than GitHub's
/// (#8250df, #a371f7) to read on its ground, the purple at the theme's tone opacity (@sf.tone_ground).
let merged_light : Int64 = 0x6830BFFFL

///|
let merged_dark : Int64 = 0xC4A9FFFFL

///|
fn pr_state_key(state : String) -> String {
  match state {
    "merged" => "web-main.preview.pr.merged"
    "closed" => "web-main.preview.pr.closed"
    "draft" => "web-main.preview.pr.draft"
    _ => "web-main.preview.pr.open"
  }
}

///|
fn issue_state_key(state : String) -> String {
  match state {
    "completed" => "web-main.preview.issue.completed"
    "not_planned" => "web-main.preview.issue.notPlanned"
    "closed" => "web-main.preview.issue.closed"
    _ => "web-main.preview.issue.open"
  }
}

///|
/// GitHub's own octicons for a pull request's state (MIT, primer/octicons: Peeks.tsx PR_GLYPH), 16 by 16.
fn pr_glyph(state : String) -> String? {
  Some(
    match state {
      "draft" => "M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 14a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5ZM14 7.5a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Zm0-4.25a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0Z"
      "merged" => "M5.45 5.154A4.25 4.25 0 0 0 9.25 7.5h1.378a2.251 2.251 0 1 1 0 1.5H9.25A5.734 5.734 0 0 1 5 7.123v3.505a2.25 2.25 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.95-.218ZM4.25 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Zm8.5-4.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM5 3.25a.75.75 0 1 0 0 .005V3.25Z"
      "closed" => "M3.25 1A2.25 2.25 0 0 1 4 5.372v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.251 2.251 0 0 1 3.25 1Zm9.5 5.5a.75.75 0 0 1 .75.75v3.378a2.251 2.251 0 1 1-1.5 0V7.25a.75.75 0 0 1 .75-.75Zm-2.03-5.273a.75.75 0 0 1 1.06 0l.97.97.97-.97a.748.748 0 0 1 1.265.332.75.75 0 0 1-.205.729l-.97.97.97.97a.751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018l-.97-.97-.97.97a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l.97-.97-.97-.97a.75.75 0 0 1 0-1.06ZM2.5 3.25a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0ZM3.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm9.5 0a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z"
      _ => "M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z"
    },
  )
}

///|
/// GitHub's octicons for an issue's state (Peeks.tsx ISSUE_GLYPH).
fn issue_glyph(state : String) -> String? {
  let ring = "M8 0a8 8 0 1 1 0 16A8 8 0 0 1 8 0ZM1.5 8a6.5 6.5 0 1 0 13 0 6.5 6.5 0 0 0-13 0Z"
  let done = "M11.28 6.78a.75.75 0 0 0-1.06-1.06L7.25 8.69 5.78 7.22a.75.75 0 0 0-1.06 1.06l2 2a.75.75 0 0 0 1.06 0l3.5-3.5ZM16 8A8 8 0 1 1 0 8a8 8 0 0 1 16 0Zm-1.5 0a6.5 6.5 0 1 0-13 0 6.5 6.5 0 0 0 13 0Z"
  Some(
    match state {
      "completed" | "closed" => done
      "not_planned" => ring +
        "m9.78-2.22-5.5 5.5a.749.749 0 0 1-1.275-.326.749.749 0 0 1 .215-.734l5.5-5.5a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042Z"
      _ => "M8 9.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z" + ring
    },
  )
}

///|
/// A 16 by 16 path filled in `ink`.
fn glyph_of(d : String, ink : Int64) -> @pixels.Vector {
  {
    w: 16.0,
    h: 16.0,
    layers: [{ d, fill: ink, stroke: 0L, width: 0.0, even_odd: false, sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0 }],
  }
}

///|
/// GitHub's mark (Peeks.tsx GitHubMark), `w` wide in `ink`.
fn github_mark(c : @ui.Ctx, w : Double, ink : Int64) -> Unit {
  @sf.vector(c, "peek-github/" + ink.to_string(), glyph_of(github_path, ink), w) |> ignore
}

///|
let github_path : String = "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"

// ── a file's (Peeks.tsx FileRef, FileCard) ─────────────────────────────

///|
/// A file the session `session`'s message names by its path (its chip: @sf.path_link), on station `station`: its card
/// over its chip while the pointer rests on it, read as the pointer comes onto it; a finger taps the chip for it.
fn file_peek(
  c : @ui.Ctx,
  src : Source,
  station : String,
  session : String,
  path : String,
  line : Int?,
  id : Int,
) -> Unit {
  let scope = "file-peek/" + id.to_string()
  let params = file_peek_params(station, session, path, line)
  // (a tap opens the file itself: message.mbt open_named)
  peek_read(c, src, scope, "filePeek", params, id, fn(read) {
    hover(c, scope, id, fn() {
      read()
      file_card(c, src, scope, params, path)
    })
    |> ignore
  })
}

///|
fn file_peek_params(station : String, session : String, path : String, line : Int?) -> Map[String, Json] {
  let p : Map[String, Json] = {
    "station": Json::string(station),
    "key": Json::string(session),
    "path": Json::string(path),
  }
  match line {
    Some(n) => p["line"] = Json::number(n.to_double())
    None => ()
  }
  p
}

///|
/// The card (FileCard), as the core reads the file (the `filePeek` topic): its head (its mark, name and when it was
/// written, its whole path under them); a few of its lines, numbered, the one named marked; an image's picture; a
/// directory's first entries; and its foot: how big it is (or how many entries), and its path to copy. Why not, read
/// and refused; bars while it is read.
fn file_card(c : @ui.Ctx, src : Source, scope : String, params : Map[String, Json], path : String) -> Unit {
  let read = @sfbase.hold(src, scope, "filePeek", params)
  let v = match read.value {
    Some(Object(_)) as v => v
    _ => None
  }
  guard v is Some(_) else {
    match read.error {
      // (while it is read: a made-up file's, in its bones)
      None =>
        @sf.bones(c, fn() {
          file_shown(c, Some({
            "kind": "text",
            "name": Json::string(base_of(path)),
            "path": Json::string(path),
            "size": 1,
            "lines": { "start": 1, "text": Json::array([24, 32, 18, 28, 12].map(fn(n) { Json::string(@sf.sample_words(n)) })) },
          }))
        })
      Some(e) =>
        c.box(style=peek_rich, fn() {
          let name = base_of(path)
          file_head(c, name, path.has_suffix("/"), path, "")
          c.text(text(Some(e), "message"), style=peek_note) |> ignore
          file_foot(c, path, "")
        })
        |> ignore
    }
    return
  }
  file_shown(c, v)
}

///|
/// A file as the core read it (`v`): its head, a few of its lines, its picture or its first entries, its foot.
fn file_shown(c : @ui.Ctx, v : Json?) -> Unit {
  let kind = text(v, "kind")
  let dir = kind == "dir"
  let lines = field(v, "lines")
  let at = match field(lines, "at") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  c.box(style=peek_rich, fn() {
    let name = text(v, "name") +
      (match at {
        Some(n) => ":" + n.to_string()
        None => ""
      })
    file_head(c, name, dir, text(v, "path"), text(field(field(v, "time"), "mtime"), "ago"))
    match kind {
      "text" if items(lines, "text").length() > 0 => file_lines(c, lines, at, text(v, "name"))
      "image" =>
        match @sf.data_image("data:" + text(field(v, "image"), "type") + ";base64," + text(field(v, "image"), "data")) {
          "" => ()
          key => c.image(key, w=Fill(1.0), h=Px(peek_file_image_h), radius=peek_file_image_r, bg=@sf.theme().p.hover, fit=FitContain) |> ignore
        }
      "dir" if items(v, "entries").length() > 0 => file_entries(c, items(v, "entries"))
      _ => ()
    }
    let what = if dir {
      @sf.t("web-main.preview.items", args=[("count", count(v, "count").to_string())])
    } else {
      let size = @sf.file_size(match field(v, "size") {
        Some(Number(n, ..)) => n
        _ => 0.0
      })
      if kind == "binary" {
        size + " · " + @sf.t("web-main.preview.binary")
      } else {
        size
      }
    }
    file_foot(c, text(v, "path"), what)
  })
  |> ignore
}

///|
/// The last part of a path (a directory's without its `/`).
fn base_of(path : String) -> String {
  let parts = path.split("/").filter(fn(x) { x != "" }).to_array()
  match parts.last() {
    Some(x) => x.to_owned()
    None => path
  }
}

///|
/// Its head (FileHead): its mark (14, muted) 6 from its name (one line, 500; a directory's ending in `/`) and when it
/// was written (muted, at the end); its whole path under them in the code face (caption, muted), wrapped anywhere.
fn file_head(c : @ui.Ctx, name : String, dir : Bool, path : String, ago : String) -> Unit {
  let p = @sf.theme().p
  c.box(style=peek_file_head, fn() {
    c.box(style=peek_chat_title, fn() {
      @sf.icon(c, if dir { "folder" } else { "file" }, size=peek_file_icon, color=p.muted) |> ignore
      c.box(style=peek_ref, fn() { c.text(if dir { name + "/" } else { name }, style=peek_title) |> ignore }) |> ignore
      if ago != "" {
        c.text(ago, style=peek_meta_words) |> ignore
      }
    })
    |> ignore
    mono(c, shown_path(path), peek_file_path)
  })
  |> ignore
}

///|
/// A path as it is shown: a home directory (/Users/<name>, /home/<name>) as `~` (paths.ts shownPath).
fn shown_path(path : String) -> String {
  for home in ["/Users/", "/home/"] {
    if path.has_prefix(home) {
      let rest = path.view(start_offset=home.length()).to_owned()
      return match rest.find("/") {
        Some(i) => "~" + rest.view(start_offset=i).to_owned()
        None => "~"
      }
    }
  }
  path
}

///|
/// Its lines (lines): numbered (34 wide, muted, to their right 8 before the line), the one named on the accent's pale
/// ground, each one line; in the code face at the caption's size, coloured as its language is (`name`'s), on the
/// hover's ground, 8 round.
fn file_lines(c : @ui.Ctx, lines : Json?, at : Int?, name : String) -> Unit {
  let start = count(lines, "start")
  let words = items(lines, "text").map(fn(l) {
    match l {
      String(t) => t
      _ => ""
    }
  })
  // in the colours the core says of the file's language (`code.ink`, as the preview colours it), plain until it has
  let (_, _, lang) = @sfbase.preview_kind(name)
  let colored = if lang == "" {
    []
  } else {
    let all = words.join("\n")
    match @sf.code_ink(c, all, lang) {
      Some(Some(ink)) => @sfbase.runs_by_line(@sf.ink_runs(all, ink, @sf.theme().dark))
      _ => []
    }
  }
  c.box(style=peek_file_lines, fn() {
    for k, t in words {
      let n = start + k
      let marked = at == Some(n)
      c.box(style=if marked { peek_file_line_at } else { peek_file_line }, fn() {
        c.box(style=peek_file_line_no, fn() { mono(c, n.to_string(), peek_file_no) }) |> ignore
        c.box(style=peek_ref, fn() {
          match colored.get(k) {
            Some(runs) if runs.length() > 0 => c.rich(runs, style=peek_file_code) |> ignore
            _ => mono(c, if t != "" { t } else { " " }, peek_file_code)
          }
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A directory's first entries (entries), two to a row, each its mark and its name, on the hover's ground.
fn file_entries(c : @ui.Ctx, entries : Array[Json]) -> Unit {
  let p = @sf.theme().p
  c.box(style=peek_file_entries, fn() {
    let mut k = 0
    while k < entries.length() {
      let pair = entries[k:if k + 2 < entries.length() { k + 2 } else { entries.length() }]
      c.box(style=peek_file_entry_row, fn() {
        for e in pair {
          let name = match e {
            String(t) => t
            _ => ""
          }
          let dir = name.has_suffix("/")
          c.box(style=peek_file_entry, fn() {
            @sf.icon(c, if dir { "folder" } else { "file" }, size=peek_file_entry_icon, color=p.muted) |> ignore
            c.box(style=peek_ref, fn() {
              mono(c, if dir { name.view(end_offset=name.length() - 1).to_owned() } else { name }, peek_file_code)
            })
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      k = k + 2
    }
  })
  |> ignore
}

///|
/// Its foot (fileFoot): what it is in words (muted), and its path to copy (复制路径, saying 已复制 a moment) in the card's
/// bottom end corner, concentric with it.
fn file_foot(c : @ui.Ctx, path : String, what : String) -> Unit {
  c.box(style=peek_file_foot, fn() {
    c.box(style=peek_ref, fn() { c.text(what, style=peek_meta_words) |> ignore }) |> ignore
    let key = "file-peek/copy/" + path
    // (saying so a moment once copied: code_block's copied)
    let said = copied_paths.contains(path) &&
      (if @kit.after(c, key + "/said", true, @sf.copied_ms) {
        copied_paths.remove(path)
        false
      } else {
        true
      })
    if @sf.panel_button(c, key, @sf.t(if said { "common.copied" } else { "web-main.preview.copyPath" }), tone=Quiet) {
      c.copy_text(path)
      // pressed again while it says so: its time starts again
      @kit.after(c, key + "/said", false, @sf.copied_ms) |> ignore
      copied_paths.add(path)
    }
  })
  |> ignore
}

///|
/// Words in the code face (the web's `fontFamily: mono`), as `style` says them otherwise.
fn mono(c : @ui.Ctx, words : String, style : @ui.TextStyle) -> Unit {
  c.rich([@ui.span(words, mono=true)], style~) |> ignore
}

///|
/// The paths (and web links) copied from a card a moment ago (saying so: 已复制).
// kept across runs: a moment's words, gone as the moment is
let copied_paths : Set[String] = Set::new()

// ── a chat's (ChatRef.tsx RefPreview) ───────────────────────────────────

///|
/// What the core reads a chat's link as (`link.parse`): asked; the chat's station, its key (its id, or its agent's
/// session) and whether the link names that agent's execution history; or no chat.
priv enum Named {
  Asking
  Chat(String, String, Bool)
  NoChat
}

///|
/// The chats links name, by the station of the chat they are in and the link: asked once each, as the pointer comes
/// onto one.
// kept across runs: what the core said of each link, the same each time it is asked
let chats_named : @sf.LiveMap[String, Named] = @sf.LiveMap::new()

///|
/// The chat `href` names, read in a chat of station `here` (a link with no station of its own, `…/chats/<id>`, one of
/// its): asked the core once (chats_named).
fn chat_named(src : Source, here : String, href : String) -> Named {
  let key = here + "\u{1}" + href
  match chats_named.get(key) {
    Some(named) => return named
    None => ()
  }
  chats_named[key] = Asking
  (src.call)("link.parse", { "url": Json::string(href) }, fn(r) {
    let t = match r {
      Ok(Object(_) as v) => Some(@sfbase.link_target(v))
      _ => None
    }
    chats_named[key] = match t {
      Some(t) if t.opens == "chat" && t.chat != "" => Chat(t.workspace + "/" + t.station, t.chat, t.history != "")
      Some(t) if t.opens == "item" && t.session != "" => Chat(t.workspace + "/" + t.station, t.session, t.history != "")
      // (`…/chats/<id>` alone: the chat's own station's)
      _ =>
        match href.find("/chats/") {
          Some(i) => {
            let id = href.view(start_offset=i + 7).to_owned()
            let id = match id.find("?") {
              Some(k) => id.view(end_offset=k).to_owned()
              None => id
            }
            let id = match id.find("#") {
              Some(k) => id.view(end_offset=k).to_owned()
              None => id
            }
            let id = if id.has_suffix("/") { id.view(end_offset=id.length() - 1).to_owned() } else { id }
            if id == "" {
              NoChat
            } else {
              Chat(here, id, href.contains("?history="))
            }
          }
          None => NoChat
        }
    }
  })
  Asking
}

///|
/// A reference to a chat (`href`) in a chat of station `here`: its card over it while the pointer rests on it, read as
/// the pointer comes onto it; `linked`, the chat as its message says it.
fn chat_peek(c : @ui.Ctx, src : Source, here : String, href : String, id : Int, linked : LinkedChat?) -> Unit {
  if c.hovered(id) {
    ignore(chat_named(src, here, href))
  }
  hover(c, "chat-peek/" + id.to_string(), id, fn() { chat_card(c, src, here, href, linked) }) |> ignore
}

///|
/// The card (RefPreview), from the workspace's list: the chat's mark, its title (one line, 500) and when it was last
/// active (muted, at the end); where it is when that is another station (its mark and name), and that the link is its
/// agent's execution history; then where it stands, or the last thing said in it (three lines at most). One archived
/// (as its message says it: `linked`), its title and that it is; any other chat not in the list (another workspace's)
/// says only that; bars while the list or the link is read.
fn chat_card(c : @ui.Ctx, src : Source, here : String, href : String, linked : LinkedChat?) -> Unit {
  match linked {
    Some(l) if l.archived => {
      c.box(style=peek_rich, fn() {
        c.box(style=peek_chat_title, fn() {
          c.box(style=peek_ref, fn() { c.text(l.title, style=peek_title) |> ignore }) |> ignore
        })
        |> ignore
        if l.note != "" {
          c.text(l.note, style=peek_excerpt) |> ignore
        }
      })
      |> ignore
      return
    }
    _ => ()
  }
  let (station, key, history) = match chat_named(src, here, href) {
    Chat(station, key, history) => (station, key, history)
    Asking => {
      chat_card_sample(c)
      return
    }
    NoChat => {
      c.text(@sf.t("web-main.chatRef.previewGone"), style=peek_note) |> ignore
      return
    }
  }
  guard @sfbase.chats_of(src, @sfbase.workspace_of(here), "all").0 is Some(view) else {
    chat_card_sample(c)
    return
  }
  let mut found : ChatItem? = None
  for d in view.days {
    for i in d.items {
      if found is None && i.station == station && (i.id == key || i.session == key) {
        found = Some(i)
      }
    }
  }
  guard found is Some(item) else {
    c.text(@sf.t("web-main.chatRef.previewGone"), style=peek_note) |> ignore
    return
  }
  chat_card_of(c, item, item.station != here, history)
}

///|
/// The card of a chat found (`item`): `elsewhere` where it is another station, `history` where the link is its agent's
/// execution history.
fn chat_card_of(c : @ui.Ctx, item : ChatItem, elsewhere : Bool, history : Bool) -> Unit {
  c.box(style=peek_rich, fn() {
    c.box(style=peek_chat_title, fn() {
      chat_mark(c, @sfbase.row_tone(item)) |> ignore
      c.box(style=peek_ref, fn() { c.text(item.title, style=peek_title) |> ignore }) |> ignore
      if item.ago != "" {
        c.text(item.ago, style=peek_meta_words) |> ignore
      }
    })
    |> ignore
    if elsewhere || history {
      c.box(style=peek_meta, fn() {
        c.box(style=peek_chat_where, fn() {
          if elsewhere {
            @sf.station_mark(c, item.station_emoji, item.station_icon, peek_station_mark, @sf.theme().p.muted)
          }
          let words = [
            if elsewhere { item.station_name } else { "" },
            if history { @sf.t("web-main.chatRef.previewHistory") } else { "" },
          ]
          c.text(words.filter(fn(w) { w != "" }).join(" · "), style=peek_meta_words) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    let said = match (item.state_text, item.decision_text, item.last) {
      (Some(s), _, _) if s != "" => s
      (_, Some(s), _) if s != "" => s
      (_, _, Some(s)) => s
      _ => ""
    }
    if said != "" {
      c.text(said, style=peek_excerpt) |> ignore
    }
  })
  |> ignore
}

///|
/// The card while the chat is read (in its bones): a made-up chat's.
fn chat_card_sample(c : @ui.Ctx) -> Unit {
  @sf.bones(c, fn() {
    chat_card_of(c, sample_chat(0), false, false)
  })
}

// ── its look (Hover.css.ts) ──────────────────────────────────────────────

///|
/// A tile: its thumb and its words, 10 apart, at their tops: the thumb in the card's corner as far from its top as
/// from its side, however many lines its title takes.
// kept across runs: a value (no field of it changes)
let peek_tile : @ui.Style = @ui.css("row w=Full gap=S2_5 align=AStart")

///|
/// Its thumb: 36 square on the hover's ground, what it shows in its middle (20); in the card's corner 16 in, concentric
/// with its 23 there (Hover.css.ts's 9).
// kept across runs: a value (no field of it changes)
let peek_thumb : @ui.Style = @ui.css("w=S9 h=S9 bg=Hover align=ACenter justify=JCenter clip=true").then(
  @ui.style(radius=@sf.small_radius),
)

///|
let peek_thumb_mark : Double = 20.0

///|
let peek_thumb_icon : Double = 18.0

///|
/// Its words: its title (two lines at most, 500) over where it goes (12, muted, one line), 1 apart.
// kept across runs: a value (no field of it changes)
let peek_tile_body : @ui.Style = @ui.css("gap=SPx").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let peek_tile_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, w=Full, max_lines=2)

///|
// kept across runs: a value (no field of it changes)
let peek_tile_url : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
/// A page's picture over its tile: as wide as the card, 16:9 (Hover.css.ts tileWithPicture: 296 wide); 10 over the
/// tile.
// kept across runs: a value (no field of it changes)
let peek_with_picture : @ui.Style = @ui.style(w=Fixed(peek_picture_w), gap=S2_5)

///|
let peek_picture_w : Double = 296.0

///|
let peek_picture_h : Double = peek_picture_w * 9.0 / 16.0

///|
/// Its corner: in the card's top corners 16 in, concentric with its 23 there (Hover.css.ts's 8), as the tile's thumb.
let peek_picture_r : Double = @sf.small_corner

///|
/// A rich card: its meta, its title, its facts, 8 apart.
// kept across runs: a value (no field of it changes)
let peek_rich : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// Its meta: the state, where it is (taking what is left, cut), when it changed; 8 apart, 12, muted.
// kept across runs: a value (no field of it changes)
let peek_meta : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// A pull request's or an issue's meta, its state's pill first: in the card's top left corner as far from both its
/// edges as makes it concentric with it (@sf.capsule_in), out past the panel's padding and the card's words' to there.
// kept across runs: a value (no field of it changes)
let peek_change_meta : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter").then(
  @ui.style(mt=@sf.room_of(peek_capsule_in), ml=@sf.room_of(peek_capsule_in)),
)

///|
/// How far a capsule 20 high in a card's corner (a state's pill, a fact's, a face) stands from where its words start,
/// out past them: concentric with the card's corner.
let peek_capsule_in : Double = @sf.capsule_in(@sf.r_menu, peek_capsule_h) - @sf.panel_pad - @sf.text_in

///|
/// A capsule's height: a state's, a fact's, a face.
let peek_capsule_h : Double = 20.0

///|
// kept across runs: a value (no field of it changes)
let peek_ref : @ui.Style = @ui.css("clip=true").then(@ui.style(w=@sf.grow))

///|
// kept across runs: a value (no field of it changes)
let peek_meta_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let peek_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
/// Its facts: in a line that goes on to another, 8 apart across and between its lines (Hover.css.ts facts' gap); its
/// first (who opened it, or a fact's pill) in the card's bottom left corner, concentric with it as its state is in its
/// top left.
// kept across runs: a value (no field of it changes)
let peek_facts : @ui.Style = @ui.css("row gap=S2 align=ACenter").then(@ui.style(w=@sf.grow))

///|
/// Their line (the card's last): out to the card's bottom start corner for its first pill (peek_capsule_in), what
/// copies it at its end.
// kept across runs: a value (no field of it changes)
let peek_facts_line : @ui.Style = @ui.css("row w=Full gap=S2 align=AEnd").then(
  @ui.style(mb=@sf.room_of(peek_capsule_in), ml=@sf.room_of(peek_capsule_in)),
)

///|
/// What copies it, in the card's bottom end corner as far from both its edges as makes it concentric with it (24
/// across: peek_button_in), its line's foot out past the pills' (peek_capsule_in).
// kept across runs: a value (no field of it changes)
let peek_copy_end : @ui.Style = @ui.style(
  mr=@sf.room_of(peek_button_in),
  mb=@sf.room_of(peek_button_in - peek_capsule_in),
)

///|
/// Who opened it: their picture (round, a capsule's height) 6 from their name, in the words' colour.
// kept across runs: a value (no field of it changes)
let peek_person : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let peek_avatar : @ui.Style = @ui.css("w=S5 h=S5 radius=Full bg=Line")

///|
let peek_avatar_d : Double = peek_capsule_h

///|
// kept across runs: a value (no field of it changes)
let peek_person_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// A fact's pill: a capsule 7 in, on the hover's ground; a size's two figures 6 apart, green and red.
// kept across runs: a value (no field of it changes)
let peek_chip : @ui.Style = @ui.css("row h=S5 gap=S1_5 px=S1_5 radius=Full bg=Hover align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let peek_add : @ui.TextStyle = @ui.text_style(size=Meta, color=Positive, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let peek_del : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=false)

///|
/// A state's pill: a capsule 8 (6 before its glyph) in, its glyph 4 from its name.
// kept across runs: a value (no field of it changes)
let peek_state : @ui.Style = @ui.css("row h=S5 gap=S1 pl=S1_5 pr=S2 radius=Full align=ACenter")

///|
let peek_glyph : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let peek_state_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, wrap=false)

///|
/// A chat's head (fileTitle): its mark, its title (what is left of the line) and its time, 6 apart, in the middle.
// kept across runs: a value (no field of it changes)
let peek_chat_title : @ui.Style = @ui.css("row w=Full gap=S1_5 align=ACenter")

///|
/// Where a chat is: its station's mark (11) 4 from its name, then that it is the history, one line.
// kept across runs: a value (no field of it changes)
let peek_chat_where : @ui.Style = @ui.css("row gap=S1 align=ACenter clip=true").then(@ui.style(w=@sf.grow))

///|
let peek_station_mark : Double = 11.0

///|
/// What it says (excerpt): the card's words, three lines at most.
// kept across runs: a value (no field of it changes)
let peek_excerpt : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, w=Full, max_lines=3)

///|
/// What a card says when it has nothing to show (note): muted.
// kept across runs: a value (no field of it changes)
let peek_note : @ui.TextStyle = @ui.text_style(size=Ui, color=Muted, w=Full)

///|
/// A file's head: its title's line over its path, 2 apart.
// kept across runs: a value (no field of it changes)
let peek_file_head : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
let peek_file_icon : Double = 14.0

///|
/// Its path: the caption's size, muted, wrapped anywhere.
// kept across runs: a value (no field of it changes)
let peek_file_path : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, w=Full)

///|
/// Its lines: on the hover's ground, 8 round, 6 over and under them.
// kept across runs: a value (no field of it changes)
let peek_file_lines : @ui.Style = @ui.css("w=Full py=S1_5 radius=Sm bg=Hover clip=true")

///|
/// A line: its number and its words, 8 from its end; the one named on the accent's pale ground.
// kept across runs: a value (no field of it changes)
let peek_file_line : @ui.Style = @ui.css("row w=Full pr=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let peek_file_line_at : @ui.Style = @ui.css("row w=Full pr=S2 align=ACenter bg=AccentBg")

///|
/// Its number: 34 wide (8 of it after it), to its right.
// kept across runs: a value (no field of it changes)
let peek_file_line_no : @ui.Style = @ui.css("pr=S2 align=AEnd").then(@ui.style(w=Fixed(peek_file_no_w)))

///|
let peek_file_no_w : Double = 34.0

///|
// kept across runs: a value (no field of it changes)
let peek_file_no : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// A line's words, an entry's name: the caption's size, one line, cut.
// kept across runs: a value (no field of it changes)
let peek_file_code : @ui.TextStyle = @ui.text_style(size=Caption, color=Fg, wrap=false, w=Cut)

///|
/// An image's picture: as wide as the card, 180 high at most, contained, 8 round.
let peek_file_image_h : Double = 180.0

///|
let peek_file_image_r : Double = 8.0

///|
/// A directory's entries: two to a row, 12 apart, 2 between rows, 6 by 8 in, on the hover's ground, 8 round.
// kept across runs: a value (no field of it changes)
let peek_file_entries : @ui.Style = @ui.css("w=Full gap=S0_5 py=S1_5 px=S2 radius=Sm bg=Hover")

///|
// kept across runs: a value (no field of it changes)
let peek_file_entry_row : @ui.Style = @ui.css("row w=Full gap=S3")

///|
/// An entry: its mark (12, muted) 5 from its name.
// kept across runs: a value (no field of it changes)
let peek_file_entry : @ui.Style = @ui.css("row gap=S1_25 align=ACenter clip=true").then(@ui.style(w=@sf.grow))

///|
let peek_file_entry_icon : Double = 12.0

///|
/// Its foot: what it is in words and its path to copy, in the card's bottom end corner as far from both its edges as
/// makes it concentric with it (@sf.capsule_in: the button 24 high), out past the panel's padding and the card's words'.
// kept across runs: a value (no field of it changes)
let peek_file_foot : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter").then(
  @ui.style(mb=@sf.room_of(peek_button_in), mr=@sf.room_of(peek_button_in)),
)

///|
let peek_button_in : Double = @sf.capsule_in(@sf.r_menu, 24.0) - @sf.panel_pad - @sf.text_in

