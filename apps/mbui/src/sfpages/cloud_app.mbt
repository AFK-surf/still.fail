// Signed in with no workspace yet (the web's cloud/CloudApp.tsx Landing, InviteCodeForm; ember apps/android
// settings/screens/Workspaces.kt Landing, Blocked): the invitations
// waiting, each joined by its 加入 (`invitation.accept`); else said so, with 创建 workspace (`workspace.create`, the
// invite code still.fail cloud wants once it asks for one), 用邀请链接加入 (the invitation's sheet, links_sheet.mbt) and
// 切换账号. An account the app may not be used with (the core's `blocked`): why, its email, 退出此账号 or 切换账号.

///|
/// What the page has asked of the core and how it went: a workspace being made (with the code tried), why it could
/// not be (`created` its error's code and words), whether a code was asked for; the invitation being accepted, why it
/// could not be; the account being signed out, why it could not be.
priv struct LandingState {
  creating : @signals.Signal[Bool]
  code_tried : @signals.Signal[String]
  create_code : @signals.Signal[String]
  create_error : @signals.Signal[String]
  asked : @signals.Signal[Bool]
  accepting : @signals.Signal[String]
  accept_error : @signals.Signal[String]
  leaving : @signals.Signal[Bool]
  leave_error : @signals.Signal[String]
  code : @ui.Field
}

///|
let landing : LandingState = {
  creating: @signals.signal(false, same=fn(a, b) { a == b }),
  code_tried: @signals.signal("", same=fn(a, b) { a == b }),
  create_code: @signals.signal("", same=fn(a, b) { a == b }),
  create_error: @signals.signal("", same=fn(a, b) { a == b }),
  asked: @signals.signal(false, same=fn(a, b) { a == b }),
  accepting: @signals.signal("", same=fn(a, b) { a == b }),
  accept_error: @signals.signal("", same=fn(a, b) { a == b }),
  leaving: @signals.signal(false, same=fn(a, b) { a == b }),
  leave_error: @signals.signal("", same=fn(a, b) { a == b }),
  code: @ui.Field::new(),
}

///|
/// As at the start (tests).
pub fn landing_reset() -> Unit {
  landing.creating.set(false)
  landing.code_tried.set("")
  landing.create_code.set("")
  landing.create_error.set("")
  landing.asked.set(false)
  landing.accepting.set("")
  landing.accept_error.set("")
  landing.leaving.set(false)
  landing.leave_error.set("")
  landing.code.set("")
}

///|
/// still.fail cloud's invite-code errors (Calls.kt INVITE_ERRORS) and limits (LIMIT_ERRORS), by their codes.
pub fn invite_error_key(code : String) -> String? {
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
pub fn landing_error_words(e : Json) -> String {
  let code = text(Some(e), "code")
  match invite_error_key(code) {
    Some(k) => @sf.t(k)
    None =>
      match code {
        "too_many_workspaces" => @sf.t("android-misc.limit.workspaces")
        "too_many_members" => @sf.t("android-misc.limit.members")
        _ => error_words(e)
      }
  }
}

///|
// kept across runs: a value (no field of it changes)
let landing_error : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger, center=true, w=Full)

///|
/// An invitation: a card of the ladder's on the surface, its words 20 in, its button under them in its foot corners
/// (concentric with its corner: @sf.card_foot_in, as high as the screen's buttons are), 12 apart.
fn invitation_row() -> @ui.Style {
  invitation_card.then(@sf.foot_pad(@sf.button_height()))
}

///|
// kept across runs: a value (no field of it changes)
let invitation_card : @ui.Style = @ui.css("w=Full pt=S5 px=S5 gap=S3 radius=Xl3 bg=Surface")

///|
// kept across runs: a value (no field of it changes)
let invitation_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let invitation_who : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// The invite code's form: its field and 创建 workspace in a row, 8 apart, why it failed under them.
// kept across runs: a value (no field of it changes)
let code_form : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let code_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// The field (Controls.kt Field): on the surface, a hairline round it, 12 round, 12 and 10 in.
// kept across runs: a value (no field of it changes)
pub let code_field : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 radius=Xl bg=Surface border=B1 border_color=Line")

///|
/// Signed in with no workspace in view (CloudApp.tsx SignedIn, App.kt), in the box the frame gives it (inside the
/// system's bars): an account the app may not be used with first, else the landing. `by_link` is 用邀请链接加入's:
/// the frame's sheet of an invitation's link, one to paste.
pub fn no_workspace(c : @ui.Ctx, src : Source, ws : Json?, by_link : () -> Unit) -> Unit {
  let entries = match ws {
    Some(Array(a)) => a
    _ => []
  }
  match entries.iter().find_first(fn(e) { text(Some(e), "blocked") != "" }) {
    Some(e) => blocked_page(c, src, Some(e))
    None => landing_page_of(c, src, entries, by_link)
  }
}

///|
/// A page of the way in after signing in (@sf.way_in_page): the sign-in page's picture in the sign-in page's place,
/// what `body` says and offers under it, as the sign-in page has them.
fn landing_frame(c : @ui.Ctx, body : () -> Unit) -> Unit {
  let t = @sf.theme()
  @sf.way_in_page(c, if t.dark { "illus_sign_in_dark" } else { "illus_sign_in" }, body)
}

