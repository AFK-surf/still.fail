// The model pick's two levels, shared by the old panel and its retained-node replacement.

///|
priv struct TripleModels {
  options : Array[Json]
  listed : Array[Json]
  near : Array[Json]
  liked : Array[Json]
  kinds : Array[Json]
  kind : String
  kind_open : Bool
  series : Array[(String, Array[Json])]
  searching : Bool
  all : Bool
}

///|
/// Derive the visible models from the pick and the panel's own navigation. The order comes from the core; searching
/// includes model ids as well as the name, and the selected maker falls back to the picked model's or the first.
fn triple_models(v : Json?, query : String, show_all : Bool, chosen_kind : String, sheet : Bool) -> TripleModels {
  let options = items(v, "options")
  let words = query.trim(chars=" ").to_string().to_lower()
  let listed = options.filter(fn(o) {
    let o = Some(o)
    words == "" ||
    text(o, "name").to_lower().contains(words) ||
    text(o, "model").to_lower().contains(words) ||
    items(o, "ids").iter().any(fn(i) { i is String(s) && s.to_lower().contains(words) })
  })
  let model_of = fn(id : Json) -> Json? {
    guard id is String(id) else { return None }
    options.search_by(fn(o) { text(Some(o), "model") == id }).map(fn(i) { options[i] })
  }
  let near = items(v, "near").filter_map(model_of)
  let liked = items(v, "liked").filter_map(model_of)
  let searching = words != ""
  let all = searching || show_all || (near.is_empty() && liked.is_empty())
  let kinds = items(v, "makers")
  let kind_of = fn(o : Json) -> String { text(field(Some(o), "maker"), "id") }
  let kind = if kinds.iter().any(fn(k) { text(Some(k), "id") == chosen_kind }) {
    chosen_kind
  } else {
    match model_of(Json::string(text(v, "option"))) {
      Some(o) if kinds.iter().any(fn(k) { text(Some(k), "id") == kind_of(o) }) => kind_of(o)
      _ => kinds.get(0).map(fn(k) { text(Some(k), "id") }).unwrap_or("")
    }
  }
  let rest = listed.filter(fn(o) { searching || kinds.length() < 2 || kind_of(o) == kind })
  let series : Array[(String, Array[Json])] = []
  for o in rest {
    let who = match text(Some(o), "family") {
      "" => @sf.t("web-main.model.otherSeries")
      f => f
    }
    match series.search_by(fn(s) { s.0 == who }) {
      Some(i) => series[i].1.push(o)
      None => series.push((who, [o]))
    }
  }
  { options, listed, near, liked, kinds, kind, kind_open: !sheet || chosen_kind != "", series, searching, all }
}
