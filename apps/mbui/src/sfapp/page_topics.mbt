// What a page has read of the core, let go of with the page (Compose lets go of a page's rememberTopic as the page
// leaves the composition): each topic a page of the stack reads (through the source page_view gives it, its rows
// built later as the list is laid out too) is that page's; a page left, the topics it read that no page still in the
// stack has read are unsubscribed. What is read over the pages is the app's. A page that forgot one kept it followed at the core for the app's life: a chat's
// `chatJobs` kept its thread's window as first read, and the chat opened again where it was first opened.

///|
/// A page's topics read since it was opened, by their name and params.
priv struct PageTopics {
  page : Page
  read : Map[String, (String, Map[String, Json])]
}

///|
let page_topics : Array[PageTopics] = []

///|
/// The topics read over the pages (the app's: the bar, a sheet, a desktop's frame…), never let go of with a page.
let app_topics : Map[String, Bool] = {}

///|
/// The source as the app was given it this frame: what the pages read through (page_src), so that what they read is
/// theirs, not the app's too.
let page_raw : Ref[Source?] = Ref::new(None)

///|
/// As the app's state was before it ever ran (app.mbt reset).
fn page_topics_reset() -> Unit {
  page_topics.clear()
  app_topics.clear()
  page_raw.val = None
}

///|
fn topic_key(name : String, params : Map[String, Json]) -> String {
  name + "\u{1}" + Json::object(params).stringify()
}

///|
fn page_topics_of(p : Page) -> Map[String, (String, Map[String, Json])] {
  for e in page_topics {
    if e.page == p {
      return e.read
    }
  }
  let read = {}
  page_topics.push({ page: p, read })
  read
}

///|
/// `src` whose topics are kept by `owner` (a page; None: the app's, what is read over the pages (the bar, a sheet,
/// the preview, a desktop's frame), kept as long as the app runs), and whose topics let go of explicitly (a chat left,
/// a row's read ahead let go) are no page's any more.
fn page_tracked(src : Source, owner? : Page? = None) -> Source {
  {
    ..src,
    topic: fn(name, params) {
      match owner {
        Some(p) => page_topics_of(p)[topic_key(name, params)] = (name, params)
        None => app_topics[topic_key(name, params)] = true
      }
      (src.topic)(name, params)
    },
    leave: fn(name, params) {
      let k = topic_key(name, params)
      for e in page_topics {
        e.read.remove(k)
      }
      app_topics.remove(k)
      (src.leave)(name, params)
    },
  }
}

///|
/// What page `page` reads through (page_view): its own.
fn page_src(src : Source, page : Page) -> Source {
  page_tracked(page_raw.val.unwrap_or(src), owner=Some(page))
}

///|
/// Page `p` left: the topics it read that no page still in the stack has read, unsubscribed (after what it let go of
/// itself: pages_left).
fn page_topics_left(src : Source, p : Page) -> Unit {
  // (the same page again in the stack: still its; the bar's places, switched among in place, keep theirs, coming back
  // to one as it was left rather than read anew)
  if app.nav.pages().contains(p) || p is (Home | Place(_) | Files | Decisions) {
    return
  }
  let mut at = -1
  for i, e in page_topics {
    if e.page == p {
      at = i
    }
  }
  if at < 0 {
    return
  }
  let gone = page_topics.remove(at)
  // (those of pages no longer in the stack whose leaving is still to be told count as theirs till then)
  let others = page_topics.filter(fn(e) { app.nav.pages().contains(e.page) || left_pages.contains(e.page) })
  let leave = []
  gone.read.each(fn(k, t) {
    if !app_topics.contains(k) && !others.iter().any(fn(e) { e.read.contains(k) }) {
      leave.push(t)
    }
  })
  for t in leave {
    (src.leave)(t.0, t.1)
  }
}
