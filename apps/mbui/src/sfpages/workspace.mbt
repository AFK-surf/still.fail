// Choosing a workspace, making one and answering an invitation, in every tier (the web's cloud/workspace.tsx
// WorkspaceSwitcher, NewWorkspaceDialog; still.fail apps/android settings/screens/Workspaces.kt WorkspacesSheet,
// NewWorkspaceSheet): the workspaces, the one in use checked, what the others have waiting at their end, the
// invitations waiting (加入 `invitation.accept`, 忽略 `invitation.decline`), another account signed in, a new one.
// A new workspace: its name, the account it is made by when more than one is signed in, the invite code once
// still.fail cloud asks for one (`workspace.create`). Joined or made, it is the one in view, at its top. Shown by the
// library's panel (opened from what the frame gives: a sheet with a finger, beside it or in the window's middle with
// a mouse).

///|
/// The new workspace as it is filled in: its name, the account chosen ("" the first), its code, whether one was asked
/// for, being made, why it could not be (the error's code and its words), each a signal (what its nodes bind read
/// them); what closes it once made (the core's answer's, read by none of them). And the invitation being answered (+id
/// joining, -id ignoring).
priv struct NewWorkspace {
  name : @ui.Field
  code : @ui.Field
  owner : @signals.Signal[String]
  asked : @signals.Signal[Bool]
  creating : @signals.Signal[Bool]
  error_code : @signals.Signal[String]
  error : @signals.Signal[String]
  mut close : () -> Unit
  responding : @signals.Signal[String]
}

///|
// kept across runs: put back by workspace_reset (reset)
let new_ws : NewWorkspace = {
  name: @ui.Field::new(),
  code: @ui.Field::new(),
  owner: @signals.signal("", same=fn(a, b) { a == b }),
  asked: @signals.signal(false, same=fn(a, b) { a == b }),
  creating: @signals.signal(false, same=fn(a, b) { a == b }),
  error_code: @signals.signal("", same=fn(a, b) { a == b }),
  error: @signals.signal("", same=fn(a, b) { a == b }),
  close: fn() {  },
  responding: @signals.signal("", same=fn(a, b) { a == b }),
}

///|
fn workspace_reset() -> Unit {
  new_ws_cleared()
  new_ws.responding.set("")
  ws_menu.set(false)
}

///|
/// The new workspace's fields as they are before it opens.
fn new_ws_cleared() -> Unit {
  new_ws.name.set("")
  new_ws.code.set("")
  new_ws.owner.set("")
  new_ws.asked.set(false)
  new_ws.creating.set(false)
  new_ws.error_code.set("")
  new_ws.error.set("")
  new_ws.close = fn() {  }
}

///|
/// The workspace `ws` the one in view, at its top (the prefs' `workspace`: the rail's switch, the list's row), once
/// what its Home opens on is answered, switch_wait_ms at most (sfbase's switch_workspace_to).
pub fn switch_workspace(src : Source, ws : String, closes? : () -> Unit = fn() {  }) -> Unit {
  @sfbase.switch_workspace_to(src, ws, closes~)
}

// ── the workspaces ─────────────────────────────────────────────────────

///|
/// The workspace sheet; compact headings may request a content-sized panel instead of the usual tall list. What it
/// holds nodes of the window's tree, made once as it opens (@sf.panel_nodes), each bound to what the core says now.
pub fn open_workspaces(src : Source, from : @sf.Anchor, compact? : Bool = false) -> Unit {
  @sf.panel_nodes(
    @sf.t("android-misc.workspace.sheet.title"),
    fn(v, close) { workspaces_list(v, src, close, compact~) },
    from~,
    tall=if compact { 0.0 } else { workspaces_tall },
    grows=true,
  )
}

///|
let workspaces_tall : Double = 0.7

///|
/// What the list holds, top to bottom: the one in use (its label, its card, the invitations under it), the others'
/// label, the others by their ids.
#derive(Eq, Hash)
priv enum WsBlock {
  InUse
  OthersLabel
  Other(String)
}

