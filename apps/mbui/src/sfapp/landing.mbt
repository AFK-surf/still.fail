// Signed in with no workspace yet (ember apps/android settings/screens/Workspaces.kt Landing, Blocked): the invitations
// waiting, each joined by its 加入 (`invitation.accept`); else said so, with 创建 workspace (`workspace.create`, the
// invite code still.fail cloud wants once it asks for one), 用邀请链接加入 (the invitation's sheet, links_sheet.mbt) and
// 切换账号. An account the app may not be used with (the core's `blocked`): why, its email, 退出此账号 or 切换账号.

///|
/// What the page has asked of the core and how it went: a workspace being made (with the code tried), why it could
/// not be (`created` its error's code and words), whether a code was asked for; the invitation being accepted, why it
/// could not be; the account being signed out, why it could not be.
priv struct LandingState {
  mut creating : Bool
  mut code_tried : String
  mut create_code : String
  mut create_error : String
  mut asked : Bool
  mut accepting : String
  mut accept_error : String
  mut leaving : Bool
  mut leave_error : String
  code : @ui.Field
}

///|
let landing : LandingState = {
  creating: false,
  code_tried: "",
  create_code: "",
  create_error: "",
  asked: false,
  accepting: "",
  accept_error: "",
  leaving: false,
  leave_error: "",
  code: @ui.Field::new(),
}

///|
/// As at the start (tests).
fn landing_reset() -> Unit {
  landing.creating = false
  landing.code_tried = ""
  landing.create_code = ""
  landing.create_error = ""
  landing.asked = false
  landing.accepting = ""
  landing.accept_error = ""
  landing.leaving = false
  landing.leave_error = ""
  landing.code.set("")
}

///|
/// still.fail cloud's invite-code errors (Calls.kt INVITE_ERRORS) and limits (LIMIT_ERRORS), by their codes.
fn invite_error_key(code : String) -> String? {
  match code {
    "invite_code_required" => Some("android-misc.invite.codeRequired")
    "invite_code_invalid" => Some("android-misc.invite.codeInvalid")
    "invite_code_used" => Some("android-misc.invite.codeUsed")
    "invite_code_expired" => Some("android-misc.invite.codeExpired")
    _ => None
  }
}

///|
/// An error in words (Calls.kt errorText): an invite code's or a limit's as still.fail says them, else the core's.
fn landing_error_words(e : Json) -> String {
  let code = text(Some(e), "code")
  match invite_error_key(code) {
    Some(k) => tr(k)
    None =>
      match code {
        "too_many_workspaces" => tr("android-misc.limit.workspaces")
        "too_many_members" => tr("android-misc.limit.members")
        _ => error_words(e)
      }
  }
}

///|
/// The page: its illustration, then what it says and offers, 12 apart, 24 in from the sides and 40 from the top.
// kept across runs: a value (no field of it changes)
let landing_page : @ui.Style = @ui.style(w=Full, h=Full, px=S6, py=S10, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let landing_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Fg, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let landing_lead : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, center=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let landing_error : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, w=Full)

///|
/// An invitation: on the surface, 12 in all round, its button at the end in the bottom corner, the corner round it.
// kept across runs: a value (no field of it changes)
let invitation_row : @ui.Style = @ui.style(row=true, w=Full, p=S3, gap=S3, radius=Around, bg=Surface, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let invitation_name : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let invitation_who : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, w=Full)

