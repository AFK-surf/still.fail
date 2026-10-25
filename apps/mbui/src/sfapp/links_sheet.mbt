// An invitation's link (/invite#<token>) opened in the app (ember apps/android settings/screens/Workspaces.kt
// openInvite, InviteLinkSheet, invitationToken): what it leads to, read as the account it would be accepted by
// (`invitation.preview`), shown in a sheet of half the screen before it is accepted (`invitation.accept`), that
// account chosen when more than one is signed in. Signed out, the sheet says to sign in first. Without a link (pasted
// instead), a field to paste one in.

///|
/// The invitation sheet's state: the link's token (None: one to paste), the account chosen, what each account was
/// told of it, and its acceptance.
priv struct Invite {
  mut token : String?
  /// the link it was opened with (None: pasted)
  mut given : String?
  mut chosen : String
  /// what `invitation.preview` answered, by token and account: Ok(the preview) or Err(why not)
  read : Map[String, Result[Json, String]]
  /// asked already, by token and account
  asked : Map[String, Bool]
  mut accepting : Bool
  mut error : String
  /// the link written in, the sheet's field's
  field : @ui.Field
}

///|
let invite : Invite = {
  token: None,
  given: None,
  chosen: "",
  read: {},
  asked: {},
  accepting: false,
  error: "",
  field: @ui.Field::new(),
}

///|
fn invite_reset() -> Unit {
  invite.token = None
  invite.given = None
  invite.chosen = ""
  invite.read.clear()
  invite.asked.clear()
  invite.accepting = false
  invite.error = ""
  invite.field.set("")
}

///|
/// An invitation's link opened in the app (Workspaces.kt openInvite): what it leads to, before it is accepted.
fn open_invite(token : String) -> Unit {
  invite_reset()
  invite.token = Some(token)
  invite.given = Some(token)
  raise_sheet(InviteLink)
}

///|
/// The token of an invitation's link (`<cloud>/invite#<token>`), or what was pasted when it is a token by itself
/// (Workspaces.kt invitationToken).
fn invitation_token(words : String) -> String? {
  let t = words.trim(chars=" \n\t").to_string()
  if t == "" {
    return None
  }
  let hash = match t.find("/invite#") {
    Some(i) => t.view(start_offset=i + 8).to_string()
    None => ""
  }
  let token = if hash != "" {
    hash
  } else if t.contains("/") || t.contains(" ") {
    ""
  } else {
    t
  }
  match token.trim(chars=" \n\t").to_string() {
    "" => None
    s => Some(s)
  }
}

///|
/// The sheet's body: in 20 from its sides, its parts 10 apart (InviteLinkSheet's Column).
// kept across runs: a value (no field of it changes)
let invite_body : @ui.Style = @ui.css("w=Full h=Full px=S5 gap=S2_5 clip")

///|
/// Its buttons at the end of a row, 8 apart, 6 over them and 24 under (InviteLinkSheet's Row).
// kept across runs: a value (no field of it changes)
let invite_buttons : @ui.Style = @ui.css("row w=Full pt=S1_5 pb=S6 gap=S2 justify=JEnd")

///|
/// The field a link is pasted in (Controls.kt Field): the surface, a line round it, 12 round, 12 and 10 in.
// kept across runs: a value (no field of it changes)
let invite_field : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 radius=Xl bg=Card border=B1 border_color=Line")

///|
/// What it says (14, muted), the account's label (13, semibold), why it failed (13, red).
// kept across runs: a value (no field of it changes)
let invite_lead : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let invite_label : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let invite_error : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger)

///|
/// The invitation's sheet with no link yet: one to paste (Workspaces.kt openInviteLink): the landing's 用邀请链接加入.
fn open_invite_link() -> Unit {
  invite_reset()
  raise_sheet(InviteLink)
}