///|
/// The list in node `v` (the panel's body's): the one in use (checked) on a card, the invitations waiting, the others
/// to switch to, then signing in another account and a new one; each block made as the core lists it and let go as it
/// lists it no more, what it says bound to what the core says of it now. Filling a share of the window, the list
/// scrolls in it (@sf.panel_list_node), its foot staying under it: more workspaces than the share holds are reached by
/// scrolling, not cut off. Nothing while none is in view (the prefs not read yet).
fn workspaces_list(v : @view.View, src : Source, close : () -> Unit, compact~ : Bool) -> Unit {
  // (what each workspace has waiting, as the one in use's marks say it)
  let marks_now = fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(_) => field(src.topic("workspaceMarks", @sfbase.marks_asked()).get().value, "workspaces")
      None => None
    }
  }
  // (a workspace pressed to switch to: the list as it was at the press held from then till the sheet is gone, the one
  // in use, the others in their order and what they have waiting, however the switch changes them meanwhile: what the
  // press put up is part of the screen as it was, sfbase's switch_workspace_to. Opened again, made anew: as it is then)
  let held : @signals.Signal[(Workspace?, Array[Workspace], Json?)?] = @signals.signal(None)
  let hold = fn() {
    if held.untracked() is None {
      let (now, all, _, _) = @signals.untracked(fn() { @sfbase.workspace_in_view(src) })
      held.set(Some((now, all, @signals.untracked(marks_now))))
    }
  }
  let in_view = fn() -> (Workspace?, Array[Workspace]) {
    match held.get() {
      Some((now, all, _)) => (now, all)
      None => {
        let (now, all, _, _) = @sfbase.workspace_in_view(src)
        (now, all)
      }
    }
  }
  let others = fn() {
    match in_view() {
      (Some(w), all) => all.filter(fn(x) { x.id != w.id })
      _ => []
    }
  }
  let marks = fn() {
    match held.get() {
      Some((_, _, m)) => m
      None => marks_now()
    }
  }
  let blocks = fn() -> Array[WsBlock] {
    guard in_view().0 is Some(_) else { return [] }
    let out = [InUse]
    let o = others()
    if o.length() > 0 {
      out.push(OthersLabel)
    }
    for x in o {
      out.push(Other(x.id))
    }
    out
  }
  let block = fn(b : @view.View, k : WsBlock) {
    match k {
      InUse => ws_in_use_node(b, src, fn() { in_view().0 }, close)
      OthersLabel => ws_label_node(b, fn() { @sf.t("android-misc.workspace.others") })
      Other(id) => {
        let find = fn() { others().iter().find_first(fn(x) { x.id == id }) }
        // (listed no more, it closes its way down the list showing what it showed last, not a blank row: as the
        // transfers' list keeps its last as it goes (#5160's `last`), a row's own)
        let seen : Ref[Workspace] = Ref(
          @signals.untracked(find).unwrap_or({ id, name: "", emoji: "", icon: "", email: "" }),
        )
        let w = fn() {
          match find() {
            Some(x) => {
              seen.val = x
              x
            }
            None => seen.val
          }
        }
        workspace_row_node(
          b,
          fn() { w().name },
          fn() { w().email },
          lead=w,
          mark=fn() { field(marks(), id).unwrap_or(Json::null()) },
          // (the sheet closed as the switch is done, with it, showing till then what it showed at the press:
          // sfbase's switch_workspace_to)
          fn() {
            hold()
            switch_workspace(src, id, closes=close)
          },
        )
      }
    }
  }
  if compact {
    v.box(fn(list) {
      @sf.style_node(list, fn() { ws_list_compact })
      // (each block in a box of no padding of its own: what comes and goes down a column closes its way to none of
      // what it holds, its padding not)
      list.each(blocks, fn(k) { k }, fn(row, k) { row.box(fn(b) { block(b, k.untracked()) }) |> ignore })
    })
    |> ignore
  } else {
    // (the panel its share whatever the list holds, as when the list did not scroll: fills)
    v.box(fn(room) {
      @sf.style_node(room, fn() { ws_list })
      @sf.panel_list_node(
        room,
        blocks,
        fn(r, k) {
          r.box(fn(b) {
            @sf.style_node(b, fn() { ws_list_row })
            block(b, k)
          })
          |> ignore
        },
        est=ws_block_est,
        fills=true,
      )
      |> ignore
    })
    |> ignore
  }
  // (down the panel's column: making its way in as a workspace comes into view, closing it as none is)
  v.show(fn() { in_view().0 is Some(_) }, fn(foot) {
    @sf.style_node(foot, fn() { ws_foot })
    workspace_row_node(
      foot,
      fn() { @sf.t("android-misc.workspace.addAccount") },
      fn() { @sf.t("android-misc.workspace.addAccount.sub") },
      icon="log-in",
      fn() {
        close()
        (src.sign_in)()
      },
    )
    // (in place of the list: one over another is not stacked)
    workspace_row_node(foot, fn() { @sf.t("android-misc.workspace.new") }, fn() { "" }, icon="plus", fn() {
      close()
      open_new_workspace(src)
    })
  })
}

