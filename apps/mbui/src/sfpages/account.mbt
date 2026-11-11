// 账号, one page in every frame, the same
// on every width (the user, 2026-10-26: 「设置感觉很乱」; it was four sections and two cards wide, one card narrow): the
// accounts on this device on one card, the one in view first with who it is (its picture, name, email and how it
// signs in) and signing out of it, the others each signed out of by itself, another added, each one's picture changed
// by pressing it (one of its own from the system's photos, or its sign-in's again); where it is signed in (each device,
// signed out from here but this one); deleting the account, in red at the foot. Signing out and deleting asked first
// (@sf.confirm).

///|
/// 账号 (AccountSettings, MeScreen).
pub fn me_page(c : @ui.Ctx, core : Core, here : Here, frame : PageFrame) -> Unit {
  let name = if here.person != "" { here.person } else { here.email }
  let how = if here.sub.has_prefix("em-") || here.sub.has_prefix("pw-") {
    @sf.t("web-pages.settings.account.email")
  } else {
    @sf.t("web-pages.settings.account.google")
  }
  let accounts = match (core.topic)("accounts", Map([])).get().value {
    Some(Array(a)) => a
    _ => []
  }
  let others = accounts.filter(fn(a) { text(Some(a), "sub") != here.sub })
  // a picture picked as theirs, once read: made their face and put up
  if own_picture.reading != "" {
    match c.image_pixels(own_picture.reading, @sf.face_picture_read) {
      PixelsComing => ()
      PixelsRead(w, h, px) => {
        own_picture.reading = ""
        @settings.act(
          core,
          @sf.t("android-settings.me.pictureWhat"),
          "account.setPicture",
          obj([("account", str(own_picture.sub)), ("picture", str(@sf.face_picture(w, h, px)))]),
          done=@sf.t("android-settings.me.pictureSet"),
        )
      }
      PixelsFailed => {
        own_picture.reading = ""
        (core.say)(@sf.t("android-settings.me.pictureUnread"))
      }
    }
  }
  // signing out of one: asked first, then the chats (the account in view goes with it)
  let sign_out = fn(sub : String, email : String) {
    @sf.confirm(
      @sf.t("web-pages.settings.account.signOutConfirm", args=[("email", email)]),
      @sf.t("web-pages.settings.account.signOutConfirmBody"),
      @sf.t("web-pages.settings.account.signOutAction"),
      fn() {
        if sub == here.sub {
          (core.home)()
        }
        @settings.act(
          core,
          @sf.t("web-pages.settings.account.signOut"),
          "auth.signOut",
          obj([("account", str(sub))]),
          done=@sf.t("web-pages.settings.account.signedOut", args=[("email", email)]),
        )
      },
    )
  }
  let delete = fn() {
    @sf.confirm(
      @sf.t("web-pages.settings.account.delete"),
      @sf.t("web-pages.settings.account.deleteConfirmBody", args=[("email", here.email)]),
      @sf.t("web-pages.settings.account.deleteAction"),
      danger=true,
      fn() {
        (core.home)()
        @settings.act(
          core,
          @sf.t("web-pages.settings.account.deleteAction"),
          "auth.deleteAccount",
          obj([("account", str(here.sub))]),
          done=@sf.t("web-pages.settings.account.deleted", args=[("email", here.email)]),
        )
      },
    )
  }
  let blocks : Array[() -> Unit] = []
  // the accounts on this device on one card: the one in view with who it is, then the others, each signed out
  // of by itself, another added
  blocks.push(fn() {
    @sf.group(c, fn() {
      @sf.link_row(
        c,
        "",
        name,
        note=here.email + " · " + how,
        strong=true,
        goes=false,
        lead=fn() { own_face(c, core, here.sub, here.email, name, here.picture) },
        control=fn() {
          let words = if others.length() > 0 {
            @sf.t("android-settings.me.signOut")
          } else {
            @sf.t("android-settings.me.signOutOnly")
          }
          @sf.button(c, words, key="sign-out/" + here.sub, tone=Ghost, on_press=fn() {
            sign_out(here.sub, here.email)
          }) |> ignore
        },
      )
      |> ignore
      for a in others {
        let sub = text(Some(a), "sub")
        let email = text(Some(a), "email")
        let shown = if text(Some(a), "name") != "" { text(Some(a), "name") } else { email }
        // each with their face, changed by pressing it as the one in view's
        let lead = fn() { own_face(c, core, sub, email, shown, text(Some(a), "picture")) }
        @sf.link_row(c, "", email, goes=false, lead~, control=fn() {
          @sf.button(c, @sf.t("android-settings.me.signOut"), key="sign-out/" + sub, tone=Ghost, on_press=fn() {
            sign_out(sub, email)
          }) |> ignore
        })
        |> ignore
      }
      @sf.link_row(c, "add-account", @sf.t("android-settings.me.addAccount"), chevron=false, lead=fn() { @sf.row_lead_mark(c, "plus") }, on_press=fn() {
        (core.sign_in)()
      }) |> ignore
    })
  })
  blocks.push(fn() {
    @sf.section(c, @sf.t("web-pages.settings.account.sessions"), heads=true, note=@sf.t("web-pages.settings.account.sessionsLead", args=[("name", "still.fail")]), fn() {
      acc_devices(c, core, here)
    })
  })
  // deleting the account in view, at the foot, in red
  blocks.push(fn() {
    @sf.group(c, fn() {
      @sf.link_row(c, "delete-account", @sf.t("android-settings.me.delete"), danger=true, chevron=false, on_press=fn() {
        delete()
      }) |> ignore
    })
  })
  @sf.page(c, on_back=core.pop, frame~, "me", @sf.t("android-settings.me.title"), blocks)
}

