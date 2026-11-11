// TEMP scratch (never committed): each frame in zz_window, every row of each chat list (key, top, height, how open)
// and the list's causes; and the words the gaps judge reads

///|
pub let zz_window : Ref[(Double, Double)] = Ref::new((-1.0, -1.0))

///|
fn zz_in(now : Double) -> Bool {
  now >= zz_window.val.0 && now <= zz_window.val.1
}

///|
fn Ctx::zz_rows(self : Ctx, now : Double, ln : Node, st : ListState, keys : Array[String]) -> Unit {
  guard zz_in(now) && st.named.has_prefix("chat") else { return }
  let rows : Array[String] = []
  let mut q = ln.first
  while q >= 0 {
    let n = self.nodes[q]
    let k = if n.item >= 0 && n.item < keys.length() { keys[n.item] } else { "#\{n.item}" }
    let op = match st.causes {
      Some(c) =>
        match c.opened.get(k) {
          Some((s, nat)) => "~\{s}/\{nat}"
          None => ""
        }
      None => ""
    }
    rows.push("\{k}@\{n.y - ln.y}+\{n.fh}\{op}")
    q = n.next
  }
  let cs = match st.causes {
    Some(c) => {
      let a : Array[String] = []
      c.by.each(fn(k, cm) {
        a.push(
          k + "=" +
          (match cm.0 {
            Comes(t) => "comes@\{t}"
            Goes(t) => "goes@\{t}"
            Changed(t) => "changed@\{t}"
          }) +
          "/\{cm.1}",
        )
      })
      "[" + a.join(" ") + "] way \{c.start}-\{c.end} inplace=\{c.in_place.iter().collect()} own=\{c.own.iter().collect()}"
    }
    None => "none"
  }
  println("ZZR \{now} vp=\{st.vp_h} \{rows.join(" ")}")
  println("ZZC \{now} \{cs}")
}

///|
fn zz_words(now : Double, lines : Array[(String, Double, Double, Double, Double, Double)]) -> Unit {
  guard zz_in(now) else { return }
  println("ZZW \{now} \{lines.map(fn(w) { "\{w.0}@\{w.2}+\{w.4}" }).join(" | ")}")
}
