// The still.fail team's replies on a bug report sent from a chat (the core's `chatFeedback`, by the chat's station and
// session): for the chat's people only, never given to its agents. A notice over the chat's composer, as the chat's
// other notices are (chat_notices: still.fail 团队回复了 FB-12, the first line of the latest, 查看), opens a panel: the
// replies of both sides in turn, the team's each with 交给 agent (it goes into the chat's draft as a quote, as a
// passage of a message does: only once the person sends it does the agent read it), and at its foot a field to answer
// the team as the person (`workspace.feedbackReply`, with their sign-in). What it holds and its foot are nodes of the
// window's tree, made once as it opens (@sf.panel_nodes).

///|
/// The reports of chat `r` the team replied on, newest first, as the core has them now.
fn feedback_reports(src : Source, r : ChatRef) -> Array[Json] {
  items(src.topic("chatFeedback", chat_params(r)).get().value, "reports")
}

///|
/// The latest reply's id on `report`: `latestId` from the core, or its last team reply's id.
fn report_latest_id(report : Json) -> String {
  let given = text(Some(report), "latestId")
  if given != "" {
    return given
  }
  let team = items(Some(report), "replies").filter(fn(x) { text(Some(x), "from") == "team" })
  if team.length() > 0 { text(Some(team[team.length() - 1]), "id") } else { "" }
}

///|
/// Whether `report`'s notice has been dismissed up to its latest reply (`chatFeedback` or `feedback_dismissed`).
fn report_dismissed(report : Json) -> Bool {
  if flag(Some(report), "dismissed") {
    return true
  }
  let id = text(Some(report), "id")
  let latest_id = report_latest_id(report)
  latest_id != "" && feedback_dismissed.get(id) == Some(latest_id)
}

///|
/// Over chat `r`'s composer (`width` its width, `chat` its notices' key): its newest report the team replied on whose
/// latest reply has not been dismissed here, its heading and the first line of their latest reply, 查看 opening them and
/// × letting it go until a newer reply comes (still in the chat's "…" menu). Nothing while there is none.
fn feedback_notice(c : @ui.Ctx, src : Source, r : ChatRef, width : Double, chat : String) -> Bool {
  let found = feedback_reports(src, r).iter().find_first(fn(f) { !report_dismissed(f) })
  guard found is Some(report) else { return false }
  let open = c.id("composer/feedback")
  let dismiss = c.id("composer/feedback/dismiss")
  let id = text(Some(report), "id")
  let ws = text(Some(report), "workspace")
  let latest_id = report_latest_id(report)
  c.on_press(open, fn() { c.tell("composer/feedback", fn() { open_feedback(src, r, id) }) })
  if latest_id != "" {
    c.on_press(dismiss, fn() {
      feedback_dismissed[id] = latest_id
      c.tell("composer/feedback/dismiss", fn() {
        (src.call)(
          "feedback.dismiss",
          { "workspace": Json::string(ws), "id": Json::string(id), "reply": Json::string(latest_id) },
          @sfbase.answer_unread,
        )
      })
    })
  }
  let latest = text(Some(report), "latest")
  let heading = text(Some(report), "heading")
  composer_notice(
    c,
    width,
    "feedback",
    if latest == "" { heading } else { heading + "：" + latest },
    Some((open, "web-main.feedback.open", "web-main.feedback.open", false)),
    dismiss=Some((dismiss, "web-main.feedback.dismiss", latest_id == "")),
    icon="said",
    chat~,
  )
  |> ignore
  true
}

///|
/// What is being written to the team, by report (the panel's field: kept while the app runs, as a draft is while its
/// page is open), and the latest reply id dismissed here on each report before the core's `chatFeedback` answers.
// kept across runs: put back by feedback_reset
let feedback_fields : Map[String, @ui.Field] = Map([])

///|
// kept across runs: put back by feedback_reset
let feedback_dismissed : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
fn feedback_reset() -> Unit {
  feedback_fields.clear()
  feedback_dismissed.clear()
}

///|
fn feedback_field(id : String) -> @ui.Field {
  match feedback_fields.get(id) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      feedback_fields[id] = f
      f
    }
  }
}

///|
/// What is under way while the person's answer on report `id` goes.
fn feedback_doing(id : String) -> String {
  "feedback.reply/" + id
}

///|
/// The report `id` of chat `r` as the core has it now (None once it is not).
fn feedback_report(src : Source, r : ChatRef, id : String) -> Json? {
  feedback_reports(src, r).iter().find_first(fn(f) { text(Some(f), "id") == id })
}

///|
/// Opens report `id` of chat `r`: its replies, each of the team's handed to the agent from there, and the field to
/// answer the team in.
pub fn open_feedback(src : Source, r : ChatRef, id : String) -> Unit {
  let report = fn() { feedback_report(src, r, id) }
  let first = report()
  let title = match first {
    Some(f) => text(Some(f), "label") + " · " + text(Some(f), "title")
    None => ""
  }
  @sf.panel_nodes(
    title,
    fn(v, close) { feedback_body(v, src, r, report, close) },
    from=Unanchored,
    description=@sf.t("web-main.feedback.lead"),
    foot=fn(v, _) { feedback_foot(v, src, r, id, report) },
    tall=0.8,
    hugs=true,
  )
}

