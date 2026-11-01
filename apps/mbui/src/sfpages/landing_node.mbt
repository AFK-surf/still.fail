// Signed in with no workspace yet, as nodes of the window's tree (cloud_app.mbt's pages, made once): the way in's page
// (@sf.way_in_page_node) holding the invitations waiting, each joined by its 加入; else, asked for a code, why and its
// form (its field the old view's, hosted); else said so, with 创建 workspace, 用邀请链接加入 and 切换账号. An account the
// app may not be used with: why, its email, 退出此账号 or 切换账号. What the core answers and what the page asked of it
// as cloud_app.mbt has them (the same calls, the same state).

///|
/// Signed in with no workspace in view, in `parent` (no_workspace's): an account the app may not be used with first,
/// else the landing, as `ws` (the workspaces' topic: an entry an account) says as it changes. `by_link` is
/// 用邀请链接加入's. The node.
pub fn no_workspace_node(parent : @view.View, src : Source, ws : () -> Json?, by_link : () -> Unit) -> @view.View {
  let entries = fn() {
    match ws() {
      Some(Array(a)) => a
      _ => []
    }
  }
  let blocked = fn() { entries().iter().find_first(fn(e) { text(Some(e), "blocked") != "" }) }
  parent.box(fn(v) {
    v.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
    v.show(fn() { blocked() is Some(_) }, fn(b) {
      b.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
      blocked_page_node(b, src, blocked) |> ignore
    })
    v.show(fn() { blocked() is None }, fn(l) {
      l.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
      landing_page_node(l, src, entries, by_link) |> ignore
    })
  })
}

///|
/// A page of the way in after signing in in `parent` (landing_frame's): the sign-in page's picture in its place, what
/// `body` says and offers under it.
fn landing_frame_node(parent : @view.View, body : (@view.View) -> Unit) -> @view.View {
  @sf.way_in_page_node(parent, fn() { if @sf.theme().dark { "illus_sign_in_dark" } else { "illus_sign_in" } }, body)
}

///|
/// Words in `body` there only while `words` says something: the page's error (landing_error's: the UI size, in the red,
/// in its middle).
fn landing_error_node(body : @view.View, words : () -> String) -> Unit {
  body.show(fn() { words() != "" }, fn(e) {
    e.width_share(Is(1.0)) |> ignore
    e.box(fn(w) {
      w
      .width_share(Is(1.0))
      .words(By(words), look=landing_words(Ui, 400))
      .words_centered(Is(true))
      .ink(By(fn() { @ui.tree_theme().color(Danger) }))
      |> ignore
    })
    |> ignore
  })
}

///|
/// The landing's words, `size` as the window's theme has it and on its own line, `weight`, wrapping.
fn landing_words(size : @ui.TextSize, weight : Int) -> @view.WordsLook {
  let (px, line) = @ui.tree_theme().text_size(size)
  { size: px, weight, line, wrap: true }
}

///|
/// 切换账号 in `body` (switch_account_button's).
fn switch_account_node(body : @view.View, src : Source) -> Unit {
  @sf.way_in_link_node(body, fn() { @sf.t("android-misc.account.switch") }, fn() { (src.sign_in)() }, busy=fn() {
    (src.signing_in)()
  })
  |> ignore
}

///|
/// The invitations waiting in what `entries` says, each with the account it was sent to.
fn landing_pending(entries : Array[Json]) -> Array[(Json?, Json)] {
  let pending = []
  for e in entries {
    for i in items(Some(e), "invitations") {
      pending.push((field(Some(e), "account"), i))
    }
  }
  pending
}