///|
/// How tall a block of the list is taken to be before it is first laid out.
let ws_block_est : Double = 64.0

///|
/// The one in use in node `b`: its label, the card it is on (pressed, what showed the list closed: it is in view
/// already), then the invitations waiting. `now`: the one in use now (as it was last, while there is none).
fn ws_in_use_node(b : @view.View, src : Source, now : () -> Workspace?, close : () -> Unit) -> Unit {
  // (none in view any more, the block closes its way showing the card as it was last, not a blank one: as the
  // transfers' list keeps its last as it goes, #5160's `last`)
  let seen : Ref[Workspace] = Ref(
    @signals.untracked(now).unwrap_or({ id: "", name: "", emoji: "", icon: "", email: "" }),
  )
  let w = fn() {
    match now() {
      Some(x) => {
        seen.val = x
        x
      }
      None => seen.val
    }
  }
  ws_label_node(b, fn() { @sf.t("android-misc.workspace.current") })
  b.box(fn(out) {
    @sf.style_node(out, fn() { ws_current.then(@sf.panel_card_out_node(out)) })
    out.box(fn(card) {
      @sf.style_node(card, fn() { ws_card.then(@ui.style(bg=Data(@sf.theme().p.chip))) })
      workspace_row_node(card, fn() { w().name }, fn() { w().email }, checked=true, lead=w, on_card=true, close)
    })
    |> ignore
  })
  |> ignore
  ws_invitations_node(b, src, close)
}

///|
/// A part's label (13, muted) in `parent`, `label` as it is said now: as far in as the panel's words, 6 over it and 2
/// under.
fn ws_label_node(parent : @view.View, label : () -> String) -> Unit {
  parent.box(fn(l) {
    @sf.style_node(l, fn() { ws_label_box.then(@sf.panel_words_in_node(l)) })
    @sf.words_node(l, label, fn() { ws_label_words }) |> ignore
  })
  |> ignore
}