///|
/// 切换账号: another account signed in (the system's browser), what the page offers last.
fn switch_account_button(c : @ui.Ctx, src : Source) -> Unit {
  if @sf.way_in_link(c, "landing/switch", @sf.t("android-misc.account.switch"), busy=(src.signing_in)()) {
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
    "name": Json::string(@sf.t("android-misc.workspace.defaultName", args=[("name", name)])),
  }
  if code != "" {
    params["invite_code"] = Json::string(code)
  }
  landing.creating.set(true)
  landing.code_tried.set(code)
  landing.create_error.set("")
  landing.create_code.set("")
  (src.call)("workspace.create", Json::object(params), fn(r) {
    landing.creating.set(false)
    match r {
      Ok(v) => @sfbase.pick_workspace(src, text(Some(v), "id"))
      Err(e) => {
        landing.create_code.set(text(Some(e), "code"))
        landing.create_error.set(landing_error_words(e))
        // once asked for a code, the form stays while codes are tried
        if invite_error_key(landing.create_code.get()) is Some(_) {
          landing.asked.set(true)
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
      if @sf.button(c, @sf.t("android-misc.workspace.create"), key="landing/create-code", tone=Primary, busy=landing.creating.get(), disabled=code == "") {
        create_workspace(src, account, code)
      }
    })
    |> ignore
    // (nothing was wrong with a code nobody had typed yet)
    if landing.create_error.get() != "" && landing.code_tried.get() != "" {
      c.text(landing.create_error.get(), style=landing_error) |> ignore
    }
  })
  |> ignore
}

///|
/// The landing (Landing): the invitations waiting; else, asked for a code, why and its form; else said so.
fn landing_page_of(c : @ui.Ctx, src : Source, entries : Array[Json], by_link : () -> Unit) -> Unit {
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
  let asking = landing.asked.get()
  landing_frame(c, fn() {
    if pending.length() > 0 {
      @sf.way_in_title(c, @sf.t("android-misc.invite.received"))
      for p in pending {
        let (account, inv) = p
        let iv = Some(inv)
        let id = text(iv, "id")
        c.box(style=invitation_row(), fn() {
          c.box(style=@sf.full_width, fn() {
            c.text(text(iv, "name"), style=invitation_name) |> ignore
            c.text(
              @sf.t("android-misc.invite.invitedAs", args=[
                (
                  "inviter",
                  match text(iv, "inviter") {
                    "" => @sf.t("android-misc.invite.someone")
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
          if @sf.button(c, @sf.t("android-misc.invite.join"), key="landing/join/" + id, tone=Primary, busy=landing.accepting.get() == id, reach=@sf.foot_across(@sf.button_height())) &&
            landing.accepting.get() == "" {
            accept_invitation(src, account, id)
          }
        })
        |> ignore
      }
      if landing.accept_error.get() != "" {
        c.text(landing.accept_error.get(), style=landing_error) |> ignore
      }
      if asking {
        invite_code_form(c, src, first)
      } else if @sf.way_in_button(c, "landing/decline-create", @sf.t("android-misc.invite.declineCreate"), solid=false, busy=landing.creating.get()) {
        create_workspace(src, first, "")
      }
    } else if asking {
      @sf.way_in_title(c, @sf.t("android-misc.invite.onlyInvited", args=[("app", "still.fail")]))
      @sf.way_in_note(c, @sf.t("android-misc.invite.codeLead", args=[("app", "still.fail"), ("email", text(first, "email"))]))
      invite_code_form(c, src, first)
      switch_account_button(c, src)
    } else {
      @sf.way_in_title(c, @sf.t("android-misc.workspace.none"))
      @sf.way_in_note(c, @sf.t("android-misc.workspace.none.lead", args=[("app", "still.fail"), ("email", text(first, "email"))]))
      if @sf.way_in_button(c, "landing/create", @sf.t("android-misc.workspace.createOne"), busy=landing.creating.get()) {
        create_workspace(src, first, "")
      }
      if landing.create_error.get() != "" {
        c.text(landing.create_error.get(), style=landing_error) |> ignore
      }
      if @sf.way_in_button(c, "landing/by-link", @sf.t("android-misc.invite.byLink"), solid=false) {
        by_link()
      }
      switch_account_button(c, src)
    }
  })
}

///|
/// An invitation accepted as `account` (Landing's join): the workspace joined is the one in view, at Home's top.
fn accept_invitation(src : Source, account : Json?, id : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  landing.accepting.set(id)
  landing.accept_error.set("")
  (src.call)("invitation.accept", { "account": Json::string(text(account, "sub")), "id": Json::string(id) }, fn(r) {
    landing.accepting.set("")
    match r {
      Ok(v) => {
        @sfbase.pick_workspace(src, text(Some(v), "id"))
        @sfbase.nav_home()
      }
      Err(e) => landing.accept_error.set(error_words(e))
    }
  })
}

///|
/// An account the app may not be used with (Blocked): why, its email; it signs out, or another signs in.
fn blocked_page(c : @ui.Ctx, src : Source, entry : Json?) -> Unit {
  let account = field(entry, "account")
  landing_frame(c, fn() {
    @sf.way_in_title(c, text(entry, "blocked"))
    @sf.way_in_note(c, text(account, "email"))
    if @sf.way_in_button(c, "landing/sign-out", @sf.t("android-misc.account.signOut"), busy=landing.leaving.get()) {
      landing.leaving.set(true)
      landing.leave_error.set("")
      (src.call)("auth.signOut", { "account": Json::string(text(account, "sub")) }, fn(r) {
        landing.leaving.set(false)
        match r {
          Ok(_) => ()
          Err(e) => landing.leave_error.set(error_words(e))
        }
      })
    }
    if landing.leave_error.get() != "" {
      c.text(landing.leave_error.get(), style=landing_error) |> ignore
    }
    switch_account_button(c, src)
  })
}

///|
/// A role in words (Accounts.kt ROLE_LABEL).
pub fn role_words(role : String) -> String {
  match role {
    "owner" => "Owner"
    "admin" => @sf.t("android-misc.role.admin")
    "member" => @sf.t("android-misc.role.member")
    r => r
  }
}