///|
/// The landing in `parent` (landing_page_of's): the invitations waiting; else, asked for a code, why and its form; else
/// said so. Each of the three as `entries` and what was asked say, as they change.
fn landing_page_node(parent : @view.View, src : Source, entries : () -> Array[Json], by_link : () -> Unit) -> @view.View {
  let first = fn() {
    match entries().get(0) {
      Some(e) => field(Some(e), "account")
      None => None
    }
  }
  let pending = fn() { landing_pending(entries()) }
  // (which of the three: invitations, a code asked for, neither)
  let shown = fn() {
    if pending().length() > 0 {
      0
    } else if landing.asked.get() {
      1
    } else {
      2
    }
  }
  landing_frame_node(parent, fn(col) {
    col.show(fn() { shown() == 0 }, fn(b) {
      landing_column(b)
      @sf.way_in_title_node(b, fn() { @sf.t("android-misc.invite.received") }) |> ignore
      b.each(pending, fn(p) { text(Some(p.1), "id") }, fn(row, p) { invitation_node(row, src, fn() { p.get() }) })
      landing_error_node(b, fn() { landing.accept_error.get() })
      b.show(fn() { landing.asked.get() }, fn(f) {
        landing_column(f)
        invite_code_form_node(f, src, first)
      })
      b.show(fn() { !landing.asked.get() }, fn(f) {
        landing_column(f)
        @sf.way_in_button_node(
          f,
          fn() { @sf.t("android-misc.invite.declineCreate") },
          fn() { create_workspace(src, @signals.untracked(first), "") },
          solid=false,
          busy=fn() { landing.creating.get() },
        )
        |> ignore
      })
    })
    col.show(fn() { shown() == 1 }, fn(b) {
      landing_column(b)
      @sf.way_in_title_node(b, fn() { @sf.t("android-misc.invite.onlyInvited", args=[("app", "still.fail")]) }) |> ignore
      @sf.way_in_note_node(b, fn() {
        @sf.t("android-misc.invite.codeLead", args=[("app", "still.fail"), ("email", text(first(), "email"))])
      })
      |> ignore
      invite_code_form_node(b, src, first)
      switch_account_node(b, src)
    })
    col.show(fn() { shown() == 2 }, fn(b) {
      landing_column(b)
      @sf.way_in_title_node(b, fn() { @sf.t("android-misc.workspace.none") }) |> ignore
      @sf.way_in_note_node(b, fn() {
        @sf.t("android-misc.workspace.none.lead", args=[("app", "still.fail"), ("email", text(first(), "email"))])
      })
      |> ignore
      @sf.way_in_button_node(
        b,
        fn() { @sf.t("android-misc.workspace.createOne") },
        fn() { create_workspace(src, @signals.untracked(first), "") },
        busy=fn() { landing.creating.get() },
      )
      |> ignore
      landing_error_node(b, fn() { landing.create_error.get() })
      @sf.way_in_button_node(b, fn() { @sf.t("android-misc.invite.byLink") }, by_link, solid=false) |> ignore
      switch_account_node(b, src)
    })
  })
}

///|
/// What one of the landing's three holds, laid out as the page's column it is in (way_in_page_node's: 12 apart, in its
/// middle, as wide as it).
fn landing_column(b : @view.View) -> Unit {
  b.width_share(Is(1.0)).gap(Is(@ui.Space::px(S3))).lines_up(Is(Some(Middle))) |> ignore
}