///|
/// A row in `parent`: what (`label`), a line under it (`sub`, none where ""), a check on the one in use (`checked`);
/// before it a workspace's mark or its letter (`lead`) or an icon; after it what a workspace has waiting (`mark`: its
/// marks), each as it is now. `press` done as it is pressed, rippling as Workspaces.kt's row does (clip(Smooth(
/// LIST_ROW_CORNER)).clickable); read out a button named `label`. `on_card`: the one in use's, on its card.
fn workspace_row_node(
  parent : @view.View,
  label : () -> String,
  sub : () -> String,
  checked? : Bool = false,
  lead? : () -> Workspace,
  icon? : String = "",
  mark? : () -> Json = fn() { Json::null() },
  on_card? : Bool = false,
  press : () -> Unit,
) -> Unit {
  // (in a panel: on its card (the one in use), or a row of the panel's own `panel_card_in` from its sides; either way
  // its mark and words on the panel's words' line, every row's on one)
  parent.box(fn(o) {
    @sf.style_node(o, fn() { if on_card { ws_row_on_card } else { ws_row_in.then(@sf.panel_card_out_node(o)) } })
    o.box(fn(r) {
      @sf.style_node(r, fn() { if on_card { ws_row_card } else { ws_row } })
      @sf.rippled_node(r, press, if on_card { @sf.row_corner } else { @sf.card_corner }, label)
      match lead {
        Some(w) =>
          r.box(fn(l) {
            @sf.style_node(l, fn() { ws_row_lead }, in_row=true)
            ws_mark_node(l, w)
          })
          |> ignore
        None => ()
      }
      // (an icon in the same square a mark stands in: the rows' words on one line, a workspace's or an action's)
      if icon != "" {
        r.box(fn(l) {
          @sf.style_node(l, fn() { ws_row_lead }, in_row=true)
          @sf.icon_node(l, icon, ws_row_icon, By(fn() { @sf.theme().p.text })) |> ignore
        })
        |> ignore
      }
      r.box(fn(words) {
        @sf.style_node(words, fn() { @sf.full_width }, in_row=true)
        @sf.words_node(words, label, fn() { ws_row_label }) |> ignore
        // (as wide as it says, cut short where the row has not the room: ws_row_sub's w=Cut; under the label, down the
        // words' column: making its way in as it comes to say something, closing it as it says nothing)
        words.show(fn() { sub() != "" }, fn(s) {
          s.lines_up(Is(Some(Start))) |> ignore
          @sf.words_node(s, sub, fn() { ws_row_sub }) |> ignore
        })
      })
      |> ignore
      ws_mark_counts_node(r, mark)
      if checked {
        @sf.icon_node(r, "check", ws_row_check, By(fn() { @sf.theme().p.accent })) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A workspace's mark (`w`'s, as it is now) in `parent`, ws_row_mark across in the words' ink, else its first letter
/// (ws_row_letter, part of the mark: at its size whatever the system's size of words, mark_words_node), one in the
/// other's place (a pick: its way from as tall as the other was).
fn ws_mark_node(parent : @view.View, w : () -> Workspace) -> Unit {
  parent.pick(fn() { workspace_marked(w()) }, fn(m, marked) {
    if marked {
      let ink = fn() { @sf.theme().p.text }
      @sf.station_mark_node(m, fn() { w().emoji }, fn() { w().icon }, ws_row_mark, ink, fn() { 0 })
    } else {
      @sf.mark_words_node(m, fn() { @sf.initial(w().name) }, fn() { ws_row_letter }) |> ignore
    }
  })
}

///|
/// What a workspace has waiting, after its name, in `parent` as `mark` (its marks) says it now: the chats its person
/// takes part in that went wrong, and those where it is their turn (waiting on them or unread), each its mark
/// (chat_mark_node: red, blue) and how many, 8 apart; read out as what it says (MarkCounts' contentDescription).
fn ws_mark_counts_node(parent : @view.View, mark : () -> Json) -> Unit {
  let m = fn() { Some(mark()) }
  parent.show(fn() { text(m(), "tone") != "" }, fn(box) {
    @sf.style_node(box, fn() { ws_counts }, in_row=true)
    box.says(By(fn() { Some(@view.said(Text, label=text(m(), "label"))) })) |> ignore
    for k in [("alert", ["alert"]), ("done", ["wait", "unread"])] {
      let n = fn() { k.1.fold(init=0, fn(n, x) { n + @sfbase.count(m(), x) }) }
      box.show(fn() { n() > 0 }, fn(c) {
        @sf.style_node(c, fn() { ws_count }, in_row=true)
        chat_mark_node(c, fn() { k.0 })
        @sf.words_node(c, fn() { "\{n()}" }, fn() { ws_count_words }) |> ignore
      })
    }
  })
}

///|
/// The list: the room it scrolls in, 24 over its foot.
// kept across runs: a value (no field of it changes)
let ws_list : @ui.Style = @ui.css("w=Full h=Full pb=S6")

///|
/// A row of the list, across it.
// kept across runs: a value (no field of it changes)
let ws_list_row : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let ws_list_compact : @ui.Style = @ui.css("w=Full pb=S3")

///|
/// The one in use: on a card 12 in from the sides, 4 under its label, 16 over what follows.
// kept across runs: a value (no field of it changes)
let ws_current : @ui.Style = @ui.css("w=Full pt=S1 pb=S4")

///|
/// A list card: its rows list_pad in, the list card's corner, on the chips' grey.
// kept across runs: a value (no field of it changes)
let ws_card : @ui.Style = @ui.style(w=Full, p=@sf.room_of(@sf.corner_inset), radius=@sf.card_radius, clip=true)

///|
/// Signing in another account and a new one: 8 under the list, 16 over the foot.
// kept across runs: a value (no field of it changes)
let ws_foot : @ui.Style = @ui.css("w=Full pt=S2 pb=S4")

///|
// kept across runs: a value (no field of it changes)
let ws_label_box : @ui.Style = @ui.css("pt=S1_5 pb=S0_5")

///|
// kept across runs: a value (no field of it changes)
let ws_label_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, leading=Font)

///|
/// On a sheet: 12 in from its sides; the row 8 more in, 12 over and under, 12 apart.
// kept across runs: a value (no field of it changes)
let ws_row_in : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let ws_row_on_card : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let ws_row : @ui.Style = @ui.css("row w=Full py=S3 gap=S3 align=ACenter").then(@ui.style(px=@sf.room_of(@sf.panel_words - @sf.panel_card_in)))

///|
/// On the card (the one in use, among the rows of the others): its mark and words where the other rows' are, on the
/// panel's words' line; the card `panel_card_in` from the panel's sides and `corner_inset` in already, as far as the
/// rows' grounds reach, the rest of the way here (2026-11-07: a row's room more put its mark 16 past the others').
// kept across runs: a value (no field of it changes)
let ws_row_card : @ui.Style = @ui.css("row w=Full py=S3 gap=S3 align=ACenter").then(@ui.style(px=@sf.room_of(@sf.panel_words - @sf.panel_card_in - @sf.corner_inset)))

///|
/// A workspace's mark or its letter in a square 24 across: the mark 22, the letter 15 semibold, muted; an icon 20 in
/// the same square (an action's: 登录其他账号, 新建 workspace), the check 14.
// kept across runs: a value (no field of it changes)
let ws_row_lead : @ui.Style = @ui.css("w=S6 h=S6 align=ACenter justify=JCenter")

///|
let ws_row_mark : Double = 22.0

///|
let ws_row_icon : Double = 20.0

///|
let ws_row_check : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let ws_row_letter : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Muted, wrap=false, leading=Font)

///|
/// What, 15 on 21; the line under it 12 on 17, muted.
// kept across runs: a value (no field of it changes)
let ws_row_label : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let ws_row_sub : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut, leading=@sf.pick_sub_line)

///|
// kept across runs: a value (no field of it changes)
let ws_counts : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ws_count : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ws_count_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, leading=Font)

// ── the invitations ────────────────────────────────────────────────────

///|
/// The invitations waiting for any account signed in, each with the account it is for (the rail's ＋ shows them too).
pub fn invitations_waiting(src : Source) -> Array[(Json?, Json)] {
  let out : Array[(Json?, Json)] = []
  match src.topic("workspaces", {}).get().value {
    Some(Array(a)) =>
      for e in a {
        for i in items(Some(e), "invitations") {
          out.push((field(Some(e), "account"), i))
        }
      }
    _ => ()
  }
  out
}

///|
/// Who invited the viewer where (an invitation's line).
pub fn invited_you(inv : Json) -> String {
  let iv = Some(inv)
  @sf.t("android-misc.invite.invitedYou", args=[
    (
      "inviter",
      match text(iv, "inviter") {
        "" => @sf.t("android-misc.invite.someone")
        w => w
      },
    ),
    ("name", text(iv, "name")),
  ])
}

///|
/// The invitations in the list in node `b`, under 邀请: who invited the viewer where, the account it is for, 加入 and
/// 忽略; each made as the core lists it, let go as it lists it no more. 加入 done, `close` first.
fn ws_invitations_node(b : @view.View, src : Source, close : () -> Unit) -> Unit {
  let pending = fn() { invitations_waiting(src) }
  b.show(fn() { pending().length() > 0 }, fn(l) { ws_label_node(l, fn() { @sf.t("android-misc.invite.label") }) })
  // (each in a box of no padding of its own: what comes and goes down a column closes its way to none of what it
  // holds, its padding not)
  b.each(pending, fn(p) { text(Some(p.1), "id") }, fn(row, p) {
    let id = text(Some(p.untracked().1), "id")
    row.box(fn(line) {
      @sf.style_node(line, fn() { invite_line })
      line.box(fn(w) {
        @sf.style_node(w, fn() { @sf.full_width }, in_row=true)
        @sf.words_node(w, fn() { invited_you(p.get().1) }, fn() { invite_line_words }) |> ignore
        @sf.words_node(w, fn() { text(p.get().0, "email") }, fn() { invite_line_email }) |> ignore
      })
      |> ignore
      let answer = fn(join : Bool) {
        if new_ws.responding.get() == "" {
          let (account, inv) = p.get()
          answer_invitation(src, account, id, join, text(Some(inv), "name"), if join { close } else { fn() {  } })
        }
      }
      @sf.button_node(line, fn() { @sf.t("android-misc.invite.join") }, fn() { answer(true) }, tone=Primary, busy=fn() {
        new_ws.responding.get() == "+" + id
      })
      |> ignore
      @sf.button_node(line, fn() { @sf.t("android-misc.invite.ignore") }, fn() { answer(false) }, busy=fn() {
        new_ws.responding.get() == "-" + id
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// An invitation: 20 in, 8 over and under, 8 apart; its words the body's, the account under them small and muted.
// kept across runs: a value (no field of it changes)
let invite_line : @ui.Style = @ui.css("row w=Full px=S5 py=S2 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let invite_line_words : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let invite_line_email : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// An invitation joined (its workspace the one in view, what showed it closed as that is done: `joined`) or ignored, said and
/// felt so once done; why not, said so and felt as refused.
pub fn answer_invitation(src : Source, account : Json?, id : String, join : Bool, name : String, joined : () -> Unit) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  new_ws.responding.set((if join { "+" } else { "-" }) + id)
  let params : Json = { "account": Json::string(text(account, "sub")), "id": Json::string(id) }
  (src.call)(if join { "invitation.accept" } else { "invitation.decline" }, params, fn(r) {
    new_ws.responding.set("")
    match r {
      Ok(v) => {
        @ui.haptic(Confirm)
        if join {
          switch_workspace(src, text(Some(v), "id"), closes=joined)
          toast_later(@sf.t("web-pages.workspace.joined", args=[("name", name)]))
        } else {
          toast_later(@sf.t("web-pages.workspace.ignored"))
        }
      }
      Err(e) => {
        @ui.haptic(Reject)
        toast_later(
          @sf.t(if join { "web-pages.cloud.joinFailed" } else { "web-pages.workspace.ignoreFailed" }, args=[
            ("error", error_words(e)),
          ]),
        )
      }
    }
  })
}

// ── a new workspace ────────────────────────────────────────────────────

///|
/// A new workspace (NewWorkspaceDialog), empty, its name's field taking what is typed as it opens: in the window's
/// middle (a sheet with a finger). What it holds nodes of the window's tree, made once as it opens (@sf.panel_nodes).
pub fn open_new_workspace(src : Source) -> Unit {
  new_ws_cleared()
  @sf.panel_nodes(
    @sf.t("web-pages.workspace.create"),
    fn(v, close) { new_workspace_body(v, src, close) },
    from=Unanchored,
    description=@sf.t("web-pages.workspace.createLead"),
    foot=fn(v, close) { new_workspace_foot(v, src, close) },
    gone=fn() { if !new_ws.creating.get() { new_ws_cleared() } },
  )
}

///|
/// A new workspace opened with `name` and `code` typed in it, and what still.fail cloud said of the last try where
/// `error_code` is one (its words as make_workspace says them, the code's field shown for one of an invite code's): the
/// fixture's new-workspace screens (sfapp's open_fixture_src).
pub fn new_workspace_put(src : Source, name~ : String, code~ : String, error_code~ : String) -> Unit {
  open_new_workspace(src)
  new_ws.name.set(name)
  new_ws.code.set(code)
  if error_code != "" {
    new_ws.error_code.set(error_code)
    new_ws.error.set(landing_error_words({ "code": Json::string(error_code) }))
    if invite_error_key(error_code) is Some(_) {
      new_ws.asked.set(true)
    }
  }
}

///|
/// The account it is made by: the one chosen, else the first signed in.
fn new_ws_owner(src : Source) -> (Array[Json], String) {
  let accounts = match src.topic("accounts", {}).get().value {
    Some(Array(a)) => a
    _ => []
  }
  let owner = match accounts.iter().find_first(fn(a) { text(Some(a), "sub") == new_ws.owner.get() }) {
    Some(a) => text(Some(a), "sub")
    None =>
      match accounts.get(0) {
        Some(a) => text(Some(a), "sub")
        None => ""
      }
  }
  (accounts, owner)
}

///|
/// Made, if it can be (a name, an account, nothing being made).
fn new_ws_create(src : Source, close : () -> Unit) -> Unit {
  let (_, owner) = new_ws_owner(src)
  let name = new_ws.name.text().trim(chars=" \n\t").to_owned()
  let code = new_ws.code.text().trim(chars=" \n\t").to_owned()
  if name != "" && owner != "" && !new_ws.creating.get() {
    new_ws.close = close
    make_workspace(src, owner, name, code)
  }
}

///|
/// What it holds in node `v` (the panel's body's): 名称 (Enter makes it; the keys its own as a dialog in the window's
/// middle opens), 所属账号 among several accounts, 邀请码 once asked for (what is wrong with it under it, else what it is
/// for), what else went wrong; each as it is now.
fn new_workspace_body(v : @view.View, src : Source, close : () -> Unit) -> Unit {
  let accounts = fn() { new_ws_owner(src).0 }
  let wants_code = fn() { invite_error_key(new_ws.error_code.get()) is Some(_) }
  let code = fn() { new_ws.code.text().trim(chars=" \n\t").to_owned() }
  @sf.field_node(v, fn() { @sf.t("web-pages.settings.workspace.name") }, fn(b) {
    let f = @sf.input_node(b, new_ws.name, placeholder=@sf.t("web-pages.workspace.namePlaceholder"), submitted=fn(_) {
      new_ws_create(src, close)
    })
    // (its first field: it has the keys as it opens, however it is shown, as the old one asked for them till it had them)
    @sf.panel_opens_in_node(f)
  })
  v.show(fn() { accounts().length() > 1 }, fn(s) {
    @sf.field_node(s, fn() { @sf.t("web-pages.workspace.owner") }, fn(b) {
      @sf.one_of_node(
        b,
        fn() { new_ws_owner(src).1 },
        fn() { accounts().map(fn(a) { (text(Some(a), "sub"), text(Some(a), "email")) }) },
        fn(x) { new_ws.owner.set(x) },
        label=fn() { @sf.t("web-pages.workspace.owner") },
      )
    })
  })
  v.show(fn() { new_ws.asked.get() || wants_code() }, fn(s) {
    @sf.labelled_field_node(
      s,
      fn() { @sf.t("web-pages.cloud.inviteCode") },
      fn(b) {
        @sf.input_node(b, new_ws.code, placeholder="XXXX-XXXX-XXXX", submitted=fn(_) {
          if code() != "" {
            new_ws_create(src, close)
          }
        })
        |> ignore
      },
      hint=fn() { @sf.t("web-pages.workspace.codeHint", args=[("name", "still.fail")]) },
      error=fn() { if wants_code() && code() != "" { new_ws.error.get() } else { "" } },
    )
  })
  v.show(fn() { new_ws.error.get() != "" && !wants_code() }, fn(s) {
    @sf.words_node(s, fn() { new_ws.error.get() }, fn() { new_ws_failed }) |> ignore
  })
}

///|
/// Its foot in node `v`: 取消 and 新建 (waiting while it is made, not pressed while nothing is named).
fn new_workspace_foot(v : @view.View, src : Source, close : () -> Unit) -> Unit {
  let name = fn() { new_ws.name.text().trim(chars=" \n\t").to_owned() }
  @sf.button_node(v, fn() { @sf.t("common.cancel") }, fn() {
    close()
    new_ws_cleared()
  }, tone=Ghost)
  |> ignore
  @sf.button_node(
    v,
    fn() { @sf.t("web-pages.workspace.createAction") },
    fn() { new_ws_create(src, close) },
    tone=Primary,
    busy=fn() { new_ws.creating.get() },
    disabled=fn() { name() == "" },
  )
  |> ignore
}

///|
/// What else went wrong (fieldError: the meta's size, red).
// kept across runs: a value (no field of it changes)
let new_ws_failed : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, w=Full)

///|
/// Makes it (`workspace.create`): the one in view once made, what showed it closed; else why, and the code's field
/// once one is wanted (sent every time: still.fail cloud looks at it only for an account not let in yet).
fn make_workspace(src : Source, owner : String, name : String, code : String) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  let params : Map[String, Json] = { "account": Json::string(owner), "name": Json::string(name) }
  if code != "" {
    params["invite_code"] = Json::string(code)
  }
  new_ws.creating.set(true)
  new_ws.error.set("")
  new_ws.error_code.set("")
  (src.call)("workspace.create", Json::object(params), fn(r) {
    new_ws.creating.set(false)
    match r {
      Ok(v) => {
        let close = new_ws.close
        new_ws_cleared()
        switch_workspace(src, text(Some(v), "id"), closes=close)
      }
      Err(e) => {
        new_ws.error_code.set(text(Some(e), "code"))
        new_ws.error.set(landing_error_words(e))
        if invite_error_key(new_ws.error_code.get()) is Some(_) {
          new_ws.asked.set(true)
        }
      }
    }
  })
}

// ── on the rail ────────────────────────────────────────────────────────

///|
/// Whether the ＋'s menu is open (the frame holds the sidebar out while it is; the ＋ lit while it is).
// kept across runs: put back by workspace_reset (reset)
let ws_menu : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
pub fn workspace_menu_open() -> Bool {
  ws_menu.get()
}

///|
/// The ＋ over the workspaces at the rail's foot pressed and let go (sfdesk's rail_node): its menu opened, or closed
/// where it is open.
pub fn workspace_add_pressed() -> Unit {
  ws_menu.set(!ws_menu.get())
}

///|
/// The ＋'s menu, beside the ＋ (a node of the window's tree, where it was placed as it was pressed: `at`), its foot
/// level with the ＋'s (WorkspaceSwitcher `adder`): 新建 workspace, 添加另一个账号, then the invitations waiting, each
/// joined or ignored. Drawn over the frame (sfdesk's rail_overlays). A press on the ＋ while it is open is one outside
/// it, as the menu is modal: it closes it, and the ＋ under it is not pressed.
pub fn workspace_menu(c : @ui.Ctx, src : Source, at : (Double, Double, Double, Double)) -> Unit {
  let entries : Array[@kit.Entry] = [
    @kit.menu_item("create", label=@sf.t("web-pages.workspace.create")),
    @kit.menu_item("account", label=@sf.t("web-pages.workspace.addAccount")),
  ]
  let icons : Map[String, String] = { "create": "plus", "account": "user-plus" }
  let pending = invitations_waiting(src)
  if pending.length() > 0 {
    entries.push(@kit.menu_separator())
    entries.push(@kit.menu_label(@sf.t("web-pages.workspace.invitations")))
    for p in pending {
      let iv = Some(p.1)
      let id = text(iv, "id")
      let inviter = match text(iv, "inviter") {
        "" => @sf.t("web-pages.cloud.someone")
        x => x
      }
      entries.push(
        @kit.menu_label(@sf.t("web-pages.workspace.invitedYou", args=[("inviter", inviter), ("name", text(iv, "name"))])),
      )
      entries.push(@kit.menu_item("join:" + id, label=@sf.t("web-pages.cloud.join")))
      entries.push(@kit.menu_item("ignore:" + id, label=@sf.t("web-pages.workspace.ignore")))
    }
  }
  // beside it, its foot level with the ＋'s (side right, align end, sideOffset 10)
  // (dismissed by the hand, Escape or a press outside it and the ＋: closed at that moment; closed as an item is chosen)
  let menu : Ref[@kit.Menu?] = Ref(None)
  c.with_dismissed(fn(_) { ws_menu.set(false) }, fn() {
    menu.val = Some(
      @sf.dropdown(
        c,
        "rail/ws-menu",
        ws_menu.get(),
        0,
        entries,
        icons,
        rail_ws_menu_w,
        side=Right,
        along=End,
        offset=rail_ws_menu_off,
        at~,
      ),
    )
  })
  let m = menu.val.unwrap()
  if m.chosen is Some(_) {
    ws_menu.set(false)
  }
  match m.chosen {
    Some("create") => open_new_workspace(src)
    Some("account") => (src.sign_in)()
    Some(v) if v.has_prefix("join:") || v.has_prefix("ignore:") => {
      let join = v.has_prefix("join:")
      let id = v.exact_view(start=if join { 5 } else { 7 }).to_owned()
      for p in pending {
        if text(Some(p.1), "id") == id {
          answer_invitation(src, p.0, id, join, text(Some(p.1), "name"), fn() {  })
        }
      }
    }
    _ => ()
  }
}


///|
let rail_ws_menu_off : Double = 10.0

///|
/// The ＋'s menu: 260 at least.
let rail_ws_menu_w : Double = 260.0