///|
/// The sheet (Workspaces.kt InviteLinkSheet), over the pages or the sign-in page.
fn invite_sheet(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let accounts = (src.topic)("accounts", {})
  let list = match accounts.value {
    Some(Array(a)) => a
    _ => []
  }
  let sub = match list.iter().find_first(fn(a) { text(Some(a), "sub") == invite.chosen }) {
    Some(a) => text(Some(a), "sub")
    None =>
      match list.get(0) {
        Some(a) => text(Some(a), "sub")
        None => ""
      }
  }
  // read once per account: what the link leads to depends on who looks
  match invite.token {
    Some(tok) if sub != "" && !invite.asked.contains(tok + "\u{1}" + sub) => {
      let k = tok + "\u{1}" + sub
      invite.asked[k] = true
      c.tell("invitation.preview/" + k, fn() {
        (src.call)(
          "invitation.preview",
          { "token": Json::string(tok), "account": Json::string(sub) },
          fn(r) {
            invite.read[k] = match r {
              Ok(v) => Ok(v)
              Err(e) => Err(error_words(e))
            }
          },
        )
      })
    }
    _ => ()
  }
  let read = match invite.token {
    Some(tok) => invite.read.get(tok + "\u{1}" + sub)
    None => None
  }
  let buttons = fn(body : () -> Unit) {
    c.box(style=invite_buttons, body) |> ignore
  }
  let lead = fn(words : String) {
    c.text(words, style=invite_lead) |> ignore
  }
  // signed out: nothing reads the invitation yet (as the web's /invite: sign in first, then decide)
  if accounts.value is Some(_) && list.length() == 0 {
    sheet_head(c, fill("android-misc.signIn.title", [("app", "still.fail")]))
    c.box(style=invite_body, fn() {
      lead(fill("android-misc.signIn.invited", [("app", "still.fail")]))
      buttons(fn() {
        if @sf.button(c, tr("common.cancel"), key="invite/cancel") {
          lower_sheet()
        }
        if @sf.button(
            c,
            tr("android-misc.signIn.google"),
            key="invite/sign-in",
            tone=Primary,
            busy=(src.signing_in)(),
          ) {
          (src.sign_in)()
        }
      })
    })
    |> ignore
    return
  }
  let head = match (invite.token, read) {
    (None, _) => tr("android-misc.invite.byLink")
    (Some(_), Some(Ok(p))) => fill("android-misc.invite.joinNamed", [("name", text(Some(p), "name"))])
    (Some(_), Some(Err(_))) => tr("android-misc.invite.unusable")
    (Some(_), None) => tr("android-misc.invite.loading")
  }
  sheet_head(c, head)
  c.box(style=invite_body, fn() {
    match (invite.token, read) {
      (None, _) => {
        lead(fill("android-misc.invite.pasteLink", [("app", "still.fail")]))
        let key = "invite/field"
        let mut words = ""
        c.box(
          style=invite_field,
          fn() {
            let r = c.editor(
              key,
              placeholder="https://app.still.fail/invite#…",
              font_size=15.0,
              line=21.0,
              max_lines=2,
              plain=true,
              color=t.p.text,
              placeholder_color=t.p.subtle,
              caret_color=t.p.accent,
              enter_sends=false,
              field=invite.field,
            )
            words = r.text
          },
        )
        |> ignore
        buttons(fn() {
          if @sf.button(c, tr("common.cancel"), key="invite/cancel") {
            invite.field.take() |> ignore
            lower_sheet()
          }
          let token = invitation_token(words)
          if @sf.button(
              c,
              tr("android-misc.invite.view"),
              key="invite/view",
              tone=Primary,
              disabled=token is None,
            ) {
            invite.field.take() |> ignore
            invite.token = token
          }
        })
      }
      (Some(_), Some(Err(why))) => {
        lead(why)
        buttons(fn() {
          if invite.given is None && @sf.button(c, tr("android-misc.invite.otherLink"), key="invite/other") {
            invite.token = None
          }
          if @sf.button(c, tr("common.close"), key="invite/close", tone=Primary) {
            lower_sheet()
          }
        })
      }
      (Some(_), None) => @sf.wait_line(c, tr("common.reading"), key="invite")
      (Some(tok), Some(Ok(p))) => {
        let inviter = match text(Some(p), "inviter") {
          "" => tr("android-misc.invite.someone")
          s => s
        }
        let email = text(Some(p), "email")
        lead(
          fill(
            if email != "" {
              "android-misc.invite.invitedYouAsOnly"
            } else {
              "android-misc.invite.invitedYouAs"
            },
            [("inviter", inviter), ("role", @sfpages.role_words(text(Some(p), "role"))), ("email", email)],
          ),
        )
        if list.length() > 1 {
          c.text(tr("android-misc.invite.whichAccount"), style=invite_label) |> ignore
          c.box(style=@sf.full_width, fn() {
            for a in list {
              let s = text(Some(a), "sub")
              if @sf.choice_row(c, "invite/as/" + s, s == sub, text(Some(a), "email")) {
                invite.chosen = s
              }
            }
          })
          |> ignore
        }
        if invite.error != "" {
          c.text(invite.error, style=invite_error) |> ignore
        }
        let as_email = match list.iter().find_first(fn(a) { text(Some(a), "sub") == sub }) {
          Some(a) => text(Some(a), "email")
          None => ""
        }
        buttons(fn() {
          if @sf.button(c, tr("common.cancel"), key="invite/cancel") {
            lower_sheet()
          }
          if @sf.button(
              c,
              fill("android-misc.invite.joinAs", [("email", as_email)]),
              key="invite/join",
              tone=Primary,
              busy=invite.accepting,
              disabled=sub == "",
            ) {
            accept_invite(src, tok, sub, text(Some(p), "name"))
          }
        })
      }
    }
  })
  |> ignore
}

///|
/// Accepted as `sub` (Cloud.acceptInvitationToken): the workspace joined is the one in view, Home at its top, and said
/// so; failed, why under it.
fn accept_invite(src : Source, token : String, sub : String, name : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  invite.accepting = true
  invite.error = ""
  (src.call)("invitation.accept", { "token": Json::string(token), "account": Json::string(sub) }, fn(r) {
    invite.accepting = false
    match r {
      Ok(v) => {
        pick_workspace(src, text(Some(v), "id"))
        home()
        toast_later(fill("android-misc.invite.joined", [("name", name)]))
      }
      Err(e) => invite.error = error_words(e)
    }
  })
}

///|
/// The sheets and the menus over the pages closed, as a page opens from a link (AppState: sheet, menu null).
fn close_overlays() -> Unit {
  lower_sheet()
  app.menu = false
  match dui.sheet {
    Some(s) => dui.leaving = Some(s)
    None => ()
  }
  dui.sheet = None
}
