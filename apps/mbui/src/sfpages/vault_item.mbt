// A secret's page, one in every frame (设置 › 密钥 › it; web/src/cloud/VaultItem.tsx, Vault.css.ts; the narrow app's
// mobile/Vault.tsx VaultItemScreen), laid out by its width (page_look.mbt), as a profile's is: what it is and where it
// is kept; in a library not locked, that it is not encrypted and the way to lock it; its content masked until shown
// (each field's eye opens it, `vault.open`, and shows that field), copied; how agents may use it; when they did, each
// use leading to its chat. 编辑 opens it first, then its editor (the presenters'). What it says is the core's
// (vault-words.ts); what it held goes as its page is left (the settings package's opened item).

///|
/// The field whose eye opened the item, shown as it opens ("" none), by item.
// kept across runs: said by the fields' eyes; vault_item_reset empties it
let vi_reveal : Map[String, String] = {}

///|
/// The fields shown in the clear, by item and field.
// kept across runs: said by the fields' eyes; vault_item_reset empties it
let vi_shown : Map[String, Bool] = {}

///|
fn vault_item_reset() -> Unit {
  vi_reveal.clear()
  vi_shown.clear()
}

///|
/// The page (VaultItemPage, VaultItemScreen).
pub fn vault_item_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame, vault : String, item : String) -> Unit {
  let t = @sf.theme()
  let look = look_of(c)
  let ws = here.workspace
  let view = (core.topic)("vaults", { "workspace": str(ws) }).value
  let list = (core.topic)("vaultItems", { "workspace": str(ws), "vault": str(vault) }).value
  let uses = (core.topic)("vaultUses", { "workspace": str(ws), "vault": str(vault), "item": str(item) }).value
  let key = "vault-item/" + vault + "/" + item
  let back = @sf.t("web-pages.vault.title")
  guard view is Some(_) && list is Some(_) else {
    @sf.page(c, on_back=core.pop, frame~, key, back, [
      fn() {
        block_waiting(c, fn() {
          let sample = item_blocks(c, core.quiet(), look, ws, key, "sample", None, Some(item_sample()), Some({ "uses": Json::array(uses_sample()) }), false, None, false, fn(_) {  })
          for b in sample {
            b()
          }
        })
      },
    ])
  }
  let v = items(view, "vaults").search_by(fn(x) { text(Some(x), "id") == vault })
  let row = items(list, "items").search_by(fn(x) { text(Some(x), "id") == item })
  guard v is Some(vi) && row is Some(ri) else {
    @sf.page(c, on_back=core.pop, frame~, key, back, [fn() { @sf.page_note(c, @sf.t("web-pages.vault.empty")) }])
  }
  let vv = Some(items(view, "vaults")[vi])
  let rv = Some(items(list, "items")[ri])
  let plain = flag(view, "plain")
  let opened = @settings.opened_plain(item)
  let opening = @settings.item_opening(item)
  // opened, then `then` with what it holds
  let open = fn(then : (Json) -> Unit) { @settings.open_item(core, ws, item, then) }
  let edit = fn(p : Json) {
    match rv {
      Some(r) => vault_editor_dialog(core, ws, vault, Some((r, p)), plain~)
      None => ()
    }
  }
  // 编辑: opened first (its content is what is edited)
  let edit_pressed = fn() {
    match opened {
      Some(p) => edit(p)
      None => open(fn(p) { edit(p) })
    }
  }
  let editing_busy = opening && vi_reveal.get(item) is None
  let blocks = item_blocks(c, core, look, ws, key, item, vv, rv, uses, plain, opened, opening, open)
  let sub = join([text(rv, "kindText"), @sf.t("web-pages.vault.storedOn", args=[("station", text(vv, "stationName"))])], " · ")
  match look {
    Wide =>
      @sf.page(c, on_back=core.pop, frame~, key, text(rv, "name"), blocks, small=@sf.t("web-pages.vault.title"), head=fn() {
        c.box(style=pf_head, fn() {
          c.box(style=pf_mark, fn() {
            @sf.icon(c, @settings.kind_icon(text(rv, "kind")), size=vi_mark_glyph, color=t.p.text) |> ignore
          })
          |> ignore
          c.box(style=pf_identity, fn() {
            c.text(text(rv, "name"), style=pf_name) |> ignore
            c.text(sub, style=pf_sub) |> ignore
          })
          |> ignore
          if @sf.button(c, @sf.t("common.edit"), key=key + "/edit", tone=Ghost, icon="edit", busy=editing_busy) {
            edit_pressed()
          }
        })
        |> ignore
      })
    // (narrow: its name the large title, what it is and where under it, 编辑 at the title's end)
    Narrow =>
      @sf.page(c, on_back=core.pop, frame~, key, text(rv, "name"), blocks, lead=sub, actions=fn() {
        if editing_busy {
          @sf.spinner(c, size=pf_spin) |> ignore
        } else if @sf.icon_button(c, "edit", key=key + "/edit", round=true, label=@sf.t("common.edit")) {
          edit_pressed()
        }
      })
  }
}