///|
/// The replies of report `report`, oldest first, in node `v` (the panel's body's): who and when over what they said;
/// the team's with 交给 agent, which quotes it into chat `r`'s draft and closes the panel (`close`).
fn feedback_body(v : @view.View, src : Source, r : ChatRef, report : () -> Json?, close : () -> Unit) -> Unit {
  v.box(fn(list) {
    // (in from a sheet's edges as its words are: a dialog's body has its own)
    @sf.style_node(list, fn() { feedback_list.then(@sf.panel_words_in_node(list)) })
    list.each(fn() { items(report(), "replies") }, fn(x) { text(Some(x), "id") }, fn(row, x) {
      let said = fn(k : String) { text(Some(x.get()), k) }
      let team = said("from") == "team"
      row.box(fn(item) {
        @sf.style_node(item, fn() { if team { feedback_team } else { feedback_reply } })
        item.box(fn(head) {
          @sf.style_node(head, fn() { feedback_head }, in_row=true)
          @sf.words_node(head, fn() { said("who") }, fn() { if team { feedback_who_team } else { feedback_who } }) |> ignore
          @sf.words_node(head, fn() { said("when") }, fn() { feedback_when }) |> ignore
        })
        |> ignore
        @sf.words_node(item, fn() { said("text") }, fn() { feedback_text }) |> ignore
        if team {
          item.box(fn(acts) {
            @sf.style_node(acts, fn() { feedback_acts }, in_row=true)
            @sf.button_node(
              acts,
              fn() { @sf.t("web-main.feedback.handOn") },
              fn() {
                feedback_hand_on(src, r, report(), x.get())
                close()
              },
              tone=Ghost,
              icon="quote",
            )
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// The team's reply `x` on report `report` into chat `r`'s draft as a quote (as a passage of a message is), headed with
/// whose it is and on what: the agent reads it only once the person sends it.
fn feedback_hand_on(src : Source, r : ChatRef, report : Json?, x : Json) -> Unit {
  let author = text(Some(x), "who") + " · " + text(report, "label")
  writing_quote(src, writing(src, r.station + ":" + r.session), {
    "author": Json::string(author),
    "text": Json::string(text(Some(x), "text")),
  })
}

///|
/// The field to answer the team in and 回复, turning while it goes, in node `v` (the panel's foot's). Sent as the
/// person, its field emptied once it is there.
fn feedback_foot(v : @view.View, src : Source, r : ChatRef, id : String, report : () -> Json?) -> Unit {
  ignore(r)
  let f = feedback_field(id)
  let words = @signals.signal(f.text())
  v.box(fn(col) {
    @sf.style_node(col, fn() { feedback_foot_col })
    @sf.textarea_node(col, f, rows=2, most=8, placeholder=@sf.t("web-main.feedback.placeholder"), edited=fn(t) { words.set(t) }) |> ignore
    col.box(fn(acts) {
      @sf.style_node(acts, fn() { feedback_foot_acts }, in_row=true)
      @sf.button_node(
        acts,
        fn() { @sf.t("web-main.feedback.send") },
        fn() {
          let said = f.text().trim().to_owned()
          guard said != "" else { return }
          let r0 = report()
          let params : Json = {
            "account": Json::string(text(r0, "account")),
            "workspace": Json::string(text(r0, "workspace")),
            "id": Json::string(id),
            "text": Json::string(said),
          }
          act(src, @sf.t("web-main.feedback.sending"), feedback_doing(id), "workspace.feedbackReply", params, ok=fn(_) {
            f.set("")
            words.set("")
          })
        },
        tone=Primary,
        busy=fn() { doing(feedback_doing(id)) },
        disabled=fn() { words.get().trim().to_owned() == "" || report() is None },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The replies, 12 apart.
// kept across runs: a value (no field of it changes)
let feedback_list : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// A reply of the team's: on the accent's faint ground, its corners a card's, set off from the chat's people's.
// kept across runs: a value (no field of it changes)
let feedback_team : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 gap=S1_5 radius=Lg bg=AccentBg")

///|
/// A reply of the chat's side (a person's in the app, an agent's): on the hover's ground.
// kept across runs: a value (no field of it changes)
let feedback_reply : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 gap=S1_5 radius=Lg bg=Hover")

///|
/// Who and when, on a line.
// kept across runs: a value (no field of it changes)
let feedback_head : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let feedback_who_team : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=AccentText, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let feedback_who : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let feedback_when : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// What it says, wrapping.
// kept across runs: a value (no field of it changes)
let feedback_text : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, w=Full)

///|
/// 交给 agent, at its end.
// kept across runs: a value (no field of it changes)
let feedback_acts : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
/// The field over 回复.
// kept across runs: a value (no field of it changes)
let feedback_foot_col : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let feedback_foot_acts : @ui.Style = @ui.css("row w=Full justify=JEnd")
