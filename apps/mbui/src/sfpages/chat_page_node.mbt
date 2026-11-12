// A chat's page made with its inside nodes (sfbase's chat_page_nodes on; chat_page_made's `body`): its messages the
// page's list (chat_body_node), the composer under them the page's old view as yet. What the old page floats over its
// list, puts over its rows and flies over it is not here yet.

///|
/// Chat `r`'s messages as `src` reads them (view_of_chat), in node `v`, growing to what the column it is in leaves
/// them, once its view is read (till then none: its bones are the old page's), laid out by the room the column gives it
/// (View::by_room: its width what the shell gives the page, as it changes), `top` over its first row (its bar's room),
/// `foot` under its last, `lead` the unread line under its top, its tips `tips`, its time on top `stint`.
pub fn chat_page_body_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  tips~ : @sf.TipLayer,
  stint~ : () -> Int,
  top? : () -> Double = fn() { list_top },
  foot? : () -> Double = fn() { list_foot },
  lead? : Double = unread_lead,
) -> Unit {
  // (its view and entries as last read: once read, never none again while the page is)
  let read : @signals.Computed[(ChatView, Array[Entry])?] = @signals.computed(
    fn(was) {
      match @sfbase.view_of_chat(src, r) {
        (Some(view), entries, _) => Some((view, entries))
        _ =>
          match was {
            Some(w) => w
            None => None
          }
      }
    },
    // (told only as the view or its entries are other ones: the chat's list keeps both while nothing of it changed,
    // sfbase's chat_read; another topic's change reads none of the rows again)
    same=fn(a, b) {
      match (a, b) {
        (Some((v1, e1)), Some((v2, e2))) => physical_equal(v1, v2) && physical_equal(e1, e2)
        (None, None) => true
        _ => false
      }
    },
  )
  // (its rows by the width it is given, never one worked out of the shell's state)
  v.by_room(fn(b, room) {
    b.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    let width = fn() { room.width() }
    b.show(fn() { read.get() is Some(_) }, fn(o) {
      o.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
      let first = @signals.untracked(fn() { read.get().unwrap() })
      let view = fn() {
        match read.get() {
          Some((view, _)) => view
          None => first.0
        }
      }
      let here : MessageNodeHere = {
        station: r.station,
        session: r.session,
        view,
        width,
        tips,
        stint,
        jump: None,
      }
      let core = @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }).map(fn(w) { @sfbase.settings_core(src, w) })
      chat_body_node(
        o,
        src,
        here,
        fn() {
          match read.get() {
            Some((_, entries)) => entries
            None => first.1
          }
        },
        sending=fn() { @sfbase.sending_now(r.station + "\u{1}" + r.session) },
        core~,
        top~,
        foot~,
        lead~,
      )
      |> ignore
    })
    |> ignore
  })
  .grow(Is(1.0))
  .shrink(Is(1.0))
  .basis(Is(Some(0.0)))
  .min_height(Is(Some(0.0)))
  |> ignore
}