///|
/// What an item's page holds (its item `rv`, in vault `vv`): a library not locked said so, its content (each field's
/// eye where its value is), how agents may use it, when they used it (`uses`).
fn item_blocks(
  c : @ui.Ctx,
  core : Core,
  look : Look,
  ws : String,
  key : String,
  item : String,
  vv : Json?,
  rv : Json?,
  uses : Json?,
  plain : Bool,
  opened : Json?,
  opening : Bool,
  open : ((Json) -> Unit) -> Unit,
) -> Array[() -> Unit] {
  let section = fn(title : String, body : () -> Unit) {
    @sf.section(c, title, heads=true, fn() {
      match look {
        Narrow => @sf.page_card(c, body)
        Wide => body()
      }
    })
  }
  let blocks : Array[() -> Unit] = []
  // in a library not locked: that it is not encrypted, the way to lock it
  if plain {
    blocks.push(fn() {
      @sf.page_card(c, fn() {
        c.text(@sf.t("web-pages.vault.risk.title"), style=vi_risk_title) |> ignore
        c.text(@sf.t("web-pages.vault.risk.body", args=[("station", text(vv, "stationName"))]), style=desk_muted) |> ignore
        // (its button in its foot corner, concentric with it)
        c.box(style=pf_card_foot.then(@sf.foot_reach(@sf.button_height())), fn() {
          @sf.card_foot_words(fn() {
            if @sf.button(c, @sf.t("web-pages.vault.lib.turnOn"), key=key + "/lock", tone=Primary) {
              (core.push)(Security)
            }
          })
        })
        |> ignore
      })
    })
  }
  // its content: each field's eye where its value is, before it is opened as after
  blocks.push(fn() {
    section(@sf.t("web-pages.vault.content"), fn() {
      c.box(style=vi_fields, fn() {
        match opened {
          Some(_) =>
            for f in @settings.opened_fields(item) {
              let fv = Some(f)
              let fk = text(fv, "key")
              if vi_reveal.get(item) == Some(fk) {
                vi_shown[item + "/" + fk] = true
                vi_reveal.remove(item)
              }
              secret_field(c, item + "/" + fk, text(fv, "label"), text(fv, "value"), flag(fv, "secret"), flag(fv, "mono"))
            }
          None =>
            for f in items(rv, "shut") {
              let fv = Some(f)
              let fk = text(fv, "key")
              c.box(style=vi_secret, fn() {
                c.text(text(fv, "label"), style=vi_label) |> ignore
                c.box(style=vi_secret_line, fn() {
                  c.rich([@ui.span(text(fv, "value"), mono=true)], style=vi_value) |> ignore
                  if opening {
                    @sf.spinner(c, size=pf_spin) |> ignore
                  } else if @sf.icon_button(c, "eye", key=key + "/show/" + fk, corner=vi_key_corner, label=@sf.t("web-pages.vault.show")) {
                    vi_reveal[item] = fk
                    open(fn(_) {  })
                  }
                })
                |> ignore
              })
              |> ignore
            }
        }
      })
      |> ignore
    })
  })
  // how agents may use it
  blocks.push(fn() {
    section(@sf.t("web-pages.vault.forAgents"), fn() {
      if !flag(rv, "listed") {
        c.text(@sf.t("web-pages.vault.notForAgents"), style=desk_muted) |> ignore
        return
      }
      c.box(style=vi_facts, fn() {
        // (its terms' column 96 wide, or as wide as the widest of them in this language: words of a length known,
        // whole)
        let terms = [@sf.t("web-pages.vault.how"), @sf.t("web-pages.vault.editor.env"), @sf.t("web-pages.vault.editor.lasts")]
        let term_w = terms.fold(init=vi_term_w, fn(m, w) { dmax(m, c.words_across(w, vi_term).ceil()) })
        let fact = fn(term : String, value : () -> Unit) {
          c.box(style=vi_fact, fn() {
            c.box(style=@ui.style(w=Fixed(term_w)), fn() { c.text(term, style=vi_term) |> ignore }) |> ignore
            value()
          })
          |> ignore
        }
        fact(@sf.t("web-pages.vault.how"), fn() { c.text(text(rv, "howText"), style=vi_fact_value) |> ignore })
        if text(rv, "env") != "" {
          fact(@sf.t("web-pages.vault.editor.env"), fn() { c.rich([@ui.span(text(rv, "env"), mono=true)], style=vi_fact_value) |> ignore })
        }
        fact(@sf.t("web-pages.vault.editor.lasts"), fn() { c.text(text(rv, "lastsText"), style=vi_fact_value) |> ignore })
      })
      |> ignore
    })
  })
  // when agents used it
  blocks.push(fn() {
    section(@sf.t("web-pages.vault.uses.title"), fn() {
      match uses {
        None => @sf.waiting(c, fn() { item_uses(c, core.quiet(), ws, key, uses_sample()) })
        Some(_) if items(uses, "uses").length() == 0 => c.text(@sf.t("web-pages.vault.uses.none"), style=desk_muted) |> ignore
        Some(_) => item_uses(c, core, ws, key, items(uses, "uses"))
      }
    })
  })
  blocks
}

