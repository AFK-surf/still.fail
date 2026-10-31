// Marking's actions in a picture's bar as nodes of the window's tree (marks_actions's, ImageMarks.kt MarksActions):
// why making the marked picture failed, 取消, 下载标注后的图片, and 添加到对话 where there is a chat's draft to put it in;
// each what it says bound to what says it as that changes, each done at the moment its press is let go on it.

///|
/// What marking's actions say as it changes (marks_actions_node): why making the marked picture failed ("" none);
/// whether something is drawn to keep and nothing is being made (`ready`: 下载 and 添加到对话 able); whether the marked
/// picture is being made; whether there is a chat's draft to put it in; and their words: 取消's, 下载's (read out, its
/// tip), 添加到对话's, and what that one says while it is made.
pub(all) struct MarksActionsSaid {
  error : String
  ready : Bool
  busy : Bool
  can_put : Bool
  cancel : String
  download : String
  put : String
  making : String
} derive(Eq, Show, Debug)

///|
/// The red of why making the marked picture failed (marks_actions's).
let marks_error_ink : Int64 = 0xFF7B6BFFL

///|
/// 添加到对话's ground (ImageMarks.kt: the accent of its own), its words and icon on it.
let marks_put_ground : Int64 = 0xE5704AFFL

///|
/// How far apart marking's actions are (marks_actions's row: gap 4).
let marks_actions_apart : Double = 4.0

///|
/// How wide why it failed is at most, cut short past it.
let marks_error_most : Double = 140.0

///|
/// 添加到对话's icon across.
let marks_put_icon : Double = 12.0

///|
/// How faint 添加到对话 is while it cannot be pressed.
let marks_put_faint : Double = 0.4

///|
/// Marking's actions in `parent` (a bar's row of tools), as marks_actions draws them, saying what `said` says as it
/// changes: why it failed (the meta's size in red, 140 at most, 6 in either side) where it did; 取消 (its words in the
/// ink's quieter colour, 32 high, 10 in either side, round as `corner`); 下载 (a tool_node: the download icon, a marking
/// tool's look and ripple, unable but where it is `ready`), its tip in `tip`; where it `can_put`, 4 further on,
/// 添加到对话 (its send icon and words in white on its ground, 32 high, 12 in either side, 5 between, round as
/// `corner`, faint and taking no press but where it is `ready`; its words what it says while made while `busy`). Each
/// pressed (its press let go on it): `cancel`, `download`, `put`, at that moment. The row's node.
pub fn marks_actions_node(
  parent : @view.View,
  said : () -> MarksActionsSaid,
  ink : () -> ViewerInk,
  corner : @view.Live[Double],
  cancel : () -> Unit,
  download : () -> Unit,
  put : () -> Unit,
  tip? : TipLayer,
) -> @view.View {
  // (its words in the meta's size, a line as marks_actions's are: a size alone said, its line the theme's text_line
  // times it, Ctx::text's; not the meta's own line)
  let meta = fn(weight : Int) -> @view.WordsLook {
    let th = @ui.tree_theme()
    let (size, _) = th.text_size(Meta)
    { size, weight, line: th.text_line * size, wrap: false }
  }
  parent.box(fn(row) {
    row.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(marks_actions_apart)) |> ignore
    // why it failed, where it did
    row.show(fn() { said().error != "" }, fn(e) {
      e
      .padding(Is((@ui.Space::px(S1_5), 0.0, @ui.Space::px(S1_5), 0.0)))
      .max_width(Is(Some(marks_error_most)))
      .clips(Is(true))
      |> ignore
      e.box(fn(w) {
        w
        .words(By(fn() { said().error }))
        .words_look(By(fn() { meta(400) }))
        .ink(Is(marks_error_ink))
        .says(By(fn() { Some(@view.said(Text, label=said().error)) }))
        |> ignore
      })
      |> ignore
    })
    // 取消
    row.box(fn(b) {
      b
      .height(Is(Some(tool_side)))
      .padding(Is((@ui.Space::px(S2_5), 0.0, @ui.Space::px(S2_5), 0.0)))
      .radius(corner)
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(By(fn() { Some(@view.said(Button, label=said().cancel)) }))
      .on_press(cancel)
      |> ignore
      b.box(fn(w) {
        w.words(By(fn() { said().cancel })).words_look(By(fn() { meta(400) })).ink(By(fn() { ink().muted })) |> ignore
      })
      |> ignore
    })
    |> ignore
    // 下载标注后的图片
    tool_node(
      row,
      fn() {
        let s = said()
        { icon: "download", label: s.download, on: false, disabled: !s.ready }
      },
      ink,
      corner,
      download,
      tip?=tip,
      lights=false,
      ripples=true,
    )
    |> ignore
    // 添加到对话, where there is a draft to put it in
    row.show(fn() { said().can_put }, fn(room) {
      room.padding(Is((@ui.Space::px(S1), 0.0, 0.0, 0.0))) |> ignore
      room.box(fn(b) {
        b
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        .height(Is(Some(tool_side)))
        .padding(Is((@ui.Space::px(S3), 0.0, @ui.Space::px(S3), 0.0)))
        .gap(Is(@ui.Space::px(S1_25)))
        .radius(corner)
        .ground(Is(marks_put_ground))
        .alpha(By(fn() { if said().ready { 1.0 } else { marks_put_faint } }))
        .presses(By(fn() { said().ready }))
        .focusable(By(fn() { said().ready }))
        .says(By(fn() {
          let s = said()
          Some(@view.said(Button, label=if s.busy { s.making } else { s.put }))
        }))
        .on_press(fn() {
          if @signals.untracked(fn() { said().ready }) {
            put()
          }
        })
        |> ignore
        b.box(fn(i) {
          i
          .width(Is(Some(marks_put_icon)))
          .height(Is(Some(marks_put_icon)))
          .shapes(Is(
            match icon_numbers("send") {
              Some(d) => icon_shapes(d, marks_put_icon / 24.0, 0x000000FFL)
              None => []
            },
          ))
          .drawn_as(Is("/icon/send/"))
          .tint(Is(0xFFFFFFFFL))
          |> ignore
        })
        |> ignore
        b.box(fn(w) {
          w
          .words(By(fn() {
            let s = said()
            if s.busy {
              s.making
            } else {
              s.put
            }
          }))
          .words_look(By(fn() { meta(600) }))
          .ink(Is(0xFFFFFFFFL))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  })
}