///|
/// An invitation in `row` (landing_page_of's card): on the surface, 20 in, its name and who sent it to whom as what, its
/// 加入 across its foot (in its foot corners, concentric with its corner: @sf.card_foot_in), 12 apart; joined as it is
/// pressed, one at a time.
fn invitation_node(row : @view.View, src : Source, p : () -> (Json?, Json)) -> Unit {
  let th = fn() { @ui.tree_theme() }
  let button_h = @sf.button_height()
  let foot_in = @sf.card_foot_in(button_h)
  let card_in = @ui.Space::px(S5)
  row
  .width_share(Is(1.0))
  .padding(Is((0.0, card_in, 0.0, foot_in)))
  .gap(Is(@ui.Space::px(S3)))
  .radius(By(fn() { th().corner(Xl3) }))
  .ground(By(fn() { th().color(Surface) }))
  |> ignore
  let id = fn() { text(Some(p().1), "id") }
  row.box(fn(words) {
    words.width_share(Is(1.0)).padding(Is((card_in, 0.0, card_in, 0.0))) |> ignore
    words.box(fn(n) {
      n
      .width_share(Is(1.0))
      .words(By(fn() { text(Some(p().1), "name") }), look=landing_words(Ui, 600))
      .ink(By(fn() { th().color(Fg) }))
      |> ignore
    })
    |> ignore
    words.box(fn(w) {
      w
      .width_share(Is(1.0))
      .words(By(fn() {
          let (account, inv) = p()
          let iv = Some(inv)
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
          ])
        }), look=landing_words(Meta, 400))
      .ink(By(fn() { th().color(Muted) }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
  // (its 加入 out to where it stands concentric with the card's foot corners)
  row.box(fn(b) {
    b.width_share(Is(1.0)).padding(Is((foot_in, 0.0, foot_in, 0.0))) |> ignore
    @sf.button_node(
      b,
      fn() { @sf.t("android-misc.invite.join") },
      fn() {
        if @signals.untracked(fn() { landing.accepting.get() }) == "" {
          let (account, _) = @signals.untracked(p)
          accept_invitation(src, account, @signals.untracked(id))
        }
      },
      tone=Primary,
      busy=fn() { landing.accepting.get() == id() },
    )
    |> ignore
  })
  |> ignore
}

///|
/// The invite code's form in `body` (invite_code_form's): its field (the old view's, hosted) and 创建 workspace in a
/// row, 8 apart, the button not pressed while no code is typed; what was last tried's error under them, none before a
/// code was typed.
fn invite_code_form_node(body : @view.View, src : Source, account : () -> Json?) -> Unit {
  let code = fn() { landing.code.text().trim(chars=" \n").to_string() }
  body.box(fn(form) {
    form.width_share(Is(1.0)).gap(Is(@ui.Space::px(S2))) |> ignore
    form.box(fn(r) {
      r.row(Is(true)).width_share(Is(1.0)).gap(Is(@ui.Space::px(S2))).lines_up(Is(Some(Middle))) |> ignore
      r.box(fn(f) {
        // (what its row leaves after the button, as code_field's w=Full: none of its own before that is shared out)
        f.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)) |> ignore
        @ui.old(f, fn(c) {
          let t = @sf.theme()
          c.box(style=code_field, fn() {
            c.editor(
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
            |> ignore
          })
          |> ignore
        })
        .grow(Is(1.0))
        // (as tall as its words are laid out, its 10 over and under round them: code_field's; as wide as its row
        // leaves it)
        .measured(By(fn() { landing.code.laid(font_size=15.0, line=21.0, max_lines=1) }), fn(l, w) {
          let (side, over) = (@ui.Space::px(S3), @ui.Space::px(S2_5))
          let (lw, lh) = l.size(w.map(fn(w) { w - side - side }))
          (lw + side + side, lh + over + over)
        })
        |> ignore
      })
      |> ignore
      @sf.button_node(
        r,
        fn() { @sf.t("android-misc.workspace.create") },
        fn() { create_workspace(src, @signals.untracked(account), @signals.untracked(code)) },
        tone=Primary,
        busy=fn() { landing.creating.get() },
        disabled=fn() { code() == "" },
      )
      |> ignore
    })
    |> ignore
    // (nothing was wrong with a code nobody had typed yet)
    landing_error_node(form, fn() {
      if landing.code_tried.get() != "" {
        landing.create_error.get()
      } else {
        ""
      }
    })
  })
  |> ignore
}

///|
/// An account the app may not be used with in `parent` (blocked_page's): why, its email; 退出此账号, why that failed
/// where it did, or 切换账号.
fn blocked_page_node(parent : @view.View, src : Source, entry : () -> Json?) -> @view.View {
  let account = fn() { field(entry(), "account") }
  landing_frame_node(parent, fn(b) {
    @sf.way_in_title_node(b, fn() { text(entry(), "blocked") }) |> ignore
    @sf.way_in_note_node(b, fn() { text(account(), "email") }) |> ignore
    @sf.way_in_button_node(
      b,
      fn() { @sf.t("android-misc.account.signOut") },
      fn() {
        landing.leaving.set(true)
        landing.leave_error.set("")
        let sub = text(@signals.untracked(account), "sub")
        (src.call)("auth.signOut", { "account": Json::string(sub) }, fn(r) {
          landing.leaving.set(false)
          match r {
            Ok(_) => ()
            Err(e) => landing.leave_error.set(error_words(e))
          }
        })
      },
      busy=fn() { landing.leaving.get() },
    )
    |> ignore
    landing_error_node(b, fn() { landing.leave_error.get() })
    switch_account_node(b, src)
  })
}

///|
/// As still.fail cloud asking for a code once was (tests: the form shown at once).
pub fn landing_asked() -> Unit {
  landing.asked.set(true)
}
