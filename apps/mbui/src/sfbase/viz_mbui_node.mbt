// Declarative mbui native widget & Wasm mini-program renderer (.mbui / .wasm -> @view.View / @ui.Ctx).
//
// Maps declarative `.mbui` JSON widgets and sandboxed `.wasm` mini-programs directly to native
// `@view.View` and `@ui.Ctx` nodes, `@signals.Signal[Json]` reactive state, `@sf` components, and
// native chart/SVG primitives (`viz_chart_node.mbt`), eliminating `NativeView::page` WebView overhead.

///|
pub struct VizMbuiWidget {
  title : String
  subtitle : String
  init_state : Map[String, Json]
  root : Json
  wasm_bytes : Bytes?
  gas_limit : Int
}

///|
priv struct VizMbuiStore {
  key : String
  signals : Map[String, @signals.Signal[Json]]
  mut synced_raw : Json
  mut wasm : VizWasmInstance?
  gas_limit : Int
  root_sig : @signals.Signal[Json]
  title_sig : @signals.Signal[String]
  subtitle_sig : @signals.Signal[String]
  tree_ver : @signals.Signal[Int]
  wasm_error : @signals.Signal[String]
}

///|
// kept across runs: cleared in viz_pages_reset()
let viz_mbui_stores : Array[VizMbuiStore] = []

///|
pub fn viz_mbui_states_clear() -> Unit {
  viz_mbui_stores.clear()
}

///|
pub fn is_mbui_viz(name : String) -> Bool {
  let s = @sf.lower(name)
  s.has_suffix(".mbui") || s.has_suffix(".wasm")
}

///|
// kept across runs: a value (no field of it changes)
let viz_zero_len : @ui.Len = viz_fixed_len(0.0)

///|
// kept across runs: a value (no field of it changes)
let viz_dot_len : @ui.Len = viz_fixed_len(8.0)

///|
// kept across runs: a value (no field of it changes)
let viz_root_col : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let viz_card_box : @ui.Style = @ui.css("w=Full p=S3 gap=S2 radius=Xl bg=Card")

///|
// kept across runs: a value (no field of it changes)
let viz_stat_box : @ui.Style = @ui.css("w=Full p=S3 gap=S1 radius=Xl bg=Card")

///|
// kept across runs: a value (no field of it changes)
let viz_flow_node_box : @ui.Style = @ui.css("px=S2_5 py=S2 gap=S0_5 radius=Lg bg=Card")

///|
// kept across runs: a value (no field of it changes)
let viz_code_box : @ui.Style = @ui.css("w=Full p=S2_5 gap=S1 radius=Lg bg=Card")

