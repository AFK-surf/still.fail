// A subscription's deltas applied as the core applies them (client/core-ts/src/collections.ts `applyKeyed`, which the
// web's and Android's appliers match): `set`, `append` and `remove` at a path; keyed `put`, `patch`, `drop` and
// `move` on a list's item found by its key. Nothing is changed in place: only the arrays and objects along an op's
// path are copied, so a value a view still holds stays as it was, and the parts that did not change are shared.
// An op that does not fit its value (a path through what is not there) is skipped, as the core skips it.

///|
/// `value` with `ops` (a `delta` message's array) applied.
pub fn apply_delta(value : Json, ops : Array[Json]) -> Json {
  let mut v = value
  for op in ops {
    match op {
      Object(o) =>
        match o.get("path") {
          Some(Array(path)) => v = apply_op(v, o, path, 0)
          _ => ()
        }
      _ => ()
    }
  }
  v
}

///|
fn apply_op(
  node : Json,
  op : Map[String, Json],
  path : Array[Json],
  depth : Int,
) -> Json {
  if depth == path.length() {
    if op.contains("key") {
      return match node {
        Array(list) => Json::array(apply_keyed(list, op))
        _ => node
      }
    }
    match op.get("set") {
      Some(v) => return v
      None => ()
    }
    return match (node, op.get("append")) {
      (Array(a), Some(Array(more))) => {
        let c = a.copy()
        for x in more {
          c.push(x)
        }
        Json::array(c)
      }
      _ => node
    }
  }
  let last = depth == path.length() - 1
  match node {
    Array(a) =>
      match index_of(path[depth]) {
        Some(i) if i < a.length() => {
          let c = a.copy()
          c[i] = apply_op(a[i], op, path, depth + 1)
          Json::array(c)
        }
        _ => node
      }
    Object(m) =>
      match path[depth] {
        String(k) =>
          if op.contains("remove") && last {
            let c = m.copy()
            c.remove(k)
            Json::object(c)
          } else if !m.contains(k) && !(op.contains("set") && last) {
            node
          } else {
            let c = m.copy()
            c[k] = apply_op(m.get(k).unwrap_or(Json::null()), op, path, depth + 1)
            Json::object(c)
          }
        _ => node
      }
    _ => node
  }
}

///|
/// A path segment as an array index: a whole number from 0.
fn index_of(seg : Json) -> Int? {
  match seg {
    Number(d, ..) =>
      if d >= 0.0 && d < 2147483647.0 && d == d.floor() {
        Some(d.to_int())
      } else {
        None
      }
    _ => None
  }
}

///|
/// An item's key: the one field's value, or the fields' values in order (a field missing is null).
fn key_of(item : Json, fields : Array[Json]) -> Json {
  let field = fn(f : Json) -> Json {
    match (item, f) {
      (Object(m), String(name)) => m.get(name).unwrap_or(Json::null())
      _ => Json::null()
    }
  }
  if fields.length() == 1 {
    field(fields[0])
  } else {
    Json::array(fields.map(field))
  }
}

///|
fn apply_keyed(list : Array[Json], op : Map[String, Json]) -> Array[Json] {
  let fields = match op.get("key") {
    Some(Array(f)) => f
    _ => return list
  }
  let out = list.copy()
  let find = fn(k : Json) -> Int {
    for i, item in out {
      if key_of(item, fields) == k {
        return i
      }
    }
    -1
  }
  // Before the item keyed `before`; at the end when that is null, absent or not there.
  let place = fn(item : Json, before : Json?) {
    let at = match before {
      None | Some(Null) => -1
      Some(b) => find(b)
    }
    if at < 0 {
      out.push(item)
    } else {
      out.insert(at, item)
    }
  }
  match (op.get("drop"), op.get("patch"), op.get("move")) {
    (Some(k), _, _) => {
      let i = find(k)
      if i >= 0 {
        out.remove(i) |> ignore
      }
    }
    (None, Some(k), _) => {
      let i = find(k)
      match op.get("ops") {
        Some(Array(ops)) if i >= 0 => out[i] = apply_delta(out[i], ops)
        _ => ()
      }
    }
    (None, None, Some(k)) => {
      let i = find(k)
      if i < 0 {
        return list
      }
      let item = out.remove(i)
      place(item, op.get("before"))
    }
    (None, None, None) => {
      let put = match op.get("put") {
        Some(p) => p
        None => return list
      }
      let i = find(key_of(put, fields))
      if i >= 0 && !op.contains("before") {
        out[i] = put
      } else {
        if i >= 0 {
          out.remove(i) |> ignore
        }
        place(put, op.get("before"))
      }
    }
  }
  out
}