///|
/// When agents used an item (`uses`), each: its chat (opening it), how, when.
fn item_uses(c : @ui.Ctx, core : Core, ws : String, key : String, uses : Array[Json]) -> Unit {
  c.box(style=vi_uses, fn() {
    for i, u in uses {
      let uv = Some(u)
      c.box(style=vi_use, fn() {
        c.box(style=vi_use_text, fn() {
          c.box(style=pf_name_line, fn() {
            let chat = match opt_text(uv, "chatTitle") {
              Some(x) if x != "" => x
              _ => text(uv, "session")
            }
            let station = text(uv, "station")
            if station != "" {
              let id = c.id(key + "/use/" + i.to_string())
              if c.clicked(id) {
                (core.open_chat)(ws + "/" + station, text(uv, "session"), chat)
              }
              // (underlined under the pointer, or a finger's press: words in the words' colour, lit)
              c.box(id~, fn() {
                c.rich([@ui.span(chat, underline=c.lit(id))], style=vi_chat, allow_ellipsis=true) |> ignore
              })
              |> ignore
            } else {
              c.text(chat, style=vi_chat, allow_ellipsis=true) |> ignore
            }
            if flag(uv, "denied") {
              @sf.pill(c, @sf.t("web-pages.vault.uses.denied"), tone=Red)
            }
          })
          |> ignore
          if opt_text(uv, "command") is Some(_) {
            c.rich([@ui.span(text(uv, "howText"), mono=true)], style=desk_note) |> ignore
          } else {
            c.text(text(uv, "howText"), style=desk_note) |> ignore
          }
        })
        |> ignore
        c.text(match text(field(uv, "at"), "full") { "" => text(field(uv, "at"), "ago"); x => x }, style=vi_use_time) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// An item made up, for what its page shows while it is read (item_blocks in its bones): two fields, how agents use
/// it, two uses.
fn item_sample() -> Json {
  let w = fn(n : Int) { Json::string(@sf.sample_words(n)) }
  {
    "listed": true,
    "howText": w(8),
    "lastsText": w(6),
    "shut": [{ "key": "a", "label": w(3), "value": w(12) }, { "key": "b", "label": w(4), "value": w(16) }],
  }
}

///|
fn uses_sample() -> Array[Json] {
  [10, 7].map(fn(n) {
    Json::object({
      "chatTitle": Json::string(@sf.sample_words(n)),
      "howText": Json::string(@sf.sample_words(14)),
      "at": { "full": Json::string(@sf.sample_words(5)) },
    })
  })
}

///|
/// A field of an item opened (Secret): its name over its value, masked until shown where it is secret (its eye), copied
/// as it is (a secret's taken off the clipboard 30 s later).
fn secret_field(c : @ui.Ctx, key : String, label : String, value : String, secret : Bool, mono : Bool) -> Unit {
  let shown = !secret || vi_shown.get(key).unwrap_or(false)
  c.box(style=vi_secret, fn() {
    c.text(label, style=vi_label) |> ignore
    c.box(style=vi_secret_line, fn() {
      let words = if shown { value } else { "•".repeat(@cmp.minimum(@cmp.maximum(value.length(), 8), 20)) }
      c.rich([@ui.span(words, mono~)], style=if shown && value.contains("\n") { vi_value_lines } else { vi_value }) |> ignore
      if secret &&
        @sf.icon_button(c, "eye", key=key + "/eye", corner=vi_key_corner, label=if shown { @sf.t("web-pages.vault.hide") } else { @sf.t("web-pages.vault.show") }, on=shown) {
        vi_shown[key] = !shown
      }
      if @sf.icon_button(c, "copy", key=key + "/copy", corner=vi_key_corner, label=@sf.t("common.copy")) {
        if secret {
          c.copy_secret(value, clear_ms=vi_copied_life)
        } else {
          c.copy_text(value)
        }
      }
    })
    |> ignore
  })
  |> ignore
}

// ── styles (Vault.css.ts) ───────────────────────────────────────────────

///|
/// How long a secret copied stays on the clipboard (copySecret: 30 s).
let vi_copied_life : Double = 30000.0

///|
let vi_mark_glyph : Double = 24.0

///|
// kept across runs: a value (no field of it changes)
let vi_risk_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=WarnInk, w=Full)

///|
/// Its fields (fields: 14 apart; a field its name over its line, 4 apart).
// kept across runs: a value (no field of it changes)
let vi_fields : @ui.Style = @ui.css("w=Full gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let vi_secret : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let vi_label : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let vi_secret_line : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let vi_value : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false, w=@sf.grow, max_lines=1)

///|
// kept across runs: a value (no field of it changes)
let vi_value_lines : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=@sf.grow)

///|
/// How agents may use it (facts: its terms in a column, 4 by 14 apart).
// kept across runs: a value (no field of it changes)
let vi_facts : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let vi_fact : @ui.Style = @ui.css("row w=Full gap=S3_5 align=AStart")

///|
/// Its terms' column at least (the web's 96).
let vi_term_w : Double = 96.0

///|
// kept across runs: a value (no field of it changes)
let vi_term : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let vi_fact_value : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, w=@sf.grow)

///|
/// Its uses (uses: 14 apart; a use its chat and how, its time at its end).
// kept across runs: a value (no field of it changes)
let vi_uses : @ui.Style = @ui.css("w=Full gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let vi_use : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let vi_use_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let vi_chat : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false, w=Cut)


///|
// kept across runs: a value (no field of it changes)
let vi_use_time : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// A field's buttons (show, copy) at its end: in the card's corner on its words' inset, the ladder's small block's
/// corner there (10), as a block in a card's corner on its 20 is.
// kept across runs: a value (no field of it changes)
let vi_key_corner : Double = @sf.small_corner
