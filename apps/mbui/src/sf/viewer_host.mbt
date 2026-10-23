// What a viewer (reader.mbt, player.mbt) asks of the page it is drawn on, told once as the app starts (web/ui
// viewer/host.ts setViewerHost): whether it is a phone's (narrow), what a link in Markdown opens, where the reader's
// layout is kept, and the page's core reading a text for the reader. With none told: a wide page's, its layout kept
// here, a text as it is. (The theme is the library's own: @sf.theme().)

///|
/// A chapter heading: its words and where it starts in the text.
pub(all) struct Chapter {
  title : String
  offset : Int
}

///|
/// A text as the core reads it for a reader (client/core-ts/src/reader.ts `reader.book`): its id (to find words in it
/// with), the text as joined (a hard-wrapped novel's lines joined into paragraphs), the column it was wrapped at (0:
/// none), its chapters and where its heading lines start; a Markdown file's tree (the core's nodes, as a chat's words
/// are drawn: markdown.mbt).
pub(all) struct ReadBook {
  id : Int
  text : String
  wrapped : Int
  chapters : Array[Chapter]
  heads : Array[Int]
  md : Array[Json]
}

///|
/// What the viewer asks of the page (ViewerHost).
pub(all) struct ViewerHost {
  narrow : () -> Bool
  /// a link in a text's Markdown opened
  on_link : (String) -> Unit
  /// how the reader lays text out on this device, and one of it changed
  reader_style : () -> ReaderStyle
  set_reader_style : (ReaderStyleChange) -> Unit
  /// a text (a file decoded) as a reader shows it, read by the page's core (`reader.book`); its second: a Markdown file's
  read_book : (String, Bool, (Result[ReadBook, String]) -> Unit) -> Unit
  /// where words are in a book the core read (`reader.search`)
  search_book : (Int, String, (Array[Int]) -> Unit) -> Unit
}

///|
/// The layout kept here while no page keeps it.
// kept across runs: the default host's own, put back by viewer_reset
let style_here : Ref[ReaderStyle] = Ref(reader_style_default)

///|
/// The host with none told.
fn viewer_host_default() -> ViewerHost {
  {
    narrow: fn() { false },
    on_link: fn(_) {  },
    reader_style: fn() { style_here.val },
    set_reader_style: fn(change) { style_here.val = style_here.val.changed(change) },
    // (no core: the text as it is, nothing found in it)
    read_book: fn(text, _, done) { done(Ok({ id: 0, text, wrapped: 0, chapters: [], heads: [], md: [] })) },
    search_book: fn(_, _, done) { done([]) },
  }
}

///|
// kept across runs: what the app says once as it starts (set_viewer_host), the same for every run of it
let host_told : Ref[ViewerHost?] = Ref(None)

///|
/// What the page gives its viewers, from now on (setViewerHost).
pub fn set_viewer_host(given : ViewerHost) -> Unit {
  host_told.val = Some(given)
}

///|
/// What the page gives (viewerHost).
pub fn viewer_host() -> ViewerHost {
  match host_told.val {
    Some(h) => h
    None => viewer_host_default()
  }
}

///|
/// Every viewer's state let go of: the texts read, the films played, the layout kept here (the app begun again: a
/// test's reset).
pub fn viewer_reset() -> Unit {
  readings_reset()
  players_reset()
  style_here.val = reader_style_default
}
