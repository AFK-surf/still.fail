// A chat's page made with its inside nodes (sfbase's chat_page_nodes on; chat_page_made's `body`): its messages the
// page's list (chat_body_node), the composer in the list's foot the page's old view as yet, the way to the newest over
// it (chat_jump_node), a passage a mouse picked in a message quoted by its pill (chat_quote_node). What else the old
// page floats over its list, puts over its rows and flies over it is not here yet.

///|
/// Chat `r`'s messages as `src` reads them (view_of_chat), in node `v`, growing to what the column it is in leaves
/// them, once its view is read (till then none: its bones are the old page's), laid out by the room the column gives it
/// (View::by_room: its width what the shell gives the page, as it changes), under the chat's bar, `cover` tall (where
/// it is drawn to, what hides the list's top), `room` more over its first row, `foot` under its last and the composer
/// `composer` builds under that, in the list's foot (till the view is read, at the foot of the room it is given),
/// `lead` the unread line under its top, its tips `tips`, its time on top `stint`;
/// what is read told the core while `shows` (chat_read_node).
pub fn chat_page_body_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  tips~ : @sf.TipLayer,
  stint~ : () -> Int,
  shows~ : () -> Bool,
  cover? : () -> Double = fn() { bar_foot },
  room? : Double = list_room,
  foot? : () -> Double = fn() { list_foot },
  composer? : (@view.View) -> Unit,
  lead? : Double = unread_lead,
) -> Unit {
  let draft = r.station + ":" + r.session
  let w = @signals.untracked(fn() { @sfbase.writing(src, draft) })
  // the chat's keys (keymap.ts's chat group: the keymap's Chat), its actions here, taken while the tree gives the page
  // keys: Space with no field focused, the cursor in the composer (composer.focus, taken as it is next built); ⌘U the
  // system's file picker for its draft (composer.file) but where the chat is offline; ⌘↓ the list's (chat_body_node)
  v.key_context("Chat")
  .on_action("composer.focus", fn(e) {
    // (the page brought over first where the tape has it behind, at the key's moment, so that its composer takes keys;
    // then at once where its old view's field is drawn, Field::focus; asked of it as it is next built where it is not)
    (@sfbase.page_for_key.val)(e.at)
    w.field.focus()
    composer_take_focus()
    @sfbase.draft_given(draft)
    true
  })
  .on_action("composer.file", fn(_) {
    guard @sfbase.view_of_chat(src, r).0 is Some(cv) && !cv.offline else { return false }
    pick_files(w)
    true
  })
  |> ignore
  // what is let go on it from outside, wherever (a message, its ground; mbui's Tree::drop_at), but on a field (a field
  // takes words where they were let go) or on the composer (its old view's capsule takes them itself): files from this
  // machine's Finder, where it is a station, into the draft by their station and path, as a row of the 文件 tab put
  // there (its composer takes them, files_taken); words dragged in from another app into the composer's field at its
  // caret, as a paste's
  // (by where they are only where this machine is a station, finder_by_station: elsewhere their paths, as words)
  @ui.paths_into(
    v,
    w.field,
    fn(paths) {
      for d in @sfbase.finder_dragged(src, paths) {
        @sfbase.files_into(draft, d)
      }
    },
    takes=fn() { @sfbase.finder_by_station() },
  )
  |> @ui.words_into(w.field)
  |> ignore
  // its words in pieces picked with the pointer (@ui.words_picked), as the old page's in its frame are (c.selectable):
  // nothing that holds it on any screen says so (a settings page's host does: context_node, made_at), a passage of a
  // message quoted from there (chat_quote_node)
  @ui.words_picked(v)
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
  // its pictures that could not be had for want of its station asked again as the chat comes into view (made, or shown
  // again from under what covered it), and as its station is reached again (ChatImages::seen, as its view says it
  // offline or not), as the old page's list asks them (chat_list's)
  v.reacts(shows, fn(now) { if now { src.images.again(r.station) } })
  // (whether it shows, lent to what its rows make: a screen's card previews it only while it does, screen_links_node's)
  v.lends(@sfbase.page_shows_lent, shows) |> ignore
  v.reacts(fn() { read.get().map(fn(x) { !x.0.offline }) }, fn(reached) {
    match reached {
      Some(b) => src.images.seen(r.station, b)
      None => ()
    }
  })
  // (its rows by the width it is given, never one worked out of the shell's state)
  v.by_room(fn(b, given) {
    b.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    let width = fn() { given.width() }
    // (the composer at the foot of the room before the view is read, in the list's foot once it is)
    match composer {
      Some(build) =>
        b.show(fn() { read.get() is None }, fn(o) {
          o.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
          o.box(fn(s) { s.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore }) |> ignore
          build(o)
        })
        |> ignore
      None => ()
    }
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
        // (a quote's card pressed: the message it quotes gone to, where the chat holds it, and the passage it quotes lit
        // there alone where its words have it, as the old page's cards (message.mbt quote_cards): chat_goes_to)
        jump: Some(fn(ts, passage) {
          match @signals.untracked(view).messages.iter().find_first(fn(m) { m.ts == ts }) {
            Some(m) => @sfbase.go_to(r, m.seq, passage~)
            None => ()
          }
        }),
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
        cover~,
        room~,
        foot~,
        composer?,
        lead~,
        read=fn(place, rows) { chat_read_node(o, src, r, view, place, rows, shows, cover) },
        to=r,
        shows~,
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