///|
// kept across runs: a value (no field of it changes)
let viz_table_box : @ui.Style = @ui.css("w=Full py=S1 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let viz_divider_line : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
// kept across runs: a value (no field of it changes)
let viz_row_wrap_s2 : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let viz_row_s1_5 : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let viz_row_end_s1 : @ui.Style = @ui.css("row gap=S1 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let viz_good : @ui.TextStyle = @ui.text_style(color=Positive)

///|
// kept across runs: a value (no field of it changes)
let viz_stat_val : @ui.TextStyle = @sf.title.then(@ui.text_style(wrap=false))

///|
// kept across runs: a value (no field of it changes)
let viz_stat_unit : @ui.TextStyle = @sf.caption.then(@ui.text_style(wrap=false))

///|
fn viz_parse_num(s : String, fallback : Double) -> Double {
  match (try Some(@json.parse(s.trim().to_owned())) catch { _ => None }) {
    Some(Number(n, ..)) => n
    _ => fallback
  }
}

///|
fn viz_json_str(obj : Map[String, Json], key : String, fallback : String) -> String {
  match obj.get(key) {
    Some(String(s)) => s
    Some(Number(n, ..)) => viz_fmt_num(n, "")
    Some(True) => "true"
    Some(False) => "false"
    _ => fallback
  }
}

///|
fn viz_json_num(obj : Map[String, Json], key : String, fallback : Double) -> Double {
  match obj.get(key) {
    Some(Number(n, ..)) => n
    Some(String(s)) => viz_parse_num(s, fallback)
    _ => fallback
  }
}

///|
fn viz_json_int(obj : Map[String, Json], key : String, fallback : Int) -> Int {
  viz_json_num(obj, key, fallback.to_double()).to_int()
}

///|
fn viz_json_bool(obj : Map[String, Json], key : String, fallback : Bool) -> Bool {
  match obj.get(key) {
    Some(True) => true
    Some(False) => false
    Some(Number(n, ..)) => n != 0.0
    Some(String(s)) => s == "true" || s == "1"
    _ => fallback
  }
}

///|
fn viz_json_arr(obj : Map[String, Json], key : String) -> Array[Json] {
  match obj.get(key) {
    Some(Array(a)) => a
    _ => []
  }
}

///|
fn viz_json_str_arr(obj : Map[String, Json], key : String) -> Array[String] {
  let out : Array[String] = []
  for item in viz_json_arr(obj, key) {
    match item {
      String(s) => out.push(s)
      Number(n, ..) => out.push(viz_fmt_num(n, ""))
      True => out.push("true")
      False => out.push("false")
      _ => ()
    }
  }
  out
}

///|
fn viz_json_num_arr(obj : Map[String, Json], key : String) -> Array[Double] {
  let out : Array[Double] = []
  for item in viz_json_arr(obj, key) {
    match item {
      Number(n, ..) => out.push(n)
      String(s) => out.push(viz_parse_num(s, 0.0))
      _ => ()
    }
  }
  out
}

///|
pub fn viz_mbui_parse_bytes(name : String, bytes : Bytes) -> VizMbuiWidget? {
  if is_wasm_bytes(bytes) {
    let fallback_title = if name.has_suffix(".wasm") {
      name.unsafe_substring(start=0, end=name.length() - 5)
    } else {
      name
    }
    return Some({
      title: fallback_title,
      subtitle: "",
      init_state: Map([]),
      root: Json::object(Map([])),
      wasm_bytes: Some(bytes),
      gas_limit: viz_wasm_default_gas,
    })
  }
  viz_mbui_parse(name, @utf8.decode_lossy(bytes))
}

///|
pub fn viz_mbui_parse(name : String, raw : String) -> VizMbuiWidget? {
  let trimmed = raw.trim().to_owned()
  if trimmed.has_prefix("wasm:base64:") {
    let b64 = trimmed.unsafe_substring(start=12, end=trimmed.length())
    match viz_base64_decode(b64) {
      Some(bytes) if is_wasm_bytes(bytes) => return viz_mbui_parse_bytes(name, bytes)
      _ => return None
    }
  }
  let raw_bytes = @utf8.encode(raw)
  if is_wasm_bytes(raw_bytes) {
    return viz_mbui_parse_bytes(name, raw_bytes)
  }
  if @sf.lower(name).has_suffix(".wasm") && !trimmed.has_prefix("{") {
    match viz_base64_decode(trimmed) {
      Some(bytes) if is_wasm_bytes(bytes) => return viz_mbui_parse_bytes(name, bytes)
      _ => ()
    }
    match viz_hex_decode(trimmed) {
      Some(bytes) if is_wasm_bytes(bytes) => return viz_mbui_parse_bytes(name, bytes)
      _ => ()
    }
  }
  if !is_mbui_viz(name) && !trimmed.has_prefix("{") {
    return None
  }
  let parsed : Json = @json.parse(raw) catch { _ => return None }
  match parsed {
    Object(obj) => {
      let is_widget = is_mbui_viz(name) ||
        obj.contains("mbui") ||
        obj.contains("wasm") ||
        obj.contains("wasm_base64") ||
        obj.contains("wasm_hex") ||
        obj.contains("body") ||
        obj.contains("root") ||
        obj.contains("children") ||
        obj.contains("type") ||
        obj.contains("kind") ||
        obj.contains("chart")
      if !is_widget {
        return None
      }
      let title = viz_json_str(obj, "title", "")
      let subtitle = viz_json_str(obj, "subtitle", "")
      let init_state : Map[String, Json] = Map([])
      match obj.get("state") {
        Some(Object(st)) =>
          for k, v in st {
            init_state[k] = v
          }
        _ => ()
      }
      let wasm_b64 = viz_json_str(
        obj,
        "wasm",
        viz_json_str(obj, "wasm_base64", viz_json_str(obj, "wasmBase64", "")),
      )
      let wasm_hex = viz_json_str(obj, "wasm_hex", viz_json_str(obj, "wasmHex", ""))
      let wasm_bytes : Bytes? = if wasm_b64 != "" {
        match viz_base64_decode(wasm_b64) {
          Some(b) if is_wasm_bytes(b) => Some(b)
          _ => None
        }
      } else if wasm_hex != "" {
        match viz_hex_decode(wasm_hex) {
          Some(b) if is_wasm_bytes(b) => Some(b)
          _ => None
        }
      } else {
        None
      }
      let gas_limit = viz_json_int(obj, "gas_limit", viz_wasm_default_gas).clamp(
        min=1_000,
        max=10_000_000,
      )
      let root = match obj.get("root") {
        Some(r) => r
        None =>
          match obj.get("body") {
            Some(b) => b
            None => parsed
          }
      }
      Some({ title, subtitle, init_state, root, wasm_bytes, gas_limit })
    }
    _ => None
  }
}

///|
fn viz_extract_state_map(raw : Json) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  match raw {
    Object(obj) => {
      match obj.get("modelContent") {
        Some(Object(mc)) =>
          for k, v in mc {
            out[k] = v
          }
        _ => ()
      }
      match obj.get("privateContent") {
        Some(Object(pc)) =>
          for k, v in pc {
            out[k] = v
          }
        _ => ()
      }
      for k, v in obj {
        if k != "modelContent" && k != "privateContent" {
          out[k] = v
        }
      }
    }
    _ => ()
  }
  out
}

///|
fn viz_sync_state_to_wasm(store : VizMbuiStore, inst : VizWasmInstance) -> Unit {
  for k, sig in store.signals {
    let v = sig.untracked()
    inst.host.state_map[k] = v
    let iv : Int? = match v {
      Number(n, ..) => Some(n.to_int())
      True => Some(1)
      False => Some(0)
      _ => None
    }
    match iv {
      Some(num) => {
        let _ = viz_wasm_set_global_i64(inst, k, num.to_int64() & 0xffffffffL)
        if viz_wasm_has_export(inst, "set_" + k) {
          let _ = viz_wasm_call(
            inst,
            "set_" + k,
            [num.to_int64() & 0xffffffffL],
            gas_limit=store.gas_limit,
          )
        }
      }
      None => ()
    }
  }
}

///|
fn viz_apply_wasm_json_output(
  store : VizMbuiStore,
  hears : VizHears?,
  json_str : String,
) -> Unit {
  let parsed : Json = @json.parse(json_str) catch { _ => return }
  match parsed {
    Object(obj) => {
      match obj.get("title") {
        Some(String(t)) if obj.contains("root") || obj.contains("body") =>
          store.title_sig.set(t)
        _ => ()
      }
      match obj.get("subtitle") {
        Some(String(sub)) if obj.contains("root") || obj.contains("body") =>
          store.subtitle_sig.set(sub)
        _ => ()
      }
      match obj.get("state") {
        Some(Object(st)) =>
          for k, v in st {
            let sig = viz_state_sig(store, k, v)
            sig.set(v)
            match store.wasm {
              Some(inst) => inst.host.state_map[k] = v
              None => ()
            }
          }
        _ => ()
      }
      match obj.get("follow_up") {
        Some(String(p)) if p.trim() != "" =>
          match store.wasm {
            Some(inst) => inst.host.follow_up_draft = Some(p.trim().to_owned())
            None => ()
          }
        _ => ()
      }
      let has_tree_fields = obj.contains("root") ||
        obj.contains("body") ||
        obj.contains("type") ||
        obj.contains("kind") ||
        obj.contains("children") ||
        obj.contains("chart")
      if has_tree_fields {
        let next_root = match obj.get("root") {
          Some(r) => r
          None =>
            match obj.get("body") {
              Some(b) => b
              None => parsed
            }
        }
        if store.root_sig.untracked() != next_root {
          store.root_sig.set(next_root)
          store.tree_ver.set(store.tree_ver.untracked() + 1)
        }
      } else if !obj.contains("state") && !obj.contains("follow_up") {
        for k, v in obj {
          let sig = viz_state_sig(store, k, v)
          sig.set(v)
        }
      }
    }
    _ => ()
  }
  ignore(hears)
}

///|
fn viz_sync_from_wasm(
  store : VizMbuiStore,
  inst : VizWasmInstance,
  ret_vals : Array[Int64],
  hears : VizHears?,
) -> Unit {
  match viz_wasm_extract_string(inst, ret_vals) {
    Ok(Some(s)) => viz_apply_wasm_json_output(store, hears, s)
    Ok(None) => ()
    Err(e) => store.wasm_error.set(e)
  }
  if inst.host.out_state is None && viz_wasm_has_export(inst, "mbui_state") {
    match viz_wasm_call(inst, "mbui_state", [], gas_limit=store.gas_limit) {
      Ok(st_ret) =>
        match viz_wasm_extract_string(inst, st_ret) {
          Ok(Some(st_str)) => {
            let parsed : Json = @json.parse(st_str) catch { _ => Json::null() }
            match parsed {
              Object(m) =>
                for k, v in m {
                  let sig = viz_state_sig(store, k, v)
                  sig.set(v)
                  inst.host.state_map[k] = v
                }
              _ => ()
            }
          }
          _ => ()
        }
      Err(_) => ()
    }
  }
  match inst.host.out_state {
    Some(Object(m)) => {
      inst.host.out_state = None
      for k, v in m {
        let sig = viz_state_sig(store, k, v)
        sig.set(v)
      }
    }
    Some(_) => inst.host.out_state = None
    None => ()
  }
  if inst.host.state_dirty {
    inst.host.state_dirty = false
    for k, v in inst.host.state_map {
      let sig = viz_state_sig(store, k, v)
      if sig.untracked() != v {
        sig.set(v)
      }
    }
  }
  for k, sig in store.signals {
    if viz_wasm_has_export(inst, "get_" + k) {
      match viz_wasm_call(inst, "get_" + k, [], gas_limit=store.gas_limit) {
        Ok(vals) if vals.length() > 0 => {
          let cur = sig.untracked()
          let next_v = match cur {
            True | False => Json::boolean(vals[0].to_int() != 0)
            _ => Json::number(vals[0].to_int().to_double())
          }
          if cur != next_v {
            sig.set(next_v)
            inst.host.state_map[k] = next_v
          }
        }
        _ => ()
      }
    } else {
      match viz_wasm_get_global_i64(inst, k) {
        Some(gv) => {
          let cur = sig.untracked()
          let next_v = match cur {
            True | False => Json::boolean(gv.to_int() != 0)
            _ => Json::number(gv.to_int().to_double())
          }
          if cur != next_v {
            sig.set(next_v)
            inst.host.state_map[k] = next_v
          }
        }
        None => ()
      }
    }
  }
  match inst.host.follow_up_draft {
    Some(draft) => {
      inst.host.follow_up_draft = None
      match hears {
        Some(h) => {
          let cut = if draft.length() > 4000 { draft.clamped_view(end=4000).to_owned() } else { draft }
          let took = match h.follow_up {
            Some(f) => f(cut)
            None => false
          }
          toast_later(viz_tr(if took { "android-misc.viz.followupDrafted" } else { "android-misc.viz.cantSend" }))
        }
        None => ()
      }
    }
    None => ()
  }
}

///|
fn viz_notify_wasm_event(
  store : VizMbuiStore,
  hears : VizHears,
  ev_json : Json,
) -> Unit {
  match store.wasm {
    Some(inst) => {
      viz_sync_state_to_wasm(store, inst)
      let ev_bytes = @utf8.encode(ev_json.stringify())
      let (ptr, len) = match viz_wasm_pass_input(inst, ev_bytes, gas_limit=store.gas_limit) {
        Ok(pair) => pair
        Err(e) => {
          store.wasm_error.set(e)
          return
        }
      }
      if viz_wasm_has_export(inst, "mbui_event") {
        let n_params = viz_wasm_func_param_count(inst, "mbui_event")
        let call_args : Array[Int64] = if n_params >= 2 {
          [ptr.to_int64() & 0xffffffffL, len.to_int64() & 0xffffffffL]
        } else if n_params == 1 {
          [ptr.to_int64() & 0xffffffffL]
        } else {
          []
        }
        match viz_wasm_call(inst, "mbui_event", call_args, gas_limit=store.gas_limit) {
          Ok(ret) => {
            store.wasm_error.set("")
            viz_sync_from_wasm(store, inst, ret, Some(hears))
          }
          Err(e) => store.wasm_error.set(e)
        }
      } else if viz_wasm_has_export(inst, "mbui_update") {
        match viz_wasm_call(inst, "mbui_update", [], gas_limit=store.gas_limit) {
          Ok(ret) => {
            store.wasm_error.set("")
            viz_sync_from_wasm(store, inst, ret, Some(hears))
          }
          Err(e) => store.wasm_error.set(e)
        }
      }
      if viz_wasm_has_export(inst, "mbui_render") && !viz_wasm_has_export(inst, "mbui_event") {
        match viz_wasm_call(inst, "mbui_render", [], gas_limit=store.gas_limit) {
          Ok(ret) => viz_sync_from_wasm(store, inst, ret, Some(hears))
          Err(e) => store.wasm_error.set(e)
        }
      }
    }
    None => ()
  }
}

///|
fn viz_store_of(
  key : String,
  widget : VizMbuiWidget,
  external_state : Json,
) -> VizMbuiStore {
  for s in viz_mbui_stores {
    if s.key == key {
      if s.synced_raw != external_state {
        s.synced_raw = external_state
        let ext = viz_extract_state_map(external_state)
        for k, v in ext {
          match s.signals.get(k) {
            Some(sig) => sig.set(v)
            None => s.signals[k] = @signals.signal(v)
          }
        }
        match s.wasm {
          Some(inst) => {
            viz_sync_state_to_wasm(s, inst)
            if viz_wasm_has_export(inst, "mbui_update") {
              match viz_wasm_call(inst, "mbui_update", [], gas_limit=s.gas_limit) {
                Ok(ret) => viz_sync_from_wasm(s, inst, ret, None)
                Err(e) => s.wasm_error.set(e)
              }
            }
          }
          None => ()
        }
      }
      return s
    }
  }
  let merged_state : Map[String, Json] = Map([])
  let signals : Map[String, @signals.Signal[Json]] = Map([])
  for k, v in widget.init_state {
    merged_state[k] = v
    signals[k] = @signals.signal(v)
  }
  let ext = viz_extract_state_map(external_state)
  for k, v in ext {
    merged_state[k] = v
    signals[k] = @signals.signal(v)
  }
  let store : VizMbuiStore = {
    key,
    signals,
    synced_raw: external_state,
    wasm: None,
    gas_limit: widget.gas_limit,
    root_sig: @signals.signal(widget.root),
    title_sig: @signals.signal(widget.title),
    subtitle_sig: @signals.signal(widget.subtitle),
    tree_ver: @signals.signal(0),
    wasm_error: @signals.signal(""),
  }
  match widget.wasm_bytes {
    Some(bytes) =>
      match viz_wasm_instantiate(bytes, merged_state) {
        Ok(inst) => {
          store.wasm = Some(inst)
          viz_sync_state_to_wasm(store, inst)
          if viz_wasm_has_export(inst, "mbui_init") {
            let init_json = Json::object(merged_state).stringify()
            let (ptr, len) = match viz_wasm_pass_input(inst, @utf8.encode(init_json), gas_limit=store.gas_limit) {
              Ok(p) => p
              Err(_) => (0, 0)
            }
            let n_params = viz_wasm_func_param_count(inst, "mbui_init")
            let args : Array[Int64] = if n_params >= 2 {
              [ptr.to_int64() & 0xffffffffL, len.to_int64() & 0xffffffffL]
            } else if n_params == 1 {
              [ptr.to_int64() & 0xffffffffL]
            } else {
              []
            }
            match viz_wasm_call(inst, "mbui_init", args, gas_limit=store.gas_limit) {
              Ok(ret) => viz_sync_from_wasm(store, inst, ret, None)
              Err(e) => store.wasm_error.set(e)
            }
          }
          if viz_wasm_has_export(inst, "mbui_update") {
            match viz_wasm_call(inst, "mbui_update", [], gas_limit=store.gas_limit) {
              Ok(ret) => viz_sync_from_wasm(store, inst, ret, None)
              Err(e) => store.wasm_error.set(e)
            }
          }
          if viz_wasm_has_export(inst, "mbui_render") {
            match viz_wasm_call(inst, "mbui_render", [], gas_limit=store.gas_limit) {
              Ok(ret) => viz_sync_from_wasm(store, inst, ret, None)
              Err(e) => store.wasm_error.set(e)
            }
          }
        }
        Err(e) => store.wasm_error.set(e)
      }
    None => ()
  }
  viz_mbui_stores.push(store)
  store
}

///|
fn viz_state_sig(
  store : VizMbuiStore,
  key : String,
  fallback : Json,
) -> @signals.Signal[Json] {
  match store.signals.get(key) {
    Some(sig) => sig
    None => {
      let sig = @signals.signal(fallback)
      store.signals[key] = sig
      sig
    }
  }
}

///|
fn viz_state_get(store : VizMbuiStore, key : String) -> Json {
  match store.signals.get(key) {
    Some(sig) => sig.get()
    None => Json::null()
  }
}

///|
fn viz_state_snapshot(store : VizMbuiStore) -> Json {
  let obj : Map[String, Json] = Map([])
  for k, sig in store.signals {
    obj[k] = sig.untracked()
  }
  Json::object(obj)
}

///|
fn viz_state_set(
  store : VizMbuiStore,
  hears : VizHears,
  key : String,
  val : Json,
) -> Unit {
  let sig = viz_state_sig(store, key, val)
  sig.set(val)
  let ev_map : Map[String, Json] = Map([
    ("type", Json::string("change")),
    ("key", Json::string(key)),
    ("value", val),
  ])
  viz_notify_wasm_event(store, hears, Json::object(ev_map))
  let snap = viz_state_snapshot(store)
  store.synced_raw = snap
  match hears.keep {
    Some(keep) => keep(snap)
    None => ()
  }
}

///|
fn viz_json_val_str(v : Json) -> String {
  match v {
    String(s) => s
    Number(n, ..) => viz_fmt_num(n, "")
    True => "true"
    False => "false"
    Null => ""
    _ => v.stringify()
  }
}

///|
fn viz_json_truthy(v : Json) -> Bool {
  match v {
    True => true
    False | Null => false
    Number(n, ..) => n != 0.0
    String(s) => s != "" && s != "false" && s != "0"
    Array(a) => a.length() > 0
    Object(o) => o.length() > 0
  }
}

///|
fn viz_interp(store : VizMbuiStore, template : String) -> String {
  if !template.contains("{") {
    return template
  }
  let chars = template.to_array()
  let n = chars.length()
  let buf = StringBuilder()
  let mut i = 0
  while i < n {
    let ch = chars[i]
    if ch == '$' && i + 1 < n && chars[i + 1] == '{' {
      let mut j = i + 2
      while j < n && chars[j] != '}' {
        j = j + 1
      }
      if j < n {
        let key = String::from_array(chars[i + 2:j])
        buf.write_string(viz_json_val_str(viz_state_get(store, key)))
        i = j + 1
        continue
      }
    } else if ch == '{' {
      let mut j = i + 1
      while j < n && chars[j] != '}' && chars[j] != ' ' && chars[j] != '\n' {
        j = j + 1
      }
      if j < n && chars[j] == '}' && j > i + 1 {
        let key = String::from_array(chars[i + 1:j])
        buf.write_string(viz_json_val_str(viz_state_get(store, key)))
        i = j + 1
        continue
      }
    }
    buf.write_char(ch)
    i = i + 1
  }
  buf.to_string()
}

///|
fn viz_eval_cond(store : VizMbuiStore, cond : Json?) -> Bool {
  match cond {
    None | Some(Null) => true
    Some(True) => true
    Some(False) => false
    Some(String(expr)) => {
      let s = expr.trim().to_owned()
      if s == "" || s == "true" {
        return true
      }
      if s == "false" {
        return false
      }
      if s.has_prefix("!") {
        let key = s.unsafe_substring(start=1, end=s.length()).trim().to_owned()
        return !viz_json_truthy(viz_state_get(store, key))
      }
      match s.find("!=") {
        Some(idx) => {
          let lhs = s.unsafe_substring(start=0, end=idx).trim().to_owned()
          let rhs = s.unsafe_substring(start=idx + 2, end=s.length()).trim().to_owned()
          return viz_json_val_str(viz_state_get(store, lhs)) != rhs
        }
        None => ()
      }
      match s.find("==") {
        Some(idx) => {
          let lhs = s.unsafe_substring(start=0, end=idx).trim().to_owned()
          let rhs = s.unsafe_substring(start=idx + 2, end=s.length()).trim().to_owned()
          return viz_json_val_str(viz_state_get(store, lhs)) == rhs
        }
        None => ()
      }
      match s.find("=") {
        Some(idx) => {
          let lhs = s.unsafe_substring(start=0, end=idx).trim().to_owned()
          let rhs = s.unsafe_substring(start=idx + 1, end=s.length()).trim().to_owned()
          return viz_json_val_str(viz_state_get(store, lhs)) == rhs
        }
        None => ()
      }
      viz_json_truthy(viz_state_get(store, s))
    }
    Some(Object(obj)) => {
      let key = viz_json_str(obj, "key", viz_json_str(obj, "state", ""))
      if key == "" {
        return true
      }
      let cur = viz_state_get(store, key)
      match obj.get("eq") {
        Some(eq_val) => viz_json_val_str(cur) == viz_json_val_str(eq_val)
        None =>
          match obj.get("ne") {
            Some(ne_val) => viz_json_val_str(cur) != viz_json_val_str(ne_val)
            None => viz_json_truthy(cur)
          }
      }
    }
    Some(other) => viz_json_truthy(other)
  }
}

///|
fn viz_run_action_map(
  store : VizMbuiStore,
  hears : VizHears,
  obj : Map[String, Json],
) -> Unit {
  let mut mutated = false
  match obj.get("set") {
    Some(Object(pairs)) => {
      mutated = true
      for k, v in pairs {
        let sig = viz_state_sig(store, k, v)
        sig.set(v)
      }
    }
    _ => ()
  }
  match obj.get("inc") {
    Some(Object(pairs)) => {
      mutated = true
      for k, delta_json in pairs {
        let delta = match delta_json {
          Number(n, ..) => n
          _ => 1.0
        }
        let cur = match viz_state_get(store, k) {
          Number(n, ..) => n
          String(s) => viz_parse_num(s, 0.0)
          _ => 0.0
        }
        let next = Json::number(cur + delta)
        let sig = viz_state_sig(store, k, next)
        sig.set(next)
      }
    }
    Some(String(inc_key)) if inc_key != "" => {
      mutated = true
      let delta = viz_json_num(obj, "by", 1.0)
      let cur = match viz_state_get(store, inc_key) {
        Number(n, ..) => n
        String(s) => viz_parse_num(s, 0.0)
        _ => 0.0
      }
      let next = Json::number(cur + delta)
      let sig = viz_state_sig(store, inc_key, next)
      sig.set(next)
    }
    _ => ()
  }
  let state_key = viz_json_str(
    obj,
    "state_key",
    viz_json_str(obj, "bind", viz_json_str(obj, "key", "")),
  )
  if state_key != "" {
    match obj.get("value") {
      Some(v) => {
        mutated = true
        let sig = viz_state_sig(store, state_key, v)
        sig.set(v)
      }
      None => ()
    }
  }
  let toggle_key = viz_json_str(obj, "toggle", "")
  if toggle_key != "" {
    mutated = true
    let cur = viz_json_truthy(viz_state_get(store, toggle_key))
    let sig = viz_state_sig(store, toggle_key, Json::boolean(!cur))
    sig.set(Json::boolean(!cur))
  }
  let wasm_fn = viz_json_str(
    obj,
    "wasm_call",
    viz_json_str(obj, "wasmCall", viz_json_str(obj, "call", "")),
  )
  if wasm_fn != "" {
    match store.wasm {
      Some(inst) => {
        mutated = true
        viz_sync_state_to_wasm(store, inst)
        let call_args : Array[Int64] = []
        for item in viz_json_arr(obj, "args") {
          match item {
            Number(n, ..) => call_args.push(n.to_int().to_int64() & 0xffffffffL)
            True => call_args.push(1L)
            False => call_args.push(0L)
            String(s) => {
              let resolved = viz_interp(store, s)
              call_args.push(viz_parse_num(resolved, 0.0).to_int().to_int64() & 0xffffffffL)
            }
            _ => ()
          }
        }
        match viz_wasm_call(inst, wasm_fn, call_args, gas_limit=store.gas_limit) {
          Ok(ret) => {
            store.wasm_error.set("")
            let into_key = viz_json_str(obj, "into", viz_json_str(obj, "result_key", ""))
            if into_key != "" && ret.length() > 0 {
              let v = Json::number(ret[0].to_int().to_double())
              let sig = viz_state_sig(store, into_key, v)
              sig.set(v)
              inst.host.state_map[into_key] = v
            }
            viz_sync_from_wasm(store, inst, ret, Some(hears))
          }
          Err(e) => store.wasm_error.set(e)
        }
      }
      None => ()
    }
  }
  let ev_id = viz_json_str(obj, "id", viz_json_str(obj, "event", ""))
  let has_sub_action = match obj.get("action") {
    Some(Object(_)) => true
    _ => false
  }
  if mutated || ev_id != "" || (store.wasm is Some(_) && !has_sub_action) {
    if wasm_fn == "" {
      let ev_map : Map[String, Json] = Map([
        ("type", Json::string(if ev_id != "" { ev_id } else { "action" })),
        ("id", Json::string(ev_id)),
        ("label", Json::string(viz_json_str(obj, "label", viz_json_str(obj, "text", "")))),
      ])
      if state_key != "" {
        ev_map["key"] = Json::string(state_key)
        ev_map["value"] = viz_state_get(store, state_key)
      }
      viz_notify_wasm_event(store, hears, Json::object(ev_map))
    }
    let snap = viz_state_snapshot(store)
    store.synced_raw = snap
    match hears.keep {
      Some(keep) => keep(snap)
      None => ()
    }
  }
  let act_kind = @sf.lower(viz_json_str(obj, "kind", viz_json_str(obj, "type", "")))
  let prompt_raw = viz_json_str(
    obj,
    "follow_up",
    viz_json_str(
      obj,
      "followUp",
      viz_json_str(
        obj,
        "prompt",
        if act_kind == "follow_up" || act_kind == "followup" {
          viz_json_str(obj, "text", "")
        } else {
          ""
        },
      ),
    ),
  )
  if prompt_raw != "" {
    let prompt = viz_interp(store, prompt_raw).trim().to_owned()
    if prompt != "" {
      let cut = if prompt.length() > 4000 { prompt.clamped_view(end=4000).to_owned() } else { prompt }
      let took = match hears.follow_up {
        Some(f) => f(cut)
        None => false
      }
      toast_later(viz_tr(if took { "android-misc.viz.followupDrafted" } else { "android-misc.viz.cantSend" }))
    }
  }
}

///|
fn viz_run_action(
  store : VizMbuiStore,
  hears : VizHears,
  obj : Map[String, Json],
) -> Unit {
  viz_run_action_map(store, hears, obj)
  match obj.get("action") {
    Some(Object(act)) => viz_run_action_map(store, hears, act)
    _ => ()
  }
}

///|
fn viz_pill_tone(tone : String) -> @sf.PillTone {
  match @sf.lower(tone) {
    "accent" | "orange" | "brand" | "primary" => Accented
    "ok" | "success" | "green" | "positive" => Green
    "warn" | "warning" | "amber" | "yellow" => Amber
    "bad" | "danger" | "error" | "red" => Red
    "info" | "blue" => Blue
    _ => Neutral
  }
}

///|
fn viz_btn_tone(tone : String) -> @sf.Tone {
  match @sf.lower(tone) {
    "primary" | "accent" | "brand" => Primary
    "danger" | "bad" | "error" | "red" => Danger
    "ghost" | "quiet" | "subtle" => Ghost
    _ => Plain
  }
}

///|
fn viz_text_style_of(obj : Map[String, Json]) -> @ui.TextStyle {
  let kind = @sf.lower(viz_json_str(obj, "type", viz_json_str(obj, "kind", "")))
  let size = if kind == "h1" {
    "h1"
  } else if kind == "h2" {
    "h2"
  } else if viz_json_bool(obj, "mono", false) {
    "mono"
  } else if viz_json_bool(obj, "small", false) {
    "small"
  } else {
    @sf.lower(viz_json_str(obj, "size", "body"))
  }
  let base = match size {
    "title" | "h1" | "xl" => @sf.title
    "h2" | "lg" | "heading" => @sf.card_title.then(@sf.strong)
    "card_title" | "h3" | "md" => @sf.card_title
    "caption" | "sm" | "small" => @sf.caption
    "meta" | "xs" | "tiny" => @sf.meta
    "mono" | "code" => @sf.code
    _ => @sf.body
  }
  let weighted = if viz_json_bool(obj, "bold", false) ||
    viz_json_str(obj, "weight", "") == "bold" ||
    viz_json_str(obj, "weight", "") == "semibold" {
    base.then(@sf.strong)
  } else {
    base
  }
  let tone = if viz_json_bool(obj, "muted", false) {
    "muted"
  } else {
    @sf.lower(viz_json_str(obj, "tone", viz_json_str(obj, "color", "")))
  }
  match tone {
    "muted" | "secondary" | "subtle" => weighted.then(@sf.quiet)
    "ok" | "success" | "green" | "positive" => weighted.then(viz_good)
    "warn" | "warning" | "amber" | "yellow" => weighted.then(@sf.lacking)
    "bad" | "danger" | "error" | "red" => weighted.then(@sf.bad)
    "accent" | "orange" | "brand" | "primary" => weighted.then(@sf.accent)
    _ => weighted
  }
}

///|
fn viz_align_of(s : String) -> @ui.Align {
  match @sf.lower(s) {
    "center" | "middle" => ACenter
    "end" | "bottom" | "right" => AEnd
    "stretch" | "fill" => AStretch
    _ => AStart
  }
}

///|
fn viz_justify_of(s : String) -> @ui.Justify {
  match @sf.lower(s) {
    "center" | "middle" => JCenter
    "end" | "right" => JEnd
    "between" | "space-between" => JBetween
    _ => JStart
  }
}

///|
fn viz_children_of(obj : Map[String, Json]) -> Array[Json] {
  match obj.get("body") {
    Some(Array(a)) => if a.length() > 0 { return a }
    Some(Object(_) as o) => return [o]
    _ => ()
  }
  match obj.get("children") {
    Some(Array(a)) => if a.length() > 0 { return a }
    Some(Object(_) as o) => return [o]
    _ => ()
  }
  let it = viz_json_arr(obj, "items")
  if it.length() > 0 {
    return it
  }
  viz_json_arr(obj, "options")
}

///|
fn viz_chart_of(store : VizMbuiStore, obj : Map[String, Json]) -> VizChart {
  let kind = viz_json_str(obj, "chart", viz_json_str(obj, "kind", "bar"))
  let title = viz_interp(store, viz_json_str(obj, "title", ""))
  let subtitle = viz_interp(store, viz_json_str(obj, "subtitle", ""))
  let center = viz_interp(
    store,
    viz_json_str(obj, "center", viz_json_str(obj, "center_value", "")),
  )
  let labels = viz_json_str_arr(obj, "labels")
  let values = viz_json_num_arr(obj, "values")
  let series : Array[VizSeries] = []
  for item in viz_json_arr(obj, "series") {
    match item {
      Object(sobj) => {
        let name = viz_interp(
          store,
          viz_json_str(sobj, "name", viz_json_str(sobj, "label", "")),
        )
        let vals = viz_json_num_arr(sobj, "values")
        let color = viz_json_str(sobj, "tone", viz_json_str(sobj, "color", ""))
        for pt in viz_json_arr(sobj, "points") {
          match pt {
            Array(pair) =>
              if pair.length() >= 2 {
                let y = match pair[1] {
                  Number(n, ..) => n
                  _ => 0.0
                }
                vals.push(y)
              }
            Object(pobj) => {
              let y = viz_json_num(pobj, "y", 0.0)
              vals.push(y)
            }
            _ => ()
          }
        }
        series.push({ name, values: vals, color })
      }
      _ => ()
    }
  }
  if series.length() == 0 && values.length() > 0 {
    series.push({
      name: viz_interp(store, viz_json_str(obj, "label", "")),
      values,
      color: viz_json_str(obj, "tone", viz_json_str(obj, "color", "")),
    })
  }
  let items : Array[VizHBarItem] = []
  let slices : Array[VizPieSlice] = []
  for item in viz_json_arr(obj, "items") {
    match item {
      Object(iobj) => {
        let label = viz_interp(
          store,
          viz_json_str(iobj, "label", viz_json_str(iobj, "name", "")),
        )
        let value = viz_json_num(iobj, "value", 0.0)
        let color = viz_json_str(iobj, "tone", viz_json_str(iobj, "color", ""))
        let text = viz_interp(
          store,
          viz_json_str(iobj, "note", viz_json_str(iobj, "text", "")),
        )
        items.push({ label, value, text, color })
        slices.push({ label, value, color })
      }
      _ => ()
    }
  }
  if items.length() == 0 && labels.length() > 0 && values.length() > 0 {
    let n = if labels.length() < values.length() { labels.length() } else { values.length() }
    for i = 0; i < n; i = i + 1 {
      items.push({ label: labels[i], value: values[i], text: "", color: "" })
      slices.push({ label: labels[i], value: values[i], color: "" })
    }
  }
  let min = match obj.get("min") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let max = match obj.get("max") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let reference = match obj.get("reference") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  let reference_label = viz_interp(store, viz_json_str(obj, "reference_label", ""))
  let unit = viz_interp(store, viz_json_str(obj, "unit", ""))
  let height = viz_json_num(obj, "height", 180.0)
  let stacked = viz_json_bool(obj, "stacked", false)
  let show_legend = viz_json_bool(
    obj,
    "legend",
    series.length() > 1 || slices.length() > 0,
  )
  let show_grid = viz_json_bool(obj, "grid", true)
  {
    kind,
    title,
    subtitle,
    center,
    labels,
    series,
    items,
    slices,
    min,
    max,
    unit,
    height,
    stacked,
    show_legend,
    show_grid,
    reference,
    reference_label,
  }
}

///|
fn viz_parse_viewbox(vb : String, fallback_w : Double, fallback_h : Double) -> (Double, Double) {
  let parts : Array[Double] = []
  for piece in vb.split(" ") {
    let s = piece.trim().to_owned()
    if s != "" {
      parts.push(viz_parse_num(s, 0.0))
    }
  }
  if parts.length() >= 4 && parts[2] > 1.0 && parts[3] > 1.0 {
    (parts[2], parts[3])
  } else {
    (fallback_w, fallback_h)
  }
}

///|
fn viz_prepare_svg(raw : String, w : Double, h : Double) -> String {
  let p = @sf.theme().p
  let s = raw
    .replace_all(old="var(--primary)", new=viz_svg_hex(p.text))
    .replace_all(old="var(--foreground)", new=viz_svg_hex(p.text))
    .replace_all(old="var(--muted-foreground)", new=viz_svg_hex(p.muted))
    .replace_all(old="var(--border)", new=viz_svg_hex(p.line_strong))
    .replace_all(old="var(--card)", new=viz_svg_hex(p.card))
    .replace_all(old="var(--green)", new=viz_svg_hex(p.green))
    .replace_all(old="var(--green-bg)", new=viz_svg_hex(p.green_bg))
    .replace_all(old="var(--red)", new=viz_svg_hex(p.red))
    .replace_all(old="var(--red-bg)", new=viz_svg_hex(p.red_bg))
    .replace_all(old="var(--yellow)", new=viz_svg_hex(p.warn_ink))
    .replace_all(old="var(--amber)", new=viz_svg_hex(p.warn_ink))
    .replace_all(old="var(--blue)", new=viz_svg_hex(p.blue))
    .replace_all(old="var(--blue-bg)", new=viz_svg_hex(p.blue_bg))
    .replace_all(old="var(--purple)", new=viz_svg_hex(@sf.usage_series(4)))
    .replace_all(old="var(--orange)", new=viz_svg_hex(p.accent))
  if s.trim().has_prefix("<svg") {
    s
  } else {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \{w.to_int()} \{h.to_int()}\">" + s + "</svg>"
  }
}

///|
fn viz_render_node(
  parent : @view.View,
  store : VizMbuiStore,
  hears : VizHears,
  node : Json,
  path : String,
  depth : Int,
  in_row? : Bool = false,
) -> Unit {
  if depth > 24 {
    return
  }
  match node {
    String(s) =>
      parent.box(fn(w) {
        @sf.style_node(w, fn() { @ui.style() }, in_row~)
        @sf.words_node(w, fn() { viz_interp(store, s) }, fn() { @sf.body }) |> ignore
      })
      |> ignore
    Array(items) =>
      parent.box(fn(col) {
        @sf.style_node(col, fn() { viz_col_s2 }, in_row~)
        for i = 0; i < items.length(); i = i + 1 {
          viz_render_node(col, store, hears, items[i], path + "/a\{i}", depth + 1)
        }
      })
      |> ignore
    Object(obj) => {
      if obj.contains("when") || obj.contains("if") {
        let cond_json = match obj.get("when") {
          Some(w) => Some(w)
          None => obj.get("if")
        }
        let stripped : Map[String, Json] = Map([])
        for k, v in obj {
          if k != "when" && k != "if" {
            stripped[k] = v
          }
        }
        parent.show(
          fn() { viz_eval_cond(store, cond_json) },
          fn(s) {
            @sf.style_node(s, fn() { @ui.style(w=Full) }, in_row~)
            viz_render_node(s, store, hears, Json::object(stripped), path + "/w", depth + 1)
          },
        )
        return
      }
      let kind = @sf.lower(
        viz_json_str(
          obj,
          "type",
          viz_json_str(obj, "kind", if obj.contains("chart") { "chart" } else { "col" }),
        ),
      )
      match kind {
        "show" => {
          let cond_json = match obj.get("cond") {
            Some(c) => Some(c)
            None => obj.get("when")
          }
          let children = viz_children_of(obj)
          let gap = viz_json_num(obj, "gap", 8.0)
          parent.show(
            fn() { viz_eval_cond(store, cond_json) },
            fn(s) {
              @sf.style_node(s, fn() { @ui.style(w=Full, gap=@sf.room_of(gap)) }, in_row~)
              for i = 0; i < children.length(); i = i + 1 {
                viz_render_node(s, store, hears, children[i], path + "/s\{i}", depth + 1)
              }
            },
          )
        }
        "col" | "column" | "widget" | "stack" | "vstack" => {
          let gap = viz_json_num(obj, "gap", 10.0)
          let align = viz_align_of(viz_json_str(obj, "align", "stretch"))
          let children = viz_children_of(obj)
          parent.box(fn(col) {
            @sf.style_node(
              col,
              fn() { @ui.style(w=Full, gap=@sf.room_of(gap), align~) },
              in_row~,
            )
            for i = 0; i < children.length(); i = i + 1 {
              viz_render_node(col, store, hears, children[i], path + "/c\{i}", depth + 1)
            }
          })
          |> ignore
        }
        "row" | "controls" | "hstack" => {
          let gap = viz_json_num(obj, "gap", 8.0)
          let wrap = viz_json_bool(obj, "wrap", !in_row)
          let align = viz_align_of(viz_json_str(obj, "align", "center"))
          let justify = viz_justify_of(viz_json_str(obj, "justify", "start"))
          let row_w : @ui.Len = if in_row { Hug } else { Full }
          let children = viz_children_of(obj)
          parent.box(fn(r) {
            if wrap {
              r.wraps(Is(Some(0.0))) |> ignore
            }
            @sf.style_node(
              r,
              fn() { @ui.style(row=true, w=row_w, gap=@sf.room_of(gap), align~, justify~) },
              in_row~,
            )
            for i = 0; i < children.length(); i = i + 1 {
              viz_render_node(r, store, hears, children[i], path + "/r\{i}", depth + 1, in_row=true)
            }
          })
          |> ignore
        }
        "grid" => {
          let cols = viz_json_int(obj, "cols", 2).clamp(min=1, max=4)
          let gap = viz_json_num(obj, "gap", 10.0)
          let children = viz_children_of(obj)
          parent.box(fn(grid_col) {
            @sf.style_node(grid_col, fn() { @ui.style(w=Full, gap=@sf.room_of(gap)) }, in_row~)
            let mut idx = 0
            while idx < children.length() {
              let row_start = idx
              let row_end = if idx + cols < children.length() { idx + cols } else { children.length() }
              grid_col.box(fn(r) {
                @sf.style_node(r, fn() { @ui.style(row=true, w=Full, gap=@sf.room_of(gap), align=AStretch) })
                for c_idx = row_start; c_idx < row_end; c_idx = c_idx + 1 {
                  let child = children[c_idx]
                  let ci = c_idx
                  r.box(fn(cell) {
                    @sf.style_node(cell, fn() { @ui.style(w=@sf.grow, min_w=viz_zero_len) }, in_row=true)
                    viz_render_node(cell, store, hears, child, path + "/g\{ci}", depth + 1)
                  })
                  |> ignore
                }
              })
              |> ignore
              idx = row_end
            }
          })
          |> ignore
        }
        "card" => {
          let title = viz_json_str(obj, "title", "")
          let subtitle = viz_json_str(obj, "subtitle", "")
          let badge = viz_json_str(obj, "badge", "")
          let badge_tone = viz_json_str(obj, "badge_tone", viz_json_str(obj, "tone", ""))
          let children = viz_children_of(obj)
          parent.box(fn(card) {
            @sf.style_node(card, fn() { viz_card_box }, in_row~)
            if title != "" || subtitle != "" || badge != "" {
              card.box(fn(head) {
                @sf.style_node(head, fn() { viz_row_between_s2 })
                head.box(fn(titles) {
                  @sf.style_node(titles, fn() { viz_col_s0_5 }, in_row=true)
                  if title != "" {
                    titles.box(fn(w) {
                      @sf.words_node(w, fn() { viz_interp(store, title) }, fn() { @sf.card_title }) |> ignore
                    })
                    |> ignore
                  }
                  if subtitle != "" {
                    titles.box(fn(w) {
                      @sf.words_node(w, fn() { viz_interp(store, subtitle) }, fn() { @sf.caption }) |> ignore
                    })
                    |> ignore
                  }
                })
                |> ignore
                if badge != "" {
                  @sf.pill_node(head, fn() { viz_interp(store, badge) }, tone=viz_pill_tone(badge_tone)) |> ignore
                }
              })
              |> ignore
            }
            for i = 0; i < children.length(); i = i + 1 {
              viz_render_node(card, store, hears, children[i], path + "/cd\{i}", depth + 1)
            }
          })
          |> ignore
        }
        "stat" | "metric" | "kpi" => {
          let label = viz_json_str(obj, "label", viz_json_str(obj, "title", ""))
          let val_raw = viz_json_str(obj, "value", "")
          let unit = viz_json_str(obj, "unit", "")
          let delta = viz_json_str(obj, "delta", viz_json_str(obj, "note", ""))
          let tone = viz_json_str(obj, "tone", "")
          let spark = viz_json_num_arr(obj, "spark")
          parent.box(fn(card) {
            @sf.style_node(card, fn() { viz_stat_box }, in_row~)
            if label != "" {
              card.box(fn(w) {
                @sf.words_node(w, fn() { viz_interp(store, label) }, fn() { @sf.caption }) |> ignore
              })
              |> ignore
            }
            card.box(fn(val_row) {
              @sf.style_node(val_row, fn() { viz_row_end_s1 })
              val_row.box(fn(w) {
                @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                @sf.words_node(w, fn() { viz_interp(store, val_raw) }, fn() { viz_stat_val }) |> ignore
              })
              |> ignore
              if unit != "" {
                val_row.box(fn(w) {
                  @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                  @sf.words_node(w, fn() { viz_interp(store, unit) }, fn() { viz_stat_unit }) |> ignore
                })
                |> ignore
              }
            })
            |> ignore
            if delta != "" || spark.length() >= 2 {
              let delta_style = match @sf.lower(tone) {
                "green" | "ok" | "good" | "success" => @sf.caption.then(viz_good)
                "red" | "bad" | "danger" | "error" => @sf.caption.then(@sf.bad)
                "yellow" | "amber" | "warn" | "warning" => @sf.caption.then(@sf.lacking)
                _ => @sf.caption
              }
              card.box(fn(foot_row) {
                @sf.style_node(foot_row, fn() { viz_row_between_s2 })
                if delta != "" {
                  foot_row.box(fn(w) {
                    @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                    @sf.words_node(w, fn() { viz_interp(store, delta) }, fn() { delta_style }) |> ignore
                  })
                  |> ignore
                }
                if spark.length() >= 2 {
                  viz_spark_node(foot_row, path + "/spark", fn() { spark }, tone, 36.0, 16.0, in_row=true)
                }
              })
              |> ignore
            }
          })
          |> ignore
        }
        "text" | "p" | "h1" | "h2" | "h3" | "label" => {
          let raw = viz_json_str(obj, "text", viz_json_str(obj, "value", viz_json_str(obj, "label", "")))
          let st = viz_text_style_of(obj)
          parent.box(fn(w) {
            @sf.style_node(w, fn() { @ui.style() }, in_row~)
            @sf.words_node(w, fn() { viz_interp(store, raw) }, fn() { st }) |> ignore
          })
          |> ignore
        }
        "badge" | "pill" => {
          let raw = viz_json_str(obj, "text", viz_json_str(obj, "label", ""))
          let tone = viz_pill_tone(viz_json_str(obj, "tone", viz_json_str(obj, "color", "")))
          if in_row {
            @sf.pill_node(parent, fn() { viz_interp(store, raw) }, tone~) |> ignore
          } else {
            parent.box(fn(pr) {
              @sf.style_node(pr, fn() { viz_row_s1_5 })
              @sf.pill_node(pr, fn() { viz_interp(store, raw) }, tone~) |> ignore
            })
            |> ignore
          }
        }
        "dot" | "status" => {
          let raw = viz_json_str(obj, "text", viz_json_str(obj, "label", ""))
          let tone = viz_json_str(obj, "tone", viz_json_str(obj, "color", "green"))
          let dot_idx = 0
          parent.box(fn(r) {
            @sf.style_node(r, fn() { viz_row_s1_5 }, in_row~)
            r.box(fn(dot) {
              @sf.style_node(
                dot,
                fn() {
                  let dc = viz_tone_color(tone, dot_idx)
                  @ui.style(w=viz_dot_len, h=viz_dot_len, radius=Full, bg=Data(dc))
                },
                in_row=true,
              )
            })
            |> ignore
            if raw != "" {
              r.box(fn(w) {
                @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                @sf.words_node(w, fn() { viz_interp(store, raw) }, fn() { @sf.body }) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
        "callout" | "alert" | "banner" => {
          let title = viz_json_str(obj, "title", "")
          let text = viz_json_str(obj, "text", viz_json_str(obj, "body", ""))
          let tone = viz_json_str(obj, "tone", "blue")
          let title_style = match @sf.lower(tone) {
            "green" | "ok" | "good" => @sf.card_title.then(viz_good)
            "red" | "bad" | "danger" => @sf.card_title.then(@sf.bad)
            "yellow" | "amber" | "warn" => @sf.card_title.then(@sf.lacking)
            _ => @sf.card_title
          }
          parent.box(fn(b) {
            @sf.style_node(b, fn() { viz_card_box }, in_row~)
            if title != "" {
              b.box(fn(w) {
                @sf.words_node(w, fn() { viz_interp(store, title) }, fn() { title_style }) |> ignore
              })
              |> ignore
            }
            if text != "" {
              b.box(fn(w) {
                @sf.words_node(w, fn() { viz_interp(store, text) }, fn() { @sf.body }) |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
        "code" | "pre" => {
          let text = viz_json_str(obj, "text", viz_json_str(obj, "code", ""))
          parent.box(fn(b) {
            @sf.style_node(b, fn() { viz_code_box }, in_row~)
            b.box(fn(w) {
              @sf.words_node(w, fn() { viz_interp(store, text) }, fn() { @sf.code }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        "kv" | "descriptions" => {
          let items = viz_json_arr(obj, "items")
          parent.box(fn(col) {
            @sf.style_node(col, fn() { viz_col_s1 }, in_row~)
            for item in items {
              match item {
                Object(iobj) => {
                  let k = viz_json_str(iobj, "label", viz_json_str(iobj, "key", ""))
                  let v = viz_json_str(iobj, "value", "")
                  let badge = viz_json_str(iobj, "badge", "")
                  let tone = viz_json_str(iobj, "tone", "")
                  let v_style = if viz_json_bool(iobj, "mono", false) {
                    @sf.code
                  } else {
                    viz_text_style_of(iobj)
                  }
                  col.box(fn(r) {
                    @sf.style_node(r, fn() { viz_row_between_s2 })
                    r.box(fn(w) {
                      @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                      @sf.words_node(w, fn() { viz_interp(store, k) }, fn() { @sf.caption }) |> ignore
                    })
                    |> ignore
                    if badge != "" {
                      @sf.pill_node(r, fn() { viz_interp(store, badge) }, tone=viz_pill_tone(tone)) |> ignore
                    } else {
                      r.box(fn(w) {
                        @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                        @sf.words_node(w, fn() { viz_interp(store, v) }, fn() { v_style }) |> ignore
                      })
                      |> ignore
                    }
                  })
                  |> ignore
                }
                _ => ()
              }
            }
          })
          |> ignore
        }
        "table" => {
          let cols = {
            let c = viz_json_str_arr(obj, "columns")
            if c.length() > 0 { c } else { viz_json_str_arr(obj, "headers") }
          }
          let rows = viz_json_arr(obj, "rows")
          parent.box(fn(tbl) {
            @sf.style_node(tbl, fn() { viz_table_box }, in_row~)
            if cols.length() > 0 {
              tbl.box(fn(head) {
                @sf.style_node(head, fn() { viz_row_between_s2 })
                for col_name in cols {
                  let cn = col_name
                  head.box(fn(cell) {
                    @sf.style_node(cell, fn() { @ui.style(w=@sf.grow, min_w=viz_zero_len) }, in_row=true)
                    @sf.words_node(cell, fn() { viz_interp(store, cn) }, fn() { @sf.caption.then(@sf.strong) }) |> ignore
                  })
                  |> ignore
                }
              })
              |> ignore
              tbl.box(fn(d) { @sf.style_node(d, fn() { viz_divider_line }) }) |> ignore
            }
            for r_idx = 0; r_idx < rows.length(); r_idx = r_idx + 1 {
              match rows[r_idx] {
                Array(cells) =>
                  tbl.box(fn(r) {
                    @sf.style_node(r, fn() { viz_row_between_s2 })
                    for c_idx = 0; c_idx < cells.length(); c_idx = c_idx + 1 {
                      let cell_json = cells[c_idx]
                      let cell_path = path + "/t\{r_idx}_\{c_idx}"
                      r.box(fn(cell) {
                        @sf.style_node(cell, fn() { @ui.style(w=@sf.grow, min_w=viz_zero_len) }, in_row=true)
                        match cell_json {
                          Object(cobj) => {
                            let c_kind = @sf.lower(viz_json_str(cobj, "type", viz_json_str(cobj, "kind", "")))
                            if cobj.contains("badge") || c_kind == "badge" || c_kind == "pill" {
                              let b_txt = viz_json_str(
                                cobj,
                                "badge",
                                viz_json_str(cobj, "text", viz_json_str(cobj, "label", "")),
                              )
                              let b_tone = viz_pill_tone(viz_json_str(cobj, "tone", ""))
                              cell.box(fn(pr) {
                                @sf.style_node(pr, fn() { viz_row_s1_5 })
                                @sf.pill_node(pr, fn() { viz_interp(store, b_txt) }, tone=b_tone) |> ignore
                              })
                              |> ignore
                            } else if cobj.contains("spark") {
                              let sp = viz_json_num_arr(cobj, "spark")
                              let sp_tone = viz_json_str(cobj, "tone", "")
                              viz_spark_node(cell, cell_path, fn() { sp }, sp_tone, 72.0, 20.0)
                            } else {
                              let txt = viz_json_str(cobj, "text", viz_json_str(cobj, "value", viz_json_str(cobj, "label", "")))
                              let st = viz_text_style_of(cobj)
                              @sf.words_node(cell, fn() { viz_interp(store, txt) }, fn() { st }) |> ignore
                            }
                          }
                          _ => {
                            let txt = viz_json_val_str(cell_json)
                            @sf.words_node(cell, fn() { viz_interp(store, txt) }, fn() { @sf.body }) |> ignore
                          }
                        }
                      })
                      |> ignore
                    }
                  })
                  |> ignore
                _ => ()
              }
            }
          })
          |> ignore
        }
        "flow" | "steps" | "pipeline" => {
          let nodes = {
            let n = viz_json_arr(obj, "nodes")
            if n.length() > 0 { n } else { viz_children_of(obj) }
          }
          parent.box(fn(row) {
            row.wraps(Is(Some(0.0))) |> ignore
            @sf.style_node(row, fn() { viz_row_wrap_s2 }, in_row~)
            for i = 0; i < nodes.length(); i = i + 1 {
              if i > 0 {
                row.box(fn(arr) {
                  @sf.style_node(arr, fn() { @ui.style() }, in_row=true)
                  @sf.words_node(arr, fn() { "→" }, fn() { @sf.caption }) |> ignore
                })
                |> ignore
              }
              match nodes[i] {
                Object(nobj) => {
                  let title = viz_json_str(nobj, "title", viz_json_str(nobj, "label", ""))
                  let body = viz_json_str(
                    nobj,
                    "body",
                    viz_json_str(nobj, "note", viz_json_str(nobj, "sub", viz_json_str(nobj, "subtitle", ""))),
                  )
                  let badge = viz_json_str(nobj, "badge", "")
                  let tone = viz_json_str(nobj, "tone", "")
                  let title_style = match @sf.lower(tone) {
                    "green" | "ok" | "good" => @sf.body.then(@sf.strong).then(viz_good)
                    "red" | "bad" | "danger" => @sf.body.then(@sf.strong).then(@sf.bad)
                    "yellow" | "amber" | "warn" => @sf.body.then(@sf.strong).then(@sf.lacking)
                    _ => @sf.body.then(@sf.strong)
                  }
                  row.box(fn(nb) {
                    @sf.style_node(nb, fn() { viz_flow_node_box }, in_row=true)
                    if title != "" {
                      nb.box(fn(w) {
                        @sf.words_node(w, fn() { viz_interp(store, title) }, fn() { title_style }) |> ignore
                      })
                      |> ignore
                    }
                    if body != "" {
                      nb.box(fn(w) {
                        @sf.words_node(w, fn() { viz_interp(store, body) }, fn() { @sf.caption }) |> ignore
                      })
                      |> ignore
                    }
                    if badge != "" {
                      nb.box(fn(pr) {
                        @sf.style_node(pr, fn() { viz_row_s1_5 })
                        @sf.pill_node(pr, fn() { viz_interp(store, badge) }, tone=viz_pill_tone(tone)) |> ignore
                      })
                      |> ignore
                    }
                  })
                  |> ignore
                }
                _ => ()
              }
            }
          })
          |> ignore
        }
        "progress" => {
          let label = viz_json_str(obj, "label", viz_json_str(obj, "title", ""))
          let val_raw = viz_json_str(obj, "value", "0")
          let max_raw = viz_json_str(obj, "max", "100")
          let tone = viz_json_str(obj, "tone", "")
          let val_txt_raw = viz_json_str(obj, "value_text", "")
          let calc_frac = fn() -> Double {
            let v = viz_parse_num(viz_interp(store, val_raw), 0.0)
            let m = @sf.dmax(1.0, viz_parse_num(viz_interp(store, max_raw), 100.0))
            @sf.dclamp(v / m, 0.0, 1.0)
          }
          let calc_txt = fn() -> String {
            if val_txt_raw != "" {
              viz_interp(store, val_txt_raw)
            } else {
              let v = viz_parse_num(viz_interp(store, val_raw), 0.0)
              let m = @sf.dmax(1.0, viz_parse_num(viz_interp(store, max_raw), 100.0))
              viz_fmt_num(v, "") + " / " + viz_fmt_num(m, "")
            }
          }
          parent.box(fn(col) {
            @sf.style_node(col, fn() { viz_col_s1 }, in_row~)
            if label != "" {
              col.box(fn(r) {
                @sf.style_node(r, fn() { viz_row_between_s2 })
                r.box(fn(w) {
                  @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                  @sf.words_node(w, fn() { viz_interp(store, label) }, fn() { @sf.body }) |> ignore
                })
                |> ignore
                r.box(fn(w) {
                  @sf.style_node(w, fn() { @ui.style() }, in_row=true)
                  @sf.words_node(w, calc_txt, fn() { @sf.code }) |> ignore
                })
                |> ignore
              })
              |> ignore
            }
            col.box(fn(bar) {
              @sf.progress_node(
                bar,
                fn() { Some(calc_frac()) },
                fn() { viz_tone_color(viz_interp(store, tone), 0) },
                fn() { @sf.theme().p.card2 },
              )
              |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        "tabs" => {
          let tab_id = viz_json_str(obj, "id", "tabs_" + path)
          let state_key = viz_json_str(
            obj,
            "state_key",
            viz_json_str(obj, "bind", viz_json_str(obj, "key", "tab:" + tab_id)),
          )
          let raw_items = {
            let it = viz_json_arr(obj, "items")
            if it.length() > 0 { it } else { viz_json_arr(obj, "options") }
          }
          let ids : Array[String] = []
          let labels : Array[String] = []
          let bodies : Array[Array[Json]] = []
          for idx = 0; idx < raw_items.length(); idx = idx + 1 {
            match raw_items[idx] {
              Object(tobj) => {
                let id = viz_json_str(tobj, "id", idx.to_string())
                let lbl = viz_json_str(tobj, "label", viz_json_str(tobj, "title", id))
                ids.push(id)
                labels.push(lbl)
                bodies.push(viz_children_of(tobj))
              }
              _ => ()
            }
          }
          if ids.length() > 0 {
            let def_id = viz_json_str(obj, "active", ids[0])
            let sig = viz_state_sig(store, state_key, Json::string(def_id))
            let active_idx = fn() -> Int {
              let cur = viz_json_val_str(sig.get())
              for i = 0; i < ids.length(); i = i + 1 {
                if ids[i] == cur {
                  return i
                }
              }
              0
            }
            let min_h = viz_json_num(obj, "min_height", viz_json_num(obj, "height", 0.0))
            let tb_style = if min_h > 0.0 {
              viz_col_s2.then(@ui.style(min_h=viz_fixed_len(min_h)))
            } else {
              viz_col_s2
            }
            parent.box(fn(col) {
              @sf.style_node(col, fn() { viz_col_s2_5 }, in_row~)
              @sf.seg_node(
                col,
                fn() { labels.map(fn(l) { viz_interp(store, l) }) },
                active_idx,
                fn(picked) {
                  if picked >= 0 && picked < ids.length() {
                    viz_state_set(store, hears, state_key, Json::string(ids[picked]))
                  }
                },
              )
              |> ignore
              col.pick(
                active_idx,
                fn(panel, tab_idx) {
                  @sf.style_node(panel, fn() { tb_style })
                  if tab_idx >= 0 && tab_idx < bodies.length() {
                    let tab_body = bodies[tab_idx]
                    for j = 0; j < tab_body.length(); j = j + 1 {
                      viz_render_node(panel, store, hears, tab_body[j], path + "/tb\{tab_idx}_\{j}", depth + 1)
                    }
                  }
                },
              )
            })
            |> ignore
          }
        }
        "details" | "collapse" | "accordion" => {
          let det_id = viz_json_str(obj, "id", "det_" + path)
          let state_key = viz_json_str(
            obj,
            "state_key",
            viz_json_str(obj, "bind", viz_json_str(obj, "key", "open:" + det_id)),
          )
          let def_open = viz_json_bool(obj, "open", false)
          let sig = viz_state_sig(store, state_key, Json::boolean(def_open))
          let title = viz_json_str(obj, "title", viz_json_str(obj, "label", "详情"))
          let subtitle = viz_json_str(obj, "subtitle", viz_json_str(obj, "note", ""))
          let children = viz_children_of(obj)
          parent.box(fn(col) {
            @sf.style_node(col, fn() { viz_col_s1_5 }, in_row~)
            @sf.choice_row_node(
              col,
              fn() { viz_interp(store, title) },
              fn() { viz_json_truthy(sig.get()) },
              press=fn() {
                let next = !viz_json_truthy(sig.untracked())
                viz_state_set(store, hears, state_key, Json::boolean(next))
              },
              note=fn() { viz_interp(store, subtitle) },
            )
            col.show(
              fn() { viz_json_truthy(sig.get()) },
              fn(body) {
                @sf.style_node(body, fn() { viz_col_s2 })
                for i = 0; i < children.length(); i = i + 1 {
                  viz_render_node(body, store, hears, children[i], path + "/d\{i}", depth + 1)
                }
              },
            )
          })
          |> ignore
        }
        "switch" | "toggle" | "check" | "checkbox" => {
          let key = viz_json_str(
            obj,
            "key",
            viz_json_str(obj, "state_key", viz_json_str(obj, "bind", "sw_" + path)),
          )
          let def_val = viz_json_bool(obj, "value", viz_json_bool(obj, "checked", false))
          let sig = viz_state_sig(store, key, Json::boolean(def_val))
          let label = viz_json_str(obj, "label", viz_json_str(obj, "title", key))
          let note = viz_json_str(obj, "note", viz_json_str(obj, "subtitle", ""))
          parent.box(fn(b) {
            @sf.style_node(b, fn() { @ui.style(w=Full) }, in_row~)
            @sf.switch_row_node(
              b,
              fn() { viz_interp(store, label) },
              fn() { viz_json_truthy(sig.get()) },
              fn(next) { viz_state_set(store, hears, key, Json::boolean(next)) },
              note=fn() { viz_interp(store, note) },
              in_words=true,
            )
          })
          |> ignore
        }
        "button" | "action" | "btn" => {
          let label = viz_json_str(obj, "label", viz_json_str(obj, "text", "操作"))
          let tone = viz_btn_tone(viz_json_str(obj, "variant", viz_json_str(obj, "tone", "secondary")))
          let icon = viz_json_str(obj, "icon", "")
          @sf.button_node(
            parent,
            fn() { viz_interp(store, label) },
            fn() { viz_run_action(store, hears, obj) },
            tone~,
            icon~,
          )
          |> ignore
        }
        "chart" => {
          let spec = viz_chart_of(store, obj)
          viz_chart_node(parent, path + "/chart", spec, in_row~)
        }
        "spark" | "sparkline" => {
          let vals = viz_json_num_arr(obj, "values")
          let tone = viz_json_str(obj, "tone", viz_json_str(obj, "color", ""))
          let w = viz_json_num(obj, "width", 108.0)
          let h = viz_json_num(obj, "height", 28.0)
          viz_spark_node(parent, path + "/spark", fn() { vals }, tone, w, h, in_row~)
        }
        "svg" => {
          let raw = viz_json_str(obj, "svg", viz_json_str(obj, "xml", ""))
          let w_fallback = viz_json_num(obj, "width", 400.0)
          let h_fallback = viz_json_num(obj, "height", 120.0)
          let (vb_w, vb_h) = viz_parse_viewbox(viz_json_str(obj, "viewBox", ""), w_fallback, h_fallback)
          viz_svg_node(
            parent,
            path + "/svg",
            fn() { (viz_prepare_svg(viz_interp(store, raw), vb_w, vb_h), vb_w, vb_h) },
            in_row~,
          )
        }
        "divider" | "sep" | "hr" =>
          parent.box(fn(d) { @sf.style_node(d, fn() { viz_divider_line }, in_row~) }) |> ignore
        _ => {
          let children = viz_children_of(obj)
          if children.length() > 0 {
            parent.box(fn(col) {
              @sf.style_node(col, fn() { viz_col_s2 }, in_row~)
              for i = 0; i < children.length(); i = i + 1 {
                viz_render_node(col, store, hears, children[i], path + "/u\{i}", depth + 1)
              }
            })
            |> ignore
          }
        }
      }
    }
    _ => ()
  }
}

///|
// kept across runs: a value (no field of it changes)
let viz_col_s2_5 : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let viz_col_s1_5 : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
fn viz_render_ctx(
  c : @ui.Ctx,
  store : VizMbuiStore,
  hears : VizHears,
  node : Json,
  path : String,
  depth : Int,
  in_row? : Bool = false,
) -> Unit {
  if depth > 24 {
    return
  }
  match node {
    String(s) => c.text(viz_interp(store, s), style=@sf.body) |> ignore
    Array(items) =>
      c.box(style=viz_col_s2, fn() {
        for i = 0; i < items.length(); i = i + 1 {
          viz_render_ctx(c, store, hears, items[i], path + "/a\{i}", depth + 1)
        }
      })
      |> ignore
    Object(obj) => {
      if obj.contains("when") || obj.contains("if") {
        let cond_json = match obj.get("when") {
          Some(w) => Some(w)
          None => obj.get("if")
        }
        if !viz_eval_cond(store, cond_json) {
          return
        }
      }
      let kind = @sf.lower(
        viz_json_str(
          obj,
          "type",
          viz_json_str(obj, "kind", if obj.contains("chart") { "chart" } else { "col" }),
        ),
      )
      match kind {
        "show" => {
          let cond_json = match obj.get("cond") {
            Some(cond) => Some(cond)
            None => obj.get("when")
          }
          if viz_eval_cond(store, cond_json) {
            let children = viz_children_of(obj)
            let gap = viz_json_num(obj, "gap", 8.0)
            c.box(style=@ui.style(w=Full, gap=@sf.room_of(gap)), fn() {
              for i = 0; i < children.length(); i = i + 1 {
                viz_render_ctx(c, store, hears, children[i], path + "/s\{i}", depth + 1)
              }
            })
            |> ignore
          }
        }
        "col" | "column" | "widget" | "stack" | "vstack" => {
          let gap = viz_json_num(obj, "gap", 10.0)
          let align = viz_align_of(viz_json_str(obj, "align", "stretch"))
          let children = viz_children_of(obj)
          c.box(style=@ui.style(w=Full, gap=@sf.room_of(gap), align~), fn() {
            for i = 0; i < children.length(); i = i + 1 {
              viz_render_ctx(c, store, hears, children[i], path + "/c\{i}", depth + 1)
            }
          })
          |> ignore
        }
        "row" | "controls" | "hstack" => {
          let gap = viz_json_num(obj, "gap", 8.0)
          let wrap = viz_json_bool(obj, "wrap", !in_row)
          let align = viz_align_of(viz_json_str(obj, "align", "center"))
          let justify = viz_justify_of(viz_json_str(obj, "justify", "start"))
          let row_w : @ui.Len = if in_row { Hug } else { Full }
          let children = viz_children_of(obj)
          c.box(
            style=@ui.style(row=true, w=row_w, gap=@sf.room_of(gap), align~, justify~),
            flow=wrap,
            fn() {
              for i = 0; i < children.length(); i = i + 1 {
                viz_render_ctx(c, store, hears, children[i], path + "/r\{i}", depth + 1, in_row=true)
              }
            },
          )
          |> ignore
        }
        "grid" => {
          let cols = viz_json_int(obj, "cols", 2).clamp(min=1, max=4)
          let gap = viz_json_num(obj, "gap", 10.0)
          let children = viz_children_of(obj)
          c.box(style=@ui.style(w=Full, gap=@sf.room_of(gap)), fn() {
            let mut idx = 0
            while idx < children.length() {
              let row_start = idx
              let row_end = if idx + cols < children.length() { idx + cols } else { children.length() }
              c.box(style=@ui.style(row=true, w=Full, gap=@sf.room_of(gap), align=AStretch), fn() {
                for c_idx = row_start; c_idx < row_end; c_idx = c_idx + 1 {
                  let child = children[c_idx]
                  c.box(style=@ui.style(w=@sf.grow, min_w=viz_zero_len), fn() {
                    viz_render_ctx(c, store, hears, child, path + "/g\{c_idx}", depth + 1)
                  })
                  |> ignore
                }
              })
              |> ignore
              idx = row_end
            }
          })
          |> ignore
        }
        "card" => {
          let title = viz_json_str(obj, "title", "")
          let subtitle = viz_json_str(obj, "subtitle", "")
          let badge = viz_json_str(obj, "badge", "")
          let badge_tone = viz_json_str(obj, "badge_tone", viz_json_str(obj, "tone", ""))
          let children = viz_children_of(obj)
          c.box(style=viz_card_box, fn() {
            if title != "" || subtitle != "" || badge != "" {
              c.box(style=viz_row_between_s2, fn() {
                c.box(style=viz_col_s0_5, fn() {
                  if title != "" {
                    c.text(viz_interp(store, title), style=@sf.card_title) |> ignore
                  }
                  if subtitle != "" {
                    c.text(viz_interp(store, subtitle), style=@sf.caption) |> ignore
                  }
                })
                |> ignore
                if badge != "" {
                  @sf.pill(c, viz_interp(store, badge), tone=viz_pill_tone(badge_tone))
                }
              })
              |> ignore
            }
            for i = 0; i < children.length(); i = i + 1 {
              viz_render_ctx(c, store, hears, children[i], path + "/cd\{i}", depth + 1)
            }
          })
          |> ignore
        }
        "stat" | "metric" | "kpi" => {
          let label = viz_json_str(obj, "label", viz_json_str(obj, "title", ""))
          let val_raw = viz_json_str(obj, "value", "")
          let unit = viz_json_str(obj, "unit", "")
          let delta = viz_json_str(obj, "delta", viz_json_str(obj, "note", ""))
          let tone = viz_json_str(obj, "tone", "")
          let spark = viz_json_num_arr(obj, "spark")
          c.box(style=viz_stat_box, fn() {
            if label != "" {
              c.text(viz_interp(store, label), style=@sf.caption) |> ignore
            }
            c.box(style=viz_row_end_s1, fn() {
              c.text(viz_interp(store, val_raw), style=viz_stat_val) |> ignore
              if unit != "" {
                c.text(viz_interp(store, unit), style=viz_stat_unit) |> ignore
              }
            })
            |> ignore
            if delta != "" || spark.length() >= 2 {
              let delta_style = match @sf.lower(tone) {
                "green" | "ok" | "good" | "success" => @sf.caption.then(viz_good)
                "red" | "bad" | "danger" | "error" => @sf.caption.then(@sf.bad)
                "yellow" | "amber" | "warn" | "warning" => @sf.caption.then(@sf.lacking)
                _ => @sf.caption
              }
              c.box(style=viz_row_between_s2, fn() {
                if delta != "" {
                  c.text(viz_interp(store, delta), style=delta_style) |> ignore
                }
                if spark.length() >= 2 {
                  viz_spark_ctx(c, path + "/spark", spark, tone, 36.0, 16.0)
                }
              })
              |> ignore
            }
          })
          |> ignore
        }
        "text" | "p" | "h1" | "h2" | "h3" | "label" => {
          let raw = viz_json_str(obj, "text", viz_json_str(obj, "value", viz_json_str(obj, "label", "")))
          c.text(viz_interp(store, raw), style=viz_text_style_of(obj)) |> ignore
        }
        "badge" | "pill" => {
          let raw = viz_json_str(obj, "text", viz_json_str(obj, "label", ""))
          let tone = viz_pill_tone(viz_json_str(obj, "tone", viz_json_str(obj, "color", "")))
          @sf.pill(c, viz_interp(store, raw), tone~)
        }
        "dot" | "status" => {
          let raw = viz_json_str(obj, "text", viz_json_str(obj, "label", ""))
          let tone = viz_json_str(obj, "tone", viz_json_str(obj, "color", "green"))
          let dc = viz_tone_color(tone, 0)
          c.box(style=viz_row_s1_5, fn() {
            c.box(
              style=@ui.style(w=viz_dot_len, h=viz_dot_len, radius=Full, bg=Data(dc)),
              fn() {  },
            )
            |> ignore
            if raw != "" {
              c.text(viz_interp(store, raw), style=@sf.body) |> ignore
            }
          })
          |> ignore
        }
        "callout" | "alert" | "banner" => {
          let title = viz_json_str(obj, "title", "")
          let text = viz_json_str(obj, "text", viz_json_str(obj, "body", ""))
          let tone = viz_json_str(obj, "tone", "blue")
          let title_style = match @sf.lower(tone) {
            "green" | "ok" | "good" => @sf.card_title.then(viz_good)
            "red" | "bad" | "danger" => @sf.card_title.then(@sf.bad)
            "yellow" | "amber" | "warn" => @sf.card_title.then(@sf.lacking)
            _ => @sf.card_title
          }
          c.box(style=viz_card_box, fn() {
            if title != "" {
              c.text(viz_interp(store, title), style=title_style) |> ignore
            }
            if text != "" {
              c.text(viz_interp(store, text), style=@sf.body) |> ignore
            }
          })
          |> ignore
        }
        "code" | "pre" => {
          let text = viz_json_str(obj, "text", viz_json_str(obj, "code", ""))
          c.box(style=viz_code_box, fn() {
            c.text(viz_interp(store, text), style=@sf.code) |> ignore
          })
          |> ignore
        }
        "kv" | "descriptions" => {
          let items = viz_json_arr(obj, "items")
          c.box(style=viz_col_s1, fn() {
            for item in items {
              match item {
                Object(iobj) => {
                  let k = viz_json_str(iobj, "label", viz_json_str(iobj, "key", ""))
                  let v = viz_json_str(iobj, "value", "")
                  let badge = viz_json_str(iobj, "badge", "")
                  let tone = viz_json_str(iobj, "tone", "")
                  let v_style = if viz_json_bool(iobj, "mono", false) {
                    @sf.code
                  } else {
                    viz_text_style_of(iobj)
                  }
                  c.box(style=viz_row_between_s2, fn() {
                    c.text(viz_interp(store, k), style=@sf.caption) |> ignore
                    if badge != "" {
                      c.box(style=viz_row_s1_5, fn() {
                        @sf.pill(c, viz_interp(store, badge), tone=viz_pill_tone(tone))
                      })
                      |> ignore
                    } else {
                      c.text(viz_interp(store, v), style=v_style) |> ignore
                    }
                  })
                  |> ignore
                }
                _ => ()
              }
            }
          })
          |> ignore
        }
        "table" => {
          let cols = {
            let cl = viz_json_str_arr(obj, "columns")
            if cl.length() > 0 { cl } else { viz_json_str_arr(obj, "headers") }
          }
          let rows = viz_json_arr(obj, "rows")
          c.box(style=viz_table_box, fn() {
            if cols.length() > 0 {
              c.box(style=viz_row_between_s2, fn() {
                for col_name in cols {
                  c.box(style=@ui.style(w=@sf.grow, min_w=viz_zero_len), fn() {
                    c.text(viz_interp(store, col_name), style=@sf.caption.then(@sf.strong)) |> ignore
                  })
                  |> ignore
                }
              })
              |> ignore
              c.box(style=viz_divider_line, fn() {  }) |> ignore
            }
            for r_idx = 0; r_idx < rows.length(); r_idx = r_idx + 1 {
              match rows[r_idx] {
                Array(cells) =>
                  c.box(style=viz_row_between_s2, fn() {
                    for c_idx = 0; c_idx < cells.length(); c_idx = c_idx + 1 {
                      let cell_json = cells[c_idx]
                      let cell_path = path + "/t\{r_idx}_\{c_idx}"
                      c.box(style=@ui.style(w=@sf.grow, min_w=viz_zero_len), fn() {
                        match cell_json {
                          Object(cobj) => {
                            let c_kind = @sf.lower(viz_json_str(cobj, "type", viz_json_str(cobj, "kind", "")))
                            if cobj.contains("badge") || c_kind == "badge" || c_kind == "pill" {
                              let b_txt = viz_json_str(
                                cobj,
                                "badge",
                                viz_json_str(cobj, "text", viz_json_str(cobj, "label", "")),
                              )
                              let b_tone = viz_pill_tone(viz_json_str(cobj, "tone", ""))
                              c.box(style=viz_row_s1_5, fn() {
                                @sf.pill(c, viz_interp(store, b_txt), tone=b_tone)
                              })
                              |> ignore
                            } else if cobj.contains("spark") {
                              let sp = viz_json_num_arr(cobj, "spark")
                              let sp_tone = viz_json_str(cobj, "tone", "")
                              viz_spark_ctx(c, cell_path, sp, sp_tone, 72.0, 20.0)
                            } else {
                              let txt = viz_json_str(cobj, "text", viz_json_str(cobj, "value", viz_json_str(cobj, "label", "")))
                              c.text(viz_interp(store, txt), style=viz_text_style_of(cobj)) |> ignore
                            }
                          }
                          _ => {
                            let txt = viz_json_val_str(cell_json)
                            c.text(viz_interp(store, txt), style=@sf.body) |> ignore
                          }
                        }
                      })
                      |> ignore
                    }
                  })
                  |> ignore
                _ => ()
              }
            }
          })
          |> ignore
        }
        "flow" | "steps" | "pipeline" => {
          let nodes = {
            let n = viz_json_arr(obj, "nodes")
            if n.length() > 0 { n } else { viz_children_of(obj) }
          }
          c.box(style=viz_row_wrap_s2, flow=true, fn() {
            for i = 0; i < nodes.length(); i = i + 1 {
              if i > 0 {
                c.text("→", style=@sf.caption) |> ignore
              }
              match nodes[i] {
                Object(nobj) => {
                  let title = viz_json_str(nobj, "title", viz_json_str(nobj, "label", ""))
                  let body = viz_json_str(
                    nobj,
                    "body",
                    viz_json_str(nobj, "note", viz_json_str(nobj, "sub", viz_json_str(nobj, "subtitle", ""))),
                  )
                  let badge = viz_json_str(nobj, "badge", "")
                  let tone = viz_json_str(nobj, "tone", "")
                  let title_style = match @sf.lower(tone) {
                    "green" | "ok" | "good" => @sf.body.then(@sf.strong).then(viz_good)
                    "red" | "bad" | "danger" => @sf.body.then(@sf.strong).then(@sf.bad)
                    "yellow" | "amber" | "warn" => @sf.body.then(@sf.strong).then(@sf.lacking)
                    _ => @sf.body.then(@sf.strong)
                  }
                  c.box(style=viz_flow_node_box, fn() {
                    if title != "" {
                      c.text(viz_interp(store, title), style=title_style) |> ignore
                    }
                    if body != "" {
                      c.text(viz_interp(store, body), style=@sf.caption) |> ignore
                    }
                    if badge != "" {
                      c.box(style=viz_row_s1_5, fn() {
                        @sf.pill(c, viz_interp(store, badge), tone=viz_pill_tone(tone))
                      })
                      |> ignore
                    }
                  })
                  |> ignore
                }
                _ => ()
              }
            }
          })
          |> ignore
        }
        "progress" => {
          let label = viz_json_str(obj, "label", viz_json_str(obj, "title", ""))
          let val_raw = viz_json_str(obj, "value", "0")
          let max_raw = viz_json_str(obj, "max", "100")
          let val = viz_parse_num(viz_interp(store, val_raw), 0.0)
          let max_v = @sf.dmax(1.0, viz_parse_num(viz_interp(store, max_raw), 100.0))
          let frac = @sf.dclamp(val / max_v, 0.0, 1.0)
          let tone = viz_interp(store, viz_json_str(obj, "tone", ""))
          let val_txt = viz_json_str(
            obj,
            "value_text",
            viz_fmt_num(val, "") + " / " + viz_fmt_num(max_v, ""),
          )
          c.box(style=viz_col_s1, fn() {
            if label != "" {
              c.box(style=viz_row_between_s2, fn() {
                c.text(viz_interp(store, label), style=@sf.body) |> ignore
                c.text(viz_interp(store, val_txt), style=@sf.code) |> ignore
              })
              |> ignore
            }
            @sf.progress(c, path + "/prog", Some(frac), w=Fill(1.0), color=viz_tone_color(tone, 0))
          })
          |> ignore
        }
        "tabs" => {
          let tab_id = viz_json_str(obj, "id", "tabs_" + path)
          let state_key = viz_json_str(
            obj,
            "state_key",
            viz_json_str(obj, "bind", viz_json_str(obj, "key", "tab:" + tab_id)),
          )
          let raw_items = {
            let it = viz_json_arr(obj, "items")
            if it.length() > 0 { it } else { viz_json_arr(obj, "options") }
          }
          let ids : Array[String] = []
          let labels : Array[String] = []
          let bodies : Array[Array[Json]] = []
          for idx = 0; idx < raw_items.length(); idx = idx + 1 {
            match raw_items[idx] {
              Object(tobj) => {
                let id = viz_json_str(tobj, "id", idx.to_string())
                let lbl = viz_json_str(tobj, "label", viz_json_str(tobj, "title", id))
                ids.push(id)
                labels.push(viz_interp(store, lbl))
                bodies.push(viz_children_of(tobj))
              }
              _ => ()
            }
          }
          if ids.length() > 0 {
            let def_id = viz_json_str(obj, "active", ids[0])
            let sig = viz_state_sig(store, state_key, Json::string(def_id))
            let cur = viz_json_val_str(sig.get())
            let mut active_idx = 0
            for i = 0; i < ids.length(); i = i + 1 {
              if ids[i] == cur {
                active_idx = i
              }
            }
            let min_h = viz_json_num(obj, "min_height", viz_json_num(obj, "height", 0.0))
            let tb_style = if min_h > 0.0 {
              viz_col_s2.then(@ui.style(min_h=viz_fixed_len(min_h)))
            } else {
              viz_col_s2
            }
            c.box(style=viz_col_s2_5, fn() {
              @sf.segmented(
                c,
                path + "/seg",
                labels,
                active_idx,
                on_pick=fn(picked) {
                  if picked >= 0 && picked < ids.length() {
                    viz_state_set(store, hears, state_key, Json::string(ids[picked]))
                  }
                },
              )
              |> ignore
              let tab_body = bodies[active_idx]
              c.box(
                style=tb_style,
                id=c.id(path + "/tbody"),
                taps=false,
                tallest=true,
                fn() {
                  for j = 0; j < tab_body.length(); j = j + 1 {
                    viz_render_ctx(c, store, hears, tab_body[j], path + "/tb\{active_idx}_\{j}", depth + 1)
                  }
                },
              )
              |> ignore
            })
            |> ignore
          }
        }
        "details" | "collapse" | "accordion" => {
          let det_id = viz_json_str(obj, "id", "det_" + path)
          let state_key = viz_json_str(
            obj,
            "state_key",
            viz_json_str(obj, "bind", viz_json_str(obj, "key", "open:" + det_id)),
          )
          let def_open = viz_json_bool(obj, "open", false)
          let sig = viz_state_sig(store, state_key, Json::boolean(def_open))
          let is_open = viz_json_truthy(sig.get())
          let title = viz_json_str(obj, "title", viz_json_str(obj, "label", "详情"))
          let subtitle = viz_json_str(obj, "subtitle", viz_json_str(obj, "note", ""))
          let children = viz_children_of(obj)
          c.box(style=viz_col_s1_5, fn() {
            @sf.choice_row(
              c,
              path + "/det",
              is_open,
              viz_interp(store, title),
              note=viz_interp(store, subtitle),
              on_press=fn() {
                viz_state_set(store, hears, state_key, Json::boolean(!is_open))
              },
            )
            |> ignore
            if is_open {
              c.box(style=viz_col_s2, fn() {
                for i = 0; i < children.length(); i = i + 1 {
                  viz_render_ctx(c, store, hears, children[i], path + "/d\{i}", depth + 1)
                }
              })
              |> ignore
            }
          })
          |> ignore
        }
        "switch" | "toggle" | "check" | "checkbox" => {
          let key = viz_json_str(
            obj,
            "key",
            viz_json_str(obj, "state_key", viz_json_str(obj, "bind", "sw_" + path)),
          )
          let def_val = viz_json_bool(obj, "value", viz_json_bool(obj, "checked", false))
          let sig = viz_state_sig(store, key, Json::boolean(def_val))
          let checked = viz_json_truthy(sig.get())
          let label = viz_json_str(obj, "label", viz_json_str(obj, "title", key))
          let note = viz_json_str(obj, "note", viz_json_str(obj, "subtitle", ""))
          @sf.switch_row(
            c,
            path + "/sw",
            viz_interp(store, label),
            checked,
            note=viz_interp(store, note),
            on_change=fn(next) { viz_state_set(store, hears, key, Json::boolean(next)) },
          )
          |> ignore
        }
        "button" | "action" | "btn" => {
          let label = viz_json_str(obj, "label", viz_json_str(obj, "text", "操作"))
          let tone = viz_btn_tone(viz_json_str(obj, "variant", viz_json_str(obj, "tone", "secondary")))
          let icon = viz_json_str(obj, "icon", "")
          @sf.button(
            c,
            viz_interp(store, label),
            key=path + "/btn",
            tone~,
            icon~,
            on_press=fn() { viz_run_action(store, hears, obj) },
          )
          |> ignore
        }
        "chart" => {
          let spec = viz_chart_of(store, obj)
          viz_chart_ctx(c, path + "/chart", spec)
        }
        "spark" | "sparkline" => {
          let vals = viz_json_num_arr(obj, "values")
          let tone = viz_json_str(obj, "tone", viz_json_str(obj, "color", ""))
          let w = viz_json_num(obj, "width", 108.0)
          let h = viz_json_num(obj, "height", 28.0)
          viz_spark_ctx(c, path + "/spark", vals, tone, w, h)
        }
        "svg" => {
          let raw = viz_json_str(obj, "svg", viz_json_str(obj, "xml", ""))
          let w_fallback = viz_json_num(obj, "width", 400.0)
          let h_fallback = viz_json_num(obj, "height", 120.0)
          let (vb_w, vb_h) = viz_parse_viewbox(viz_json_str(obj, "viewBox", ""), w_fallback, h_fallback)
          viz_svg_ctx(c, path + "/svg", viz_prepare_svg(viz_interp(store, raw), vb_w, vb_h), vb_w, vb_h)
        }
        "divider" | "sep" | "hr" => c.box(style=viz_divider_line, fn() {  }) |> ignore
        _ => {
          let children = viz_children_of(obj)
          if children.length() > 0 {
            c.box(style=viz_col_s2, fn() {
              for i = 0; i < children.length(); i = i + 1 {
                viz_render_ctx(c, store, hears, children[i], path + "/u\{i}", depth + 1)
              }
            })
            |> ignore
          }
        }
      }
    }
    _ => ()
  }
}

///|
fn viz_root_has_title(root_json : Json, title : String) -> Bool {
  match root_json {
    Object(ro) => title != "" && viz_json_str(ro, "title", "") == title
    _ => false
  }
}

///|
pub fn viz_mbui_node(
  parent : @view.View,
  place : String,
  widget : VizMbuiWidget,
  state : () -> Json,
  hears : VizHears,
) -> Unit {
  let store = viz_store_of(place, widget, state())
  parent.box(fn(root) {
    @sf.style_node(root, fn() {
      let _ = viz_store_of(place, widget, state())
      viz_root_col
    })
    root.show(
      fn() {
        let t = store.title_sig.get()
        let sub = store.subtitle_sig.get()
        !viz_root_has_title(store.root_sig.get(), t) && (t != "" || sub != "")
      },
      fn(head) {
        @sf.style_node(head, fn() { viz_col_s0_5 })
        head.show(
          fn() { store.title_sig.get() != "" },
          fn(w) {
            @sf.words_node(w, fn() { viz_interp(store, store.title_sig.get()) }, fn() { @sf.title }) |> ignore
          },
        )
        head.show(
          fn() { store.subtitle_sig.get() != "" },
          fn(w) {
            @sf.words_node(w, fn() { viz_interp(store, store.subtitle_sig.get()) }, fn() { @sf.caption }) |> ignore
          },
        )
      },
    )
    root.show(
      fn() { store.wasm_error.get() != "" },
      fn(err_box) {
        @sf.style_node(err_box, fn() { viz_card_box })
        @sf.words_node(
          err_box,
          fn() { "Wasm 沙箱拦截: " + store.wasm_error.get() },
          fn() { @sf.body.then(@sf.bad) },
        )
        |> ignore
      },
    )
    root.pick(
      fn() { store.tree_ver.get() },
      fn(p, _) {
        @sf.style_node(p, fn() { viz_root_col })
        viz_render_node(p, store, hears, store.root_sig.untracked(), place, 0)
      },
    )
  })
  |> ignore
}

///|
pub fn viz_mbui_ctx(
  c : @ui.Ctx,
  place : String,
  widget : VizMbuiWidget,
  state : Json,
  hears : VizHears,
) -> Unit {
  let store = viz_store_of(place, widget, state)
  let root_json = store.root_sig.get()
  let title = store.title_sig.get()
  let subtitle = store.subtitle_sig.get()
  let w_err = store.wasm_error.get()
  c.box(style=viz_root_col, fn() {
    if !viz_root_has_title(root_json, title) && (title != "" || subtitle != "") {
      c.box(style=viz_col_s0_5, fn() {
        if title != "" {
          c.text(viz_interp(store, title), style=@sf.title) |> ignore
        }
        if subtitle != "" {
          c.text(viz_interp(store, subtitle), style=@sf.caption) |> ignore
        }
      })
      |> ignore
    }
    if w_err != "" {
      c.box(style=viz_card_box, fn() {
        c.text("Wasm 沙箱拦截: " + w_err, style=@sf.body.then(@sf.bad)) |> ignore
      })
      |> ignore
    }
    viz_render_ctx(c, store, hears, root_json, place, 0)
  })
  |> ignore
}