///|
/// The invite code's form: its field and 创建 workspace in a row, 8 apart, why it failed under them.
// kept across runs: a value (no field of it changes)
let code_form : @ui.Style = @ui.style(w=Full, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let code_row : @ui.Style = @ui.style(row=true, w=Full, gap=S2, align=ACenter)

///|
/// The field (Controls.kt Field): on the surface, a hairline round it, 12 round, 12 and 10 in.
// kept across runs: a value (no field of it changes)
let code_field : @ui.Style = @ui.style(
  w=Full,
  px=S3,
  py=S2_5,
  radius=Xl,
  bg=Surface,
  border=B1,
  border_color=Line,
)

///|
/// Signed in with no workspace in view (App.kt): an account the app may not be used with first, else the landing.
fn no_workspace(c : @ui.Ctx, src : Source, ws : Json?) -> Unit {
  let entries = match ws {
    Some(Array(a)) => a
    _ => []
  }
  match entries.iter().find_first(fn(e) { text(Some(e), "blocked") != "" }) {
    Some(e) => blocked_page(c, src, Some(e))
    None => landing_page_of(c, src, entries)
  }
  // an invitation's link pasted (用邀请链接加入): its sheet over the page
  sheet_layer(c, fn(kind) { if kind == InviteLink { invite_sheet(c, src) } })
}

///|
/// The illustration over what the page says (Workspaces.kt Illustration: 260 wide at most).
fn landing_picture(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  @sf.drawable(c, if t.dark { "illus_sign_in_dark" } else { "illus_sign_in" }, dmin(260.0, c.width - 48.0)) |> ignore
}

///|
/// 切换账号: another account signed in (the system's browser).
fn switch_account_button(c : @ui.Ctx, src : Source) -> Unit {
  if @settings.button(c, "landing/switch", tr("android-misc.account.switch"), false, busy=(src.signing_in)()) {
    (src.sign_in)()
  }
}

///|
/// Makes a workspace of the first account's own (named after it), with `code` when one was asked for: picked once
/// made; else why not, and whether a code is wanted.
fn create_workspace(src : Source, account : Json?, code : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  let sub = text(account, "sub")
  let name = match text(account, "name") {
    "" =>
      match text(account, "email").find("@") {
        Some(i) => text(account, "email").view(end_offset=i).to_owned()
        None => text(account, "email")
      }
    n => n
  }
  let params : Map[String, Json] = {
    "account": Json::string(sub),
    "name": Json::string(fill("android-misc.workspace.defaultName", [("name", name)])),
  }
  if code != "" {
    params["invite_code"] = Json::string(code)
  }
  landing.creating = true
  landing.code_tried = code
  landing.create_error = ""
  landing.create_code = ""
  (src.call)("workspace.create", Json::object(params), fn(r) {
    landing.creating = false
    match r {
      Ok(v) => pick_workspace(src, text(Some(v), "id"))
      Err(e) => {
        landing.create_code = text(Some(e), "code")
        landing.create_error = landing_error_words(e)
        // once asked for a code, the form stays while codes are tried
        if invite_error_key(landing.create_code) is Some(_) {
          landing.asked = true
        }
      }
    }
  })
}

///|
/// The invite code's form (InviteCodeForm): what was last tried's error under it, none before a code was typed.
fn invite_code_form(c : @ui.Ctx, src : Source, account : Json?) -> Unit {
  let t = @sf.theme()
  c.box(style=code_form, fn() {
    let mut code = ""
    c.box(style=code_row, fn() {
      c.box(style=code_field, fn() {
        let r = c.editor(
          "landing/code",
          placeholder="XXXX-XXXX-XXXX",
          font_size=15.0,
          line=21.0,
          max_lines=1,
          plain=true,
          color=t.p.text,
          placeholder_color=t.p.subtle,
          caret_color=t.p.accent,
          enter_sends=false,
          field=landing.code,
        )
        code = r.text.trim(chars=" \n").to_string()
      })
      |> ignore
      if @settings.button(c, "landing/create-code", tr("android-misc.workspace.create"), true, busy=landing.creating, enabled=code != "") {
        create_workspace(src, account, code)
      }
    })
    |> ignore
    // (nothing was wrong with a code nobody had typed yet)
    if landing.create_error != "" && landing.code_tried != "" {
      c.text(landing.create_error, style=landing_error) |> ignore
    }
  })
  |> ignore
}

///|
/// The landing (Landing): the invitations waiting; else, asked for a code, why and its form; else said so.
fn landing_page_of(c : @ui.Ctx, src : Source, entries : Array[Json]) -> Unit {
  let first = match entries.get(0) {
    Some(e) => field(Some(e), "account")
    None => None
  }
  let pending : Array[(Json?, Json)] = []
  for e in entries {
    for i in items(Some(e), "invitations") {
      pending.push((field(Some(e), "account"), i))
    }
  }
  let asking = landing.asked
  c.box(style=landing_page, fn() {
    landing_picture(c)
    if pending.length() > 0 {
      c.text(tr("android-misc.invite.received"), style=landing_title) |> ignore
      for p in pending {
        let (account, inv) = p
        let iv = Some(inv)
        let id = text(iv, "id")
        c.box(style=invitation_row, fn() {
          c.box(style=@sf.full_width, fn() {
            c.text(text(iv, "name"), style=invitation_name) |> ignore
            c.text(
              fill("android-misc.invite.invitedAs", [
                (
                  "inviter",
                  match text(iv, "inviter") {
                    "" => tr("android-misc.invite.someone")
                    w => w
                  },
                ),
                ("email", text(account, "email")),
                ("role", role_words(text(iv, "role"))),
              ]),
              style=invitation_who,
            )
            |> ignore
          })
          |> ignore
          if @settings.button(c, "landing/join/" + id, tr("android-misc.invite.join"), true, busy=landing.accepting == id) &&
            landing.accepting == "" {
            accept_invitation(src, account, id)
          }
        })
        |> ignore
      }
      if landing.accept_error != "" {
        c.text(landing.accept_error, style=landing_error) |> ignore
      }
      if asking {
        invite_code_form(c, src, first)
      } else if @settings.button(c, "landing/decline-create", tr("android-misc.invite.declineCreate"), false, busy=landing.creating) {
        create_workspace(src, first, "")
      }
    } else if asking {
      c.text(fill("android-misc.invite.onlyInvited", [("app", "still.fail")]), style=landing_title) |> ignore
      c.text(fill("android-misc.invite.codeLead", [("app", "still.fail"), ("email", text(first, "email"))]), style=landing_lead)
      |> ignore
      invite_code_form(c, src, first)
      switch_account_button(c, src)
    } else {
      c.text(tr("android-misc.workspace.none"), style=landing_title) |> ignore
      c.text(fill("android-misc.workspace.none.lead", [("app", "still.fail"), ("email", text(first, "email"))]), style=landing_lead)
      |> ignore
      if @settings.button(c, "landing/create", tr("android-misc.workspace.createOne"), true, busy=landing.creating) {
        create_workspace(src, first, "")
      }
      if landing.create_error != "" {
        c.text(landing.create_error, style=landing_error) |> ignore
      }
      if @settings.button(c, "landing/by-link", tr("android-misc.invite.byLink"), false) {
        open_invite_link()
      }
      switch_account_button(c, src)
    }
  })
  |> ignore
}

///|
/// An invitation accepted as `account` (Landing's join): the workspace joined is the one in view, at Home's top.
fn accept_invitation(src : Source, account : Json?, id : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  landing.accepting = id
  landing.accept_error = ""
  (src.call)("invitation.accept", { "account": Json::string(text(account, "sub")), "id": Json::string(id) }, fn(r) {
    landing.accepting = ""
    match r {
      Ok(v) => {
        pick_workspace(src, text(Some(v), "id"))
        home()
      }
      Err(e) => landing.accept_error = error_words(e)
    }
  })
}

///|
/// The invitation's sheet with no link yet: one to paste (Workspaces.kt openInviteLink).
fn open_invite_link() -> Unit {
  invite_reset()
  raise_sheet(InviteLink)
}

///|
/// An account the app may not be used with (Blocked): why, its email; it signs out, or another signs in.
fn blocked_page(c : @ui.Ctx, src : Source, entry : Json?) -> Unit {
  let account = field(entry, "account")
  c.box(style=landing_page, fn() {
    landing_picture(c)
    c.text(text(entry, "blocked"), style=landing_title) |> ignore
    c.text(text(account, "email"), style=landing_lead) |> ignore
    if @settings.button(c, "landing/sign-out", tr("android-misc.account.signOut"), true, busy=landing.leaving) &&
      !landing.leaving {
      landing.leaving = true
      landing.leave_error = ""
      (src.call)("auth.signOut", { "account": Json::string(text(account, "sub")) }, fn(r) {
        landing.leaving = false
        match r {
          Ok(_) => ()
          Err(e) => landing.leave_error = error_words(e)
        }
      })
    }
    if landing.leave_error != "" {
      c.text(landing.leave_error, style=landing_error) |> ignore
    }
    switch_account_button(c, src)
  })
  |> ignore
}
