// The agents' memory on a station (settings/Memory.kt; the core's `memory` topic: read each time one of its pages shows
// it, what was read last shown meanwhile, the app opened again too): the global memory by its parts, each project's
// memory (a skill whose description says when it applies), the station's other skills (the built-in ones folded), each
// opening a page of its own to read, Markdown; the memory of every station a row each from settings (MemoriesScreen).
// What 记忆's pages read of it (src/sfpages memory.mbt, memory_doc.mbt, one page each in every frame).

///|
/// A station's memory as the core holds it, and why it could not be read while it holds none.
pub(all) struct MemoryRead {
  value : Json?
  error : String
}

///|
/// A station's memory (the `memory` topic).
pub fn memory_of(core : Core, address : String) -> MemoryRead {
  let topic = (core.topic)("memory", { "station": str(address) })
  {
    value: topic.value,
    error: match topic.error {
      Some(e) => error_text(e)
      None => ""
    },
  }
}

///|
/// The global memory's parts (Memory.kt sectionsOf): by its headings, as the core reads them.
pub fn sections_of(m : Json?) -> Array[(String, String, String)] {
  items(field(m, "global"), "sections").map(fn(x) { (text(Some(x), "title"), text(Some(x), "text"), text(Some(x), "note")) })
}

///|
/// Whose a skill is, after its name (Memory.kt tagOf): another station's, or shared from here.
pub fn skill_tag(k : Json?, names : Map[String, String]) -> String {
  let share = field(k, "share")
  match text(share, "role") {
    "user" => {
      let host = text(share, "host")
      fill("web-main.memory.share.from", [
        (
          "station",
          match names.get(host) {
            Some(n) => n
            None => if host.length() > 8 { host.unsafe_substring(start=0, end=8) } else { host }
          },
        ),
      ])
    }
    "host" => tr("web-main.memory.share.shared")
    _ => ""
  }
}

///|
pub let memory_chevron : Double = 14.0

///|
/// Whether the built-in skills are folded open, by station.
pub let builtin_open : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()
