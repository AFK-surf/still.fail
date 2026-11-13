// Comma's status indicator (status-indicator/StatusIndicator, its <status-indicator> element's tokens: --si-*) as a node
// of the window's tree: a task's four statuses in a row, the chosen one a pill (the quaternary's ground) with its glyph
// in its status's colour and its name, the others each a dot (the disabled foreground's), lit under the hand (the
// icon's colour on a quaternary ground). A press on one chooses it; its colour and the pill's place come over Comma's
// feedback durations. Read out a radio group of radios.

///|
/// A task's status (Comma's visible task-status buckets, in their order).
#derive(Eq, Debug)
pub(all) enum TaskStatus {
  InProgress
  NeedsReview
  Done
  Cancelled
}

///|
/// The four, in Comma's order.
pub let task_statuses : Array[TaskStatus] = [InProgress, NeedsReview, Done, Cancelled]

///|
/// A status's glyph (Central's loader, bubble-alert, circle-check, circle-x) and its colour now.
fn TaskStatus::look(self : TaskStatus) -> (Array[IconLayer], Int64) {
  let c = colors()
  match self {
    InProgress => (icon_loader, c.markdown_icon_primary)
    NeedsReview => (icon_bubble_alert, yellow_500)
    Done => (icon_circle_check, c.fg_success_primary)
    Cancelled => (icon_circle_x, error_500)
  }
}

///|
/// A status's name, as Comma says it in English (its i18n's task-status labels).
pub fn TaskStatus::label(self : TaskStatus) -> String {
  match self {
    InProgress => "In progress"
    NeedsReview => "Needs review"
    Done => "Done"
    Cancelled => "Cancelled"
  }
}

///|
/// Comma's status indicator in `parent`, `chosen` the status shown; a press on another sets it. The node.
#callsite(autofill(loc))
pub fn status_node(
  parent : @view.View,
  chosen : @signals.Signal[TaskStatus],
  label? : String = "Status",
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(g) {
    g.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(space_xxs)).says(Is(Some(@view.said(RadioGroup, label~)))) |> ignore
    for s in task_statuses {
      g.box(fn(item) {
        let on = fn() { chosen.get() == s }
        let hand = eased_by(item, fn() { lit(item, fn() { !on() }) }, ms_feedback_in, ease_smooth_out)
        let pill = eased_by(item, on, ms_feedback_out, ease_surface_smooth_out)
        item
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        .gap(Is(space_xs))
        .height(Is(Some(24.0)))
        .padding(By(fn() { if on() { (space_xs, 0.0, space_md, 0.0) } else { (space_xxs, 0.0, space_xxs, 0.0) } }))
        .radius(Is(12.0))
        .ground(By(fn() {
          let c = colors()
          alpha(c.bg_quaternary, pill.shown(item).max(hand.shown(item)))
        }))
        .says(By(fn() { Some(@view.said(Radio, label=s.label(), check=if on() { On } else { Off })) }))
        |> ignore
        presses_node(item, fn() { chosen.set(s) })
        item.pick(fn() { on() }, fn(p, chose) {
          p.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(space_xs)) |> ignore
          if chose {
            icon_node(p, s.look().0, 16.0, fn() { s.look().1 }) |> ignore
            p.box(fn(w) {
              w
              .words(Is(s.label()), look=words_in(type_mini, weight=weight_medium))
              .ink(By(fn() { colors().text_primary }))
              |> ignore
            })
            |> ignore
          } else {
            // (a dot, in the middle of the 20 its glyph would take)
            p.box(fn(slot) {
              slot.width(Is(Some(space_2xl))).height(Is(Some(space_2xl))).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
              |> ignore
              slot.box(fn(d) {
                d
                .width(Is(Some(space_sm)))
                .height(Is(Some(space_sm)))
                .radius(Is(space_sm / 2.0))
                .ground(By(fn() {
                  let c = colors()
                  mix(c.markdown_icon_primary, hand.shown(item), c.fg_disabled)
                }))
                |> ignore
              })
              |> ignore
            })
            |> ignore
          }
        }, along_row=true)
        ring_node(item, fn() { 12.0 }, ink=focus_gray.1)
      })
      |> ignore
    }
  })
}