///|
/// The face of an account on this device (`sub`, `email`, `name`, its `picture`), pressed to change it: a camera in its
/// corner says so, spinning while a change of it goes (each change once at a time, of any account). Pressed, the
/// system's photos at once; once it has a picture of its own, a menu beside it to pick another or to take its
/// sign-in's again.
fn own_face(c : @ui.Ctx, core : Core, sub : String, email : String, name : String, picture : String) -> Unit {
  let t = @sf.theme()
  let picking = own_picture.asking || own_picture.reading != ""
  let busy = (picking && own_picture.sub == sub) ||
    is_doing(core, ["account.setPicture", "account.removePicture"], [("account", sub)])
  let id = c.id("own-picture/" + sub)
  c.box(style=own_face_room, id~, label=@sf.t("android-settings.me.picture"), fn() {
    avatar(c, core, email, name, acc_picture, picture~)
    c.box(style=own_face_badge, right=own_face_badge_out, bottom=own_face_badge_out, fn() {
      if busy {
        @sf.spinner(c, size=own_face_mark) |> ignore
      } else {
        @sf.icon(c, "camera", size=own_face_mark, color=t.p.text) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  if !busy && !picking {
    c.on_press(id, fn() {
      if !own_picture_of(core, sub) {
        pick_own_picture(core, sub)
      } else {
        @sf.menu(
          [
            Some(@sf.menu_item_of(@sf.t("android-settings.me.picture"), icon="photo", fn() { pick_own_picture(core, sub) })),
            Some(
              @sf.menu_item_of(@sf.t("android-settings.me.pictureDefault"), icon="user", fn() {
                @settings.act(
                  core,
                  @sf.t("android-settings.me.pictureDefaultWhat"),
                  "account.removePicture",
                  obj([("account", str(sub))]),
                  done=@sf.t("android-settings.me.pictureDefaultSet"),
                )
              }),
            ),
          ],
          from=Of(id),
        )
      }
    })
  }
}

///|
/// The face pressed: round, as it is.
// kept across runs: a value (no field of it changes)
let own_face_room : @ui.Style = @ui.css("radius=Full")

///|
/// The camera in its corner: a small disc of the card's ground, standing off the face.
// kept across runs: a value (no field of it changes)
let own_face_badge : @ui.Style = @ui.css("w=S6 h=S6 radius=Full bg=Card align=ACenter justify=JCenter")

///|
/// How far the camera's disc stands past the face's edge (its corner's).
let own_face_badge_out : Double = -4.0

///|
/// The camera's (or the spinner's) size in its disc.
let own_face_mark : Double = 14.0

///|
/// Where the account is signed in (the `loginSessions` topic): each device's name (this one marked 当前), when it signed
/// in and until when; 退出 on the others (`loginSession.revoke`). Narrow, on a card. Read the first time, rows' shapes
/// where their card's rows will be (3).
fn acc_devices(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let topic = (core.topic)("loginSessions", { "account": str(here.sub) }).get()
  let list = match topic.value {
    Some(Array(a)) => a
    _ => {
      match topic.error {
        Some(e) => @sf.page_note(c, @sf.t("web-pages.settings.account.sessionsFailed", args=[("error", error_text(e))]), bad=true)
        None => @sf.waiting(c, fn() { devices_list(c, core.quiet(), here, devices_sample()) }, text=@sf.t("common.reading"))
      }
      return
    }
  }
  devices_list(c, core, here, list)
}

///|
/// The devices the account is signed in on (`list`): each a row of its own, its name (当前 after it on this one), 退出
/// at its end on the others, when it signed in and until when under them.
fn devices_list(c : @ui.Ctx, core : Core, here : Here, list : Array[Json]) -> Unit {
  @sf.group(c, fn() {
    for d in list {
      let dv = Some(d)
      let id = text(dv, "id")
      let current = flag(dv, "current")
      let name = match text(dv, "name") {
        "" => @sf.t("web-pages.settings.account.unnamedDevice")
        n => n
      }
      let times = @sf.t("web-pages.settings.account.sessionTimes", args=[("time", stamp(dv, "created_at", "ago")), ("until", stamp(dv, "expires_at", "until"))])
      @sf.link_row(
        c,
        "device/" + id,
        name,
        note=times,
        goes=false,
        title_after?=if current { Some(fn() { you(c, @sf.t("web-pages.settings.account.here")) }) } else { None },
        control?=if current {
          None
        } else {
          Some(fn() {
            let revoking = is_doing(core, ["loginSession.revoke"], [("id", id)])
            @sf.button(c, @sf.t("web-pages.settings.account.revoke"), key="revoke/" + id, tone=Ghost, busy=revoking, on_press=fn() {
              @settings.act(
                core,
                @sf.t("web-pages.settings.account.revoke"),
                "loginSession.revoke",
                obj([("id", str(id)), ("account", str(here.sub))]),
                done=@sf.t("web-pages.settings.account.revoked"),
              )
            }) |> ignore
          })
        },
      )
      |> ignore
    }
  })
}

///|
/// A picture of an account's own being had: asked of the system's photo picker, then read to be made its face
/// (me_page), for the account it was asked for (it may be another by then).
priv struct OwnPicture {
  /// the account it is for
  mut sub : String
  /// asked of the system's photo picker
  mut asking : Bool
  /// the picture picked, being read (its key), "" none
  mut reading : String
}

///|
let own_picture : OwnPicture = { sub: "", asking: false, reading: "" }

///|
/// Pictures picked as an account's own, each its own key.
let own_pictures : Ref[Int] = Ref(0)

///|
fn own_picture_reset() -> Unit {
  own_picture.sub = ""
  own_picture.asking = false
  own_picture.reading = ""
  own_pictures.val = 0
}

///|
/// The system's photo picker asked for a picture to be the account `sub`'s own; the one picked read by me_page.
fn pick_own_picture(core : Core, sub : String) -> Unit {
  own_picture.sub = sub
  let asked = (core.pick_picture)(fn(bytes) {
    own_picture.asking = false
    match bytes {
      Some(b) => {
        own_pictures.val += 1
        own_picture.reading = "mem:own-picture/\{own_pictures.val}"
        @ui.add_image(own_picture.reading, b)
      }
      None => ()
    }
  })
  own_picture.asking = asked
  if !asked {
    (core.say)(@sf.t("android-settings.me.pictureUnread"))
  }
}

///|
/// Whether the account `sub` shows a picture of its own (the `workspaces` topic's `ownPicture`), rather than its
/// sign-in's.
fn own_picture_of(core : Core, sub : String) -> Bool {
  match (core.topic)("workspaces", Map([])).get().value {
    Some(Array(entries)) =>
      entries.iter().any(fn(e) { text(field(Some(e), "account"), "sub") == sub && flag(Some(e), "ownPicture") })
    _ => false
  }
}

///|
let acc_picture : Double = @sf.identity_mark

///|
// kept across runs: a value (no field of it changes)
pub let acc_delete_words : @ui.TextStyle = @sf.body.then(@sf.bad)

///|
/// (a narrow page's foot: what takes something away, 16 over it)
// kept across runs: a value (no field of it changes)
pub let acc_narrow_foot : @ui.Style = @ui.css("w=Full pt=S4")

///|
/// Devices made up, for what is shown while they are read (devices_list in its bones): this one and two others.
fn devices_sample() -> Array[Json] {
  [(6, true), (9, false), (7, false)].mapi(fn(i, d) {
    Json::object({
      "id": Json::string("sample" + i.to_string()),
      "name": Json::string(@sf.sample_words(d.0)),
      "current": Json::boolean(d.1),
      "created_at": { "ago": Json::string(@sf.sample_words(4)) },
      "expires_at": { "until": Json::string(@sf.sample_words(4)) },
    })
  })
}
