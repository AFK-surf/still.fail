// What the files keep as they are left, as a local file browser does, for the app's run (ember web/src/drive/kept.ts;
// not stored): the folder last open in a workspace's files' page (the rail's 文件 comes back to it) and in its chats'
// 文件 tab (the same over each chat, as the tab is kept while chats change beside it). How far each folder was
// scrolled is its list's own (by where it is shown and how: its key). The folders a tree had open, a column's width
// dragged and what was last opened in each folder (chosen when it is shown again) are the core's (`drive.browse`):
// `keep_opened` tells it.

///|
/// The files' page last open, and the 文件 tab's place, by workspace (a tab's: None, the places).
priv struct Kept {
  pages : Map[String, DriveAt]
  tabs : Map[String, DriveAt?]
}

///|
let kept : Kept = { pages: {}, tabs: {} }

///|
fn kept_reset() -> Unit {
  kept.pages.clear()
  kept.tabs.clear()
}

///|
/// What was opened in the folder at `at` (a folder gone into, a file), by its name: chosen as it is shown again.
pub fn keep_opened(c : @ui.Ctx, src : Source, owner : String, at : DriveAt, name : String) -> Unit {
  c.tell("keep-opened/" + owner, fn() {
    (src.call)(
      "drive.browse",
      {
        "act": "opened",
        "owner": Json::string(owner),
        "station": Json::string(at.station),
        "root": Json::string(at.root.unwrap_or("")),
        "path": Json::string(at.path),
        "name": Json::string(name),
      },
      fn(_) {  },
    )
  })
}

///|
/// The files' page last open in workspace `ws`.
pub fn last_files_page(ws : String) -> DriveAt? {
  kept.pages.get(ws)
}

///|
pub fn keep_files_page(ws : String, at : DriveAt) -> Unit {
  kept.pages[ws] = at
}

///|
/// Where the chats' 文件 tab was in workspace `ws` (Some(None): the places).
pub fn kept_tab(ws : String) -> DriveAt?? {
  kept.tabs.get(ws)
}

///|
pub fn keep_tab(ws : String, at : DriveAt?) -> Unit {
  kept.tabs[ws] = at
}
