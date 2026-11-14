// Sandboxed WebAssembly 1.0 bytecode interpreter for mbui mini-programs and plugins.
//
// Runs `.wasm` mini-programs and embedded Wasm compute modules across all platforms
// (including iOS without JIT and Web/Wasm-GC Tester) with:
// - Capability-based host import allowlist (`mbui` / `env` state, tree, and follow-up primitives only; zero OS/network I/O)
// - Deterministic instruction-level Gas metering (`viz_wasm_default_gas` per invocation)
// - Hard linear memory cap (`viz_wasm_max_pages` = 64 pages = 4 MiB) and call stack depth limit (`256`)

///|
pub let viz_wasm_default_gas : Int = 1_000_000

///|
pub let viz_wasm_max_pages : Int = 64

///|
let viz_wasm_page_size : Int = 65536

///|
let viz_wasm_max_call_depth : Int = 256

///|
pub fn is_wasm_bytes(bytes : Bytes) -> Bool {
  bytes.length() >= 8 &&
  bytes[0] == b'\x00' &&
  bytes[1] == b'a' &&
  bytes[2] == b's' &&
  bytes[3] == b'm' &&
  bytes[4] == b'\x01' &&
  bytes[5] == b'\x00' &&
  bytes[6] == b'\x00' &&
  bytes[7] == b'\x00'
}

///|
pub fn viz_base64_encode(bytes : Bytes) -> String {
  let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let out = StringBuilder()
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b0 = bytes[i].to_int()
    let b1 = if i + 1 < n { bytes[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < n { bytes[i + 2].to_int() } else { 0 }
    let triple = (b0 << 16) | (b1 << 8) | b2
    out.write_char(alphabet.get_char((triple >> 18) & 0x3f).unwrap_or('A'))
    out.write_char(alphabet.get_char((triple >> 12) & 0x3f).unwrap_or('A'))
    if i + 1 < n {
      out.write_char(alphabet.get_char((triple >> 6) & 0x3f).unwrap_or('A'))
    } else {
      out.write_char('=')
    }
    if i + 2 < n {
      out.write_char(alphabet.get_char(triple & 0x3f).unwrap_or('A'))
    } else {
      out.write_char('=')
    }
    i += 3
  }
  out.to_string()
}

///|
fn viz_b64_val(ch : Char) -> Int {
  if ch >= 'A' && ch <= 'Z' {
    ch.to_int() - 'A'.to_int()
  } else if ch >= 'a' && ch <= 'z' {
    ch.to_int() - 'a'.to_int() + 26
  } else if ch >= '0' && ch <= '9' {
    ch.to_int() - '0'.to_int() + 52
  } else if ch == '+' || ch == '-' {
    62
  } else if ch == '/' || ch == '_' {
    63
  } else {
    -1
  }
}

///|
pub fn viz_base64_decode(s : String) -> Bytes? {
  let out : Array[Byte] = []
  let mut acc = 0
  let mut bits = 0
  for ch in s {
    if ch == '=' || ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' {
      continue
    }
    let v = viz_b64_val(ch)
    if v < 0 {
      return None
    }
    acc = (acc << 6) | v
    bits += 6
    if bits >= 8 {
      bits -= 8
      out.push(((acc >> bits) & 0xff).to_byte())
    }
  }
  Some(Bytes::from_array(out))
}

///|
fn viz_hex_val(ch : Char) -> Int {
  if ch >= '0' && ch <= '9' {
    ch.to_int() - '0'.to_int()
  } else if ch >= 'a' && ch <= 'f' {
    ch.to_int() - 'a'.to_int() + 10
  } else if ch >= 'A' && ch <= 'F' {
    ch.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
pub fn viz_hex_decode(s : String) -> Bytes? {
  let out : Array[Byte] = []
  let mut hi = -1
  for ch in s {
    if ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' || ch == '_' {
      continue
    }
    let v = viz_hex_val(ch)
    if v < 0 {
      return None
    }
    if hi < 0 {
      hi = v
    } else {
      out.push(((hi << 4) | v).to_byte())
      hi = -1
    }
  }
  if hi >= 0 {
    return None
  }
  Some(Bytes::from_array(out))
}

///|
priv struct WasmReader {
  data : Bytes
  mut pos : Int
}

///|
fn WasmReader::new(data : Bytes, pos : Int) -> WasmReader {
  { data, pos }
}

///|
fn WasmReader::byte(self : WasmReader) -> Result[Int, String] {
  if self.pos >= self.data.length() {
    return Err("unexpected end of wasm binary")
  }
  let b = self.data[self.pos].to_int()
  self.pos += 1
  Ok(b)
}

///|
fn WasmReader::u32(self : WasmReader) -> Result[Int, String] {
  let mut res = 0
  let mut shift = 0
  for _ in 0..<5 {
    let b = match self.byte() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    res = res | ((b & 0x7f) << shift)
    if (b & 0x80) == 0 {
      return Ok(res)
    }
    shift += 7
  }
  Err("invalid u32 leb128")
}

///|
fn WasmReader::i32(self : WasmReader) -> Result[Int, String] {
  let mut res = 0
  let mut shift = 0
  let mut b = 0
  for _ in 0..<5 {
    b = match self.byte() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    res = res | ((b & 0x7f) << shift)
    shift += 7
    if (b & 0x80) == 0 {
      if shift < 32 && (b & 0x40) != 0 {
        res = res | (-1 << shift)
      }
      return Ok(res)
    }
  }
  Err("invalid i32 leb128")
}

///|
fn WasmReader::i64(self : WasmReader) -> Result[Int64, String] {
  let mut res = 0L
  let mut shift = 0
  let mut b = 0
  for _ in 0..<10 {
    b = match self.byte() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    res = res | ((b & 0x7f).to_int64() << shift)
    shift += 7
    if (b & 0x80) == 0 {
      if shift < 64 && (b & 0x40) != 0 {
        res = res | (-1L << shift)
      }
      return Ok(res)
    }
  }
  Err("invalid i64 leb128")
}

///|
fn WasmReader::f32_bits(self : WasmReader) -> Result[Int, String] {
  if self.pos + 4 > self.data.length() {
    return Err("unexpected end reading f32")
  }
  let p = self.pos
  self.pos += 4
  let bits = self.data[p].to_int() |
    (self.data[p + 1].to_int() << 8) |
    (self.data[p + 2].to_int() << 16) |
    (self.data[p + 3].to_int() << 24)
  Ok(bits)
}

///|
fn WasmReader::f64_bits(self : WasmReader) -> Result[Int64, String] {
  if self.pos + 8 > self.data.length() {
    return Err("unexpected end reading f64")
  }
  let p = self.pos
  self.pos += 8
  let mut bits = 0L
  for i in 0..<8 {
    bits = bits | ((self.data[p + i].to_int() & 0xff).to_int64() << (i * 8))
  }
  Ok(bits)
}

///|
fn WasmReader::name(self : WasmReader) -> Result[String, String] {
  let n = match self.u32() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if n < 0 || self.pos + n > self.data.length() {
    return Err("name out of bounds")
  }
  let slice = self.data[self.pos:self.pos + n]
  self.pos += n
  Ok(@utf8.decode_lossy(slice))
}

///|
priv struct WasmFuncType {
  params : Array[Int]
  results : Array[Int]
}

///|
priv struct WasmImportFunc {
  kind : Int
  type_idx : Int
}

///|
priv struct WasmInstr {
  op : Int
  mut imm1 : Int
  mut imm2 : Int
  imm64 : Int64
  table : Array[Int]
}

///|
priv struct WasmCodeFunc {
  type_idx : Int
  num_params : Int
  num_locals : Int
  code : Array[WasmInstr]
}

///|
priv struct WasmLabel {
  target_pc : Int
  stack_height : Int
  arity : Int
  is_loop : Bool
}

///|
pub struct VizWasmHost {
  state_map : Map[String, Json]
  mut state_dirty : Bool
  mut out_tree : String?
  mut out_state : Json?
  mut input_bytes : Bytes
  mut follow_up_draft : String?
}

///|
pub struct VizWasmInstance {
  priv types : Array[WasmFuncType]
  priv imports : Array[WasmImportFunc]
  priv funcs : Array[WasmCodeFunc]
  priv table : Array[Int]
  priv mem : Array[Byte]
  priv max_pages : Int
  priv globals : Array[Int64]
  priv exports_func : Map[String, Int]
  priv exports_global : Map[String, Int]
  priv data_segments : Array[Array[Byte]]
  host : VizWasmHost
  mut last_gas_used : Int
  mut total_gas_used : Int
}

///|
const HOST_SET_TREE : Int = 1
///|
const HOST_SET_STATE : Int = 2
///|
const HOST_STATE_GET_I32 : Int = 3
///|
const HOST_STATE_SET_I32 : Int = 4
///|
const HOST_STATE_GET_F64 : Int = 5
///|
const HOST_STATE_SET_F64 : Int = 6
///|
const HOST_STATE_GET_STR : Int = 7
///|
const HOST_STATE_SET_STR : Int = 8
///|
const HOST_FOLLOW_UP : Int = 9
///|
const HOST_INPUT_LEN : Int = 10
///|
const HOST_INPUT_COPY : Int = 11
///|
const HOST_NOOP : Int = 12

///|
fn resolve_host_import(mod_name : String, field_name : String) -> Result[Int, String] {
  if mod_name != "mbui" && mod_name != "env" && mod_name != "spectest" {
    return Err("disallowed wasm import module: \{mod_name}.\{field_name}")
  }
  match field_name {
    "set_tree" | "mbui_set_tree" | "output_tree" => Ok(HOST_SET_TREE)
    "set_state" | "mbui_set_state" | "output_state" => Ok(HOST_SET_STATE)
    "state_get_i32" | "mbui_state_get_i32" | "get_i32" => Ok(HOST_STATE_GET_I32)
    "state_set_i32" | "mbui_state_set_i32" | "set_i32" => Ok(HOST_STATE_SET_I32)
    "state_get_f64" | "mbui_state_get_f64" | "get_f64" => Ok(HOST_STATE_GET_F64)
    "state_set_f64" | "mbui_state_set_f64" | "set_f64" => Ok(HOST_STATE_SET_F64)
    "state_get_str" | "mbui_state_get_str" | "get_str" => Ok(HOST_STATE_GET_STR)
    "state_set_str" | "mbui_state_set_str" | "set_str" => Ok(HOST_STATE_SET_STR)
    "follow_up" | "mbui_follow_up" | "send_follow_up" => Ok(HOST_FOLLOW_UP)
    "input_len" | "mbui_input_len" => Ok(HOST_INPUT_LEN)
    "input_copy" | "mbui_input_copy" | "input_read" => Ok(HOST_INPUT_COPY)
    "log" | "mbui_log" | "print" | "print_i32" | "print_char" | "abort" => Ok(HOST_NOOP)
    _ => Err("disallowed wasm import function: \{mod_name}.\{field_name}")
  }
}

///|
fn eval_const_expr(r : WasmReader, globals : Array[Int64]) -> Result[Int64, String] {
  let mut val = 0L
  while true {
    let op = match r.byte() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    match op {
      0x0b => return Ok(val)
      0x41 =>
        val = match r.i32() {
          Ok(v) => v.to_int64() & 0xffffffffL
          Err(e) => return Err(e)
        }
      0x42 =>
        val = match r.i64() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
      0x43 =>
        val = match r.f32_bits() {
          Ok(v) => v.to_int64() & 0xffffffffL
          Err(e) => return Err(e)
        }
      0x44 =>
        val = match r.f64_bits() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
      0x23 => {
        let idx = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        if idx >= 0 && idx < globals.length() {
          val = globals[idx]
        }
      }
      _ => return Err("unsupported const expr opcode: \{op}")
    }
  }
  Ok(val)
}

///|
fn block_arity(block_type : Int, types : Array[WasmFuncType]) -> (Int, Int) {
  if block_type == -64 {
    (0, 0)
  } else if block_type < 0 {
    (0, 1)
  } else if block_type < types.length() {
    (types[block_type].params.length(), types[block_type].results.length())
  } else {
    (0, 0)
  }
}

///|
fn decode_function_body(
  r : WasmReader,
  body_end : Int,
  type_idx : Int,
  types : Array[WasmFuncType],
) -> Result[WasmCodeFunc, String] {
  let fn_type = if type_idx >= 0 && type_idx < types.length() {
    types[type_idx]
  } else {
    { params: [], results: [] }
  }
  let local_groups = match r.u32() {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let mut extra_locals = 0
  for _ in 0..<local_groups {
    let count = match r.u32() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    let _ = match r.byte() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    if count < 0 || extra_locals + count > 4096 {
      return Err("too many locals in wasm function")
    }
    extra_locals += count
  }
  let code : Array[WasmInstr] = []
  // Stack of open block instruction indices in `code` (0 = function body root)
  let ctrl_stack : Array[Int] = [-1]
  while r.pos < body_end {
    let op = match r.byte() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    match op {
      0x00 | 0x01 | 0x0f | 0x1a | 0x1b =>
        code.push({ op, imm1: 0, imm2: 0, imm64: 0L, table: [] })
      0x1c => {
        let n = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<n {
          let _ = match r.byte() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        }
        code.push({ op: 0x1b, imm1: 0, imm2: 0, imm64: 0L, table: [] })
      }
      0x02 | 0x03 | 0x04 => {
        let bt = match r.i32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let (p_arity, r_arity) = block_arity(bt, types)
        let packed_arity = (p_arity << 16) | (r_arity & 0xffff)
        let idx = code.length()
        code.push({ op, imm1: -1, imm2: -1, imm64: packed_arity.to_int64(), table: [] })
        ctrl_stack.push(idx)
      }
      0x05 => {
        if ctrl_stack.length() <= 1 {
          return Err("unmatched else in wasm function")
        }
        let if_idx = ctrl_stack[ctrl_stack.length() - 1]
        let else_idx = code.length()
        code.push({ op, imm1: -1, imm2: 0, imm64: 0L, table: [] })
        if if_idx >= 0 {
          code[if_idx].imm1 = else_idx
        }
      }
      0x0b => {
        if ctrl_stack.is_empty() {
          return Err("unmatched end in wasm function")
        }
        let open_idx = ctrl_stack.pop().unwrap_or(-1)
        let end_idx = code.length()
        code.push({ op, imm1: open_idx, imm2: 0, imm64: 0L, table: [] })
        if open_idx >= 0 {
          let after_end = end_idx + 1
          code[open_idx].imm2 = after_end
          let else_idx = code[open_idx].imm1
          if else_idx >= 0 && else_idx < code.length() {
            code[else_idx].imm1 = after_end
          }
        }
        if ctrl_stack.is_empty() {
          break
        }
      }
      0x0c | 0x0d | 0x10 | 0x20 | 0x21 | 0x22 | 0x23 | 0x24 => {
        let idx = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        code.push({ op, imm1: idx, imm2: 0, imm64: 0L, table: [] })
      }
      0x0e => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        if count < 0 || count > 4096 {
          return Err("br_table too large")
        }
        let targets : Array[Int] = []
        for _ in 0..=count {
          let t = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          targets.push(t)
        }
        code.push({ op, imm1: 0, imm2: 0, imm64: 0L, table: targets })
      }
      0x11 => {
        let type_i = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let table_i = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        code.push({ op, imm1: type_i, imm2: table_i, imm64: 0L, table: [] })
      }
      _ if op >= 0x28 && op <= 0x3e => {
        let align = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        if (align & 0x40) != 0 {
          let _ = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        }
        let offset = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        code.push({ op, imm1: offset, imm2: align, imm64: 0L, table: [] })
      }
      0x3f | 0x40 => {
        let mem_idx = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        code.push({ op, imm1: mem_idx, imm2: 0, imm64: 0L, table: [] })
      }
      0x41 => {
        let v = match r.i32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        code.push({ op, imm1: v, imm2: 0, imm64: v.to_int64() & 0xffffffffL, table: [] })
      }
      0x42 => {
        let v = match r.i64() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        code.push({ op, imm1: 0, imm2: 0, imm64: v, table: [] })
      }
      0x43 => {
        let v = match r.f32_bits() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        code.push({ op, imm1: v, imm2: 0, imm64: v.to_int64() & 0xffffffffL, table: [] })
      }
      0x44 => {
        let v = match r.f64_bits() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        code.push({ op, imm1: 0, imm2: 0, imm64: v, table: [] })
      }
      _ if op >= 0x45 && op <= 0xc4 =>
        code.push({ op, imm1: 0, imm2: 0, imm64: 0L, table: [] })
      0xfc => {
        let sub = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        match sub {
          _ if sub >= 0 && sub <= 7 =>
            code.push({ op: 0xfc00 + sub, imm1: 0, imm2: 0, imm64: 0L, table: [] })
          8 => {
            let seg = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let mem_i = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            code.push({ op: 0xfc08, imm1: seg, imm2: mem_i, imm64: 0L, table: [] })
          }
          9 => {
            let seg = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            code.push({ op: 0xfc09, imm1: seg, imm2: 0, imm64: 0L, table: [] })
          }
          10 => {
            let m1 = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let m2 = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            code.push({ op: 0xfc0a, imm1: m1, imm2: m2, imm64: 0L, table: [] })
          }
          11 => {
            let m1 = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            code.push({ op: 0xfc0b, imm1: m1, imm2: 0, imm64: 0L, table: [] })
          }
          _ => return Err("unsupported 0xfc sub-opcode: \{sub}")
        }
      }
      _ => return Err("unsupported wasm opcode: \{op}")
    }
  }
  r.pos = body_end
  Ok({
    type_idx,
    num_params: fn_type.params.length(),
    num_locals: fn_type.params.length() + extra_locals,
    code,
  })
}

///|
pub fn viz_wasm_instantiate(
  bytes : Bytes,
  init_state : Map[String, Json],
  max_pages? : Int = viz_wasm_max_pages,
) -> Result[VizWasmInstance, String] {
  if !is_wasm_bytes(bytes) {
    return Err("invalid wasm magic or version header")
  }
  let r = WasmReader::new(bytes, 8)
  let types : Array[WasmFuncType] = []
  let imports : Array[WasmImportFunc] = []
  let func_type_indices : Array[Int] = []
  let funcs : Array[WasmCodeFunc] = []
  let table : Array[Int] = []
  let mem : Array[Byte] = []
  let mut actual_max_pages = max_pages
  let mut initial_pages = 1
  let globals : Array[Int64] = []
  let exports_func : Map[String, Int] = Map([])
  let exports_global : Map[String, Int] = Map([])
  let data_segments : Array[Array[Byte]] = []
  let active_data : Array[(Int, Array[Byte])] = []
  let mut start_func = -1

  while r.pos < bytes.length() {
    let sec_id = match r.byte() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    let sec_size = match r.u32() {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    let sec_end = r.pos + sec_size
    if sec_size < 0 || sec_end > bytes.length() {
      return Err("wasm section out of bounds")
    }
    match sec_id {
      0 => r.pos = sec_end
      1 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let form = match r.byte() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          if form != 0x60 {
            return Err("unsupported wasm type form: \{form}")
          }
          let np = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let params : Array[Int] = []
          for _ in 0..<np {
            let pt = match r.byte() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            params.push(pt)
          }
          let nr = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let results : Array[Int] = []
          for _ in 0..<nr {
            let rt = match r.byte() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            results.push(rt)
          }
          types.push({ params, results })
        }
      }
      2 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let mod_name = match r.name() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let field_name = match r.name() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let kind = match r.byte() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          match kind {
            0 => {
              let tidx = match r.u32() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              let hkind = match resolve_host_import(mod_name, field_name) {
                Ok(k) => k
                Err(e) => return Err(e)
              }
              imports.push({ kind: hkind, type_idx: tidx })
            }
            1 => {
              let _ = match r.byte() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              let flags = match r.u32() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              let init_sz = match r.u32() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              if (flags & 1) != 0 {
                let _ = match r.u32() {
                  Ok(v) => v
                  Err(e) => return Err(e)
                }
              }
              for _ in 0..<init_sz.min(4096) {
                table.push(-1)
              }
            }
            2 => {
              let flags = match r.u32() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              let min_p = match r.u32() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              initial_pages = min_p.max(0).min(max_pages)
              if (flags & 1) != 0 {
                let max_p = match r.u32() {
                  Ok(v) => v
                  Err(e) => return Err(e)
                }
                actual_max_pages = max_p.max(initial_pages).min(max_pages)
              }
            }
            3 => {
              let _ = match r.byte() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              let _ = match r.byte() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              globals.push(0L)
            }
            _ => return Err("unsupported import kind: \{kind}")
          }
        }
      }
      3 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let tidx = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          func_type_indices.push(tidx)
        }
      }
      4 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let _ = match r.byte() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let flags = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let init_sz = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          if (flags & 1) != 0 {
            let _ = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
          }
          for _ in 0..<init_sz.min(4096) {
            table.push(-1)
          }
        }
      }
      5 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let flags = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let min_p = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          if min_p > max_pages {
            return Err("wasm initial memory (\{min_p} pages) exceeds sandbox limit (\{max_pages} pages)")
          }
          initial_pages = min_p.max(0)
          if (flags & 1) != 0 {
            let max_p = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            actual_max_pages = max_p.max(initial_pages).min(max_pages)
          }
        }
      }
      6 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let _ = match r.byte() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let _ = match r.byte() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let init_val = match eval_const_expr(r, globals) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          globals.push(init_val)
        }
      }
      7 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let name = match r.name() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let kind = match r.byte() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let idx = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          if kind == 0 {
            exports_func[name] = idx
          } else if kind == 3 {
            exports_global[name] = idx
          }
        }
      }
      8 =>
        start_func = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
      9 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let flags = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          if flags == 0 {
            let offset = match eval_const_expr(r, globals) {
              Ok(v) => v.to_int()
              Err(e) => return Err(e)
            }
            let num_elem = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            for i in 0..<num_elem {
              let fidx = match r.u32() {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              let slot = offset + i
              while table.length() <= slot && table.length() < 4096 {
                table.push(-1)
              }
              if slot >= 0 && slot < table.length() {
                table[slot] = fidx
              }
            }
          } else {
            r.pos = sec_end
            break
          }
        }
      }
      10 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for i in 0..<count {
          let body_size = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let body_end = r.pos + body_size
          if body_size < 0 || body_end > sec_end {
            return Err("function body out of bounds")
          }
          let tidx = if i < func_type_indices.length() { func_type_indices[i] } else { 0 }
          let decoded = match decode_function_body(r, body_end, tidx, types) {
            Ok(f) => f
            Err(e) => return Err(e)
          }
          funcs.push(decoded)
        }
      }
      11 => {
        let count = match r.u32() {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        for _ in 0..<count {
          let mode = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let mut offset = 0
          let mut is_active = false
          if mode == 0 {
            is_active = true
            offset = match eval_const_expr(r, globals) {
              Ok(v) => v.to_int()
              Err(e) => return Err(e)
            }
          } else if mode == 2 {
            is_active = true
            let _ = match r.u32() {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            offset = match eval_const_expr(r, globals) {
              Ok(v) => v.to_int()
              Err(e) => return Err(e)
            }
          }
          let data_len = match r.u32() {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          if data_len < 0 || r.pos + data_len > sec_end {
            return Err("data segment out of bounds")
          }
          let seg_bytes : Array[Byte] = Array::makei(data_len, fn(k) { bytes[r.pos + k] })
          r.pos += data_len
          data_segments.push(seg_bytes)
          if is_active {
            active_data.push((offset, seg_bytes))
          }
        }
      }
      12 => r.pos = sec_end
      _ => r.pos = sec_end
    }
    r.pos = sec_end
  }

  let init_byte_len = initial_pages * viz_wasm_page_size
  for _ in 0..<init_byte_len {
    mem.push(b'\x00')
  }
  for seg in active_data {
    let (offset, seg_bytes) = seg
    if offset < 0 || offset + seg_bytes.length() > mem.length() {
      return Err("data segment out of bounds of linear memory")
    }
    for i in 0..<seg_bytes.length() {
      mem[offset + i] = seg_bytes[i]
    }
  }

  let state_copy : Map[String, Json] = Map([])
  for k, v in init_state {
    state_copy[k] = v
  }
  let inst : VizWasmInstance = {
    types,
    imports,
    funcs,
    table,
    mem,
    max_pages: actual_max_pages,
    globals,
    exports_func,
    exports_global,
    data_segments,
    host: {
      state_map: state_copy,
      state_dirty: false,
      out_tree: None,
      out_state: None,
      input_bytes: b"",
      follow_up_draft: None,
    },
    last_gas_used: 0,
    total_gas_used: 0,
  }

  if start_func >= 0 {
    match viz_wasm_call_index(inst, start_func, [], viz_wasm_default_gas) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok(inst)
}

///|
pub fn viz_wasm_has_export(inst : VizWasmInstance, name : String) -> Bool {
  inst.exports_func.contains(name)
}

///|
pub fn viz_wasm_get_global_i64(inst : VizWasmInstance, name : String) -> Int64? {
  match inst.exports_global.get(name) {
    Some(idx) if idx >= 0 && idx < inst.globals.length() => Some(inst.globals[idx])
    _ => None
  }
}

///|
pub fn viz_wasm_set_global_i64(inst : VizWasmInstance, name : String, val : Int64) -> Bool {
  match inst.exports_global.get(name) {
    Some(idx) if idx >= 0 && idx < inst.globals.length() => {
      inst.globals[idx] = val
      true
    }
    _ => false
  }
}

///|
pub fn viz_wasm_read_utf8(inst : VizWasmInstance, ptr : Int, len : Int) -> Result[String, String] {
  if ptr < 0 || len < 0 || ptr + len > inst.mem.length() {
    return Err("wasm memory slice out of bounds (\{ptr} + \{len} > \{inst.mem.length()})")
  }
  if len == 0 {
    return Ok("")
  }
  let arr : Array[Byte] = Array::makei(len, fn(i) { inst.mem[ptr + i] })
  Ok(@utf8.decode_lossy(Bytes::from_array(arr)))
}

///|
pub fn viz_wasm_read_cstring(inst : VizWasmInstance, ptr : Int) -> Result[String, String] {
  if ptr < 0 || ptr >= inst.mem.length() {
    return Err("wasm cstring pointer out of bounds")
  }
  let mut end = ptr
  let max_end = (ptr + 262144).min(inst.mem.length())
  while end < max_end && inst.mem[end] != b'\x00' {
    end += 1
  }
  viz_wasm_read_utf8(inst, ptr, end - ptr)
}

///|
pub fn viz_wasm_write_bytes(inst : VizWasmInstance, ptr : Int, data : Bytes) -> Result[Unit, String] {
  let n = data.length()
  if ptr < 0 || ptr + n > inst.mem.length() {
    return Err("wasm memory write out of bounds")
  }
  for i in 0..<n {
    inst.mem[ptr + i] = data[i]
  }
  Ok(())
}

///|
fn mem_check(mem : Array[Byte], base : Int, offset : Int, size : Int) -> Result[Int, String] {
  if base < 0 || offset < 0 {
    return Err("out of bounds memory access")
  }
  let addr64 = (base.to_int64() & 0xffffffffL) + (offset.to_int64() & 0xffffffffL)
  if addr64 < 0L || addr64 + size.to_int64() > mem.length().to_int64() {
    return Err("out of bounds memory access")
  }
  Ok(addr64.to_int())
}

///|
fn mem_read_u8(mem : Array[Byte], addr : Int) -> Int {
  mem[addr].to_int() & 0xff
}

///|
fn mem_read_i8(mem : Array[Byte], addr : Int) -> Int {
  let v = mem[addr].to_int() & 0xff
  if (v & 0x80) != 0 { v | -256 } else { v }
}

///|
fn mem_read_u16(mem : Array[Byte], addr : Int) -> Int {
  (mem[addr].to_int() & 0xff) | ((mem[addr + 1].to_int() & 0xff) << 8)
}

///|
fn mem_read_i16(mem : Array[Byte], addr : Int) -> Int {
  let v = mem_read_u16(mem, addr)
  if (v & 0x8000) != 0 { v | -65536 } else { v }
}

///|
fn mem_read_i32(mem : Array[Byte], addr : Int) -> Int {
  (mem[addr].to_int() & 0xff) |
  ((mem[addr + 1].to_int() & 0xff) << 8) |
  ((mem[addr + 2].to_int() & 0xff) << 16) |
  ((mem[addr + 3].to_int() & 0xff) << 24)
}

///|
fn mem_read_i64(mem : Array[Byte], addr : Int) -> Int64 {
  let lo = mem_read_i32(mem, addr).to_int64() & 0xffffffffL
  let hi = mem_read_i32(mem, addr + 4).to_int64() & 0xffffffffL
  lo | (hi << 32)
}

///|
fn mem_write_i8(mem : Array[Byte], addr : Int, v : Int) -> Unit {
  mem[addr] = (v & 0xff).to_byte()
}

///|
fn mem_write_i16(mem : Array[Byte], addr : Int, v : Int) -> Unit {
  mem[addr] = (v & 0xff).to_byte()
  mem[addr + 1] = ((v >> 8) & 0xff).to_byte()
}

///|
fn mem_write_i32(mem : Array[Byte], addr : Int, v : Int) -> Unit {
  mem[addr] = (v & 0xff).to_byte()
  mem[addr + 1] = ((v >> 8) & 0xff).to_byte()
  mem[addr + 2] = ((v >> 16) & 0xff).to_byte()
  mem[addr + 3] = ((v >> 24) & 0xff).to_byte()
}

///|
fn mem_write_i64(mem : Array[Byte], addr : Int, v : Int64) -> Unit {
  mem_write_i32(mem, addr, v.to_int())
  mem_write_i32(mem, addr + 4, (v >> 32).to_int())
}

///|
fn bits_to_f32_double(bits : Int) -> Double {
  Float::reinterpret_from_int(bits).to_double()
}

///|
fn double_to_f32_bits(d : Double) -> Int {
  Float::from_double(d).reinterpret_as_int()
}

///|
fn i32_clz(x : Int) -> Int {
  if x == 0 {
    return 32
  }
  let mut n = 0
  let mut u = x.reinterpret_as_uint()
  while (u & 0x80000000U) == 0U {
    n += 1
    u = u << 1
  }
  n
}

///|
fn i32_ctz(x : Int) -> Int {
  if x == 0 {
    return 32
  }
  let mut n = 0
  let mut u = x.reinterpret_as_uint()
  while (u & 1U) == 0U {
    n += 1
    u = u >> 1
  }
  n
}

///|
fn i32_popcnt(x : Int) -> Int {
  let mut n = 0
  let mut u = x.reinterpret_as_uint()
  while u != 0U {
    u = u & (u - 1U)
    n += 1
  }
  n
}

///|
fn i64_clz(x : Int64) -> Int64 {
  if x == 0L {
    return 64L
  }
  let mut n = 0L
  let mut u = x.reinterpret_as_uint64()
  while (u & 0x8000000000000000UL) == 0UL {
    n += 1L
    u = u << 1
  }
  n
}

///|
fn i64_ctz(x : Int64) -> Int64 {
  if x == 0L {
    return 64L
  }
  let mut n = 0L
  let mut u = x.reinterpret_as_uint64()
  while (u & 1UL) == 0UL {
    n += 1L
    u = u >> 1
  }
  n
}

///|
fn i64_popcnt(x : Int64) -> Int64 {
  let mut n = 0L
  let mut u = x.reinterpret_as_uint64()
  while u != 0UL {
    u = u & (u - 1UL)
    n += 1L
  }
  n
}

///|
fn run_host_import(
  inst : VizWasmInstance,
  imp : WasmImportFunc,
  args : Array[Int64],
) -> Result[Array[Int64], String] {
  let a0 = if args.length() > 0 { args[0].to_int() } else { 0 }
  let a1 = if args.length() > 1 { args[1].to_int() } else { 0 }
  let a2 = if args.length() > 2 { args[2].to_int() } else { 0 }
  let a3 = if args.length() > 3 { args[3].to_int() } else { 0 }
  match imp.kind {
    HOST_SET_TREE => {
      let s = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      inst.host.out_tree = Some(s)
      Ok([])
    }
    HOST_SET_STATE => {
      let s = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let parsed : Json = @json.parse(s) catch { _ => return Err("invalid json in mbui.set_state") }
      inst.host.out_state = Some(parsed)
      match parsed {
        Object(m) =>
          for k, v in m {
            inst.host.state_map[k] = v
          }
        _ => ()
      }
      inst.host.state_dirty = true
      Ok([])
    }
    HOST_STATE_GET_I32 => {
      let key = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let res = match inst.host.state_map.get(key) {
        Some(Number(n, ..)) => n.to_int()
        Some(True) => 1
        Some(False) => 0
        Some(String(s)) => viz_parse_num(s, a2.to_double()).to_int()
        _ => a2
      }
      Ok([res.to_int64() & 0xffffffffL])
    }
    HOST_STATE_SET_I32 => {
      let key = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      inst.host.state_map[key] = Json::number(a2.to_double())
      inst.host.state_dirty = true
      Ok([])
    }
    HOST_STATE_GET_F64 => {
      let key = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let fb = if args.length() > 2 { args[2].reinterpret_as_double() } else { 0.0 }
      let res = match inst.host.state_map.get(key) {
        Some(Number(n, ..)) => n
        Some(True) => 1.0
        Some(False) => 0.0
        Some(String(s)) => viz_parse_num(s, fb)
        _ => fb
      }
      Ok([res.reinterpret_as_int64()])
    }
    HOST_STATE_SET_F64 => {
      let key = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let val = if args.length() > 2 { args[2].reinterpret_as_double() } else { 0.0 }
      inst.host.state_map[key] = Json::number(val)
      inst.host.state_dirty = true
      Ok([])
    }
    HOST_STATE_GET_STR => {
      let key = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let str_val = match inst.host.state_map.get(key) {
        Some(String(s)) => s
        Some(Number(n, ..)) => viz_fmt_num(n, "")
        Some(True) => "true"
        Some(False) => "false"
        _ => ""
      }
      let encoded = @utf8.encode(str_val)
      let copy_len = encoded.length().min(a3.max(0))
      if copy_len > 0 {
        if a2 < 0 || a2 + copy_len > inst.mem.length() {
          return Err("out of bounds memory in state_get_str")
        }
        for i in 0..<copy_len {
          inst.mem[a2 + i] = encoded[i]
        }
      }
      Ok([copy_len.to_int64() & 0xffffffffL])
    }
    HOST_STATE_SET_STR => {
      let key = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let val = match viz_wasm_read_utf8(inst, a2, a3) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      inst.host.state_map[key] = Json::string(val)
      inst.host.state_dirty = true
      Ok([])
    }
    HOST_FOLLOW_UP => {
      let prompt = match viz_wasm_read_utf8(inst, a0, a1) {
        Ok(v) => v.trim().to_owned()
        Err(e) => return Err(e)
      }
      if prompt != "" {
        inst.host.follow_up_draft = Some(prompt)
      }
      let ftype = if imp.type_idx >= 0 && imp.type_idx < inst.types.length() {
        inst.types[imp.type_idx]
      } else {
        { params: [], results: [] }
      }
      if ftype.results.length() > 0 {
        Ok([1L])
      } else {
        Ok([])
      }
    }
    HOST_INPUT_LEN => Ok([inst.host.input_bytes.length().to_int64() & 0xffffffffL])
    HOST_INPUT_COPY => {
      let n = inst.host.input_bytes.length().min(a1.max(0))
      if n > 0 {
        if a0 < 0 || a0 + n > inst.mem.length() {
          return Err("out of bounds memory in input_copy")
        }
        for i in 0..<n {
          inst.mem[a0 + i] = inst.host.input_bytes[i]
        }
      }
      Ok([n.to_int64() & 0xffffffffL])
    }
    _ => {
      let ftype = if imp.type_idx >= 0 && imp.type_idx < inst.types.length() {
        inst.types[imp.type_idx]
      } else {
        { params: [], results: [] }
      }
      Ok(Array::make(ftype.results.length(), 0L))
    }
  }
}

///|
fn exec_wasm_func(
  inst : VizWasmInstance,
  func_idx : Int,
  args : Array[Int64],
  gas_ref : Ref[Int],
  depth : Int,
) -> Result[Array[Int64], String] {
  if depth > viz_wasm_max_call_depth {
    return Err("wasm call stack depth limit exceeded")
  }
  let num_imports = inst.imports.length()
  if func_idx < 0 {
    return Err("invalid wasm function index")
  }
  if func_idx < num_imports {
    gas_ref.val -= 1
    if gas_ref.val < 0 {
      return Err("wasm gas limit exceeded")
    }
    return run_host_import(inst, inst.imports[func_idx], args)
  }
  let def_idx = func_idx - num_imports
  if def_idx >= inst.funcs.length() {
    return Err("wasm function index out of bounds")
  }
  let func = inst.funcs[def_idx]
  let ftype = if func.type_idx >= 0 && func.type_idx < inst.types.length() {
    inst.types[func.type_idx]
  } else {
    { params: [], results: [] }
  }
  let ret_arity = ftype.results.length()
  let locals : Array[Int64] = Array::make(func.num_locals, 0L)
  for i in 0..<func.num_params.min(args.length()) {
    locals[i] = args[i]
  }
  let stack : Array[Int64] = []
  let labels : Array[WasmLabel] = [
    { target_pc: func.code.length(), stack_height: 0, arity: ret_arity, is_loop: false },
  ]
  let code = func.code
  let code_len = code.length()
  let mut pc = 0

  let pop1 = fn() -> Int64 { stack.pop().unwrap_or(0L) }
  let pop_i32 = fn() -> Int { stack.pop().unwrap_or(0L).to_int() }
  let push_i32 = fn(v : Int) -> Unit { stack.push(v.to_int64() & 0xffffffffL) }
  let push_bool = fn(b : Bool) -> Unit { stack.push(if b { 1L } else { 0L }) }

  let do_branch = fn(label_depth : Int) -> Result[Int, String] {
    let target_idx = labels.length() - 1 - label_depth
    if target_idx < 0 {
      return Err("invalid branch depth")
    }
    let lbl = labels[target_idx]
    let arity = lbl.arity
    let top_vals : Array[Int64] = Array::make(arity, 0L)
    for i = arity - 1; i >= 0; i = i - 1 {
      top_vals[i] = stack.pop().unwrap_or(0L)
    }
    while stack.length() > lbl.stack_height {
      let _ = stack.pop()
    }
    for v in top_vals {
      stack.push(v)
    }
    if lbl.is_loop {
      while labels.length() > target_idx + 1 {
        let _ = labels.pop()
      }
    } else {
      while labels.length() > target_idx {
        let _ = labels.pop()
      }
    }
    Ok(lbl.target_pc)
  }

  while pc < code_len && !labels.is_empty() {
    gas_ref.val -= 1
    if gas_ref.val < 0 {
      return Err("wasm gas limit exceeded")
    }
    let ins = code[pc]
    pc += 1
    let op = ins.op
    match op {
      0x00 => return Err("wasm unreachable trap")
      0x01 => ()
      0x02 => {
        let packed = ins.imm64.to_int()
        let p_arity = (packed >> 16) & 0xffff
        let r_arity = packed & 0xffff
        let base_h = (stack.length() - p_arity).max(0)
        labels.push({ target_pc: ins.imm2, stack_height: base_h, arity: r_arity, is_loop: false })
      }
      0x03 => {
        let packed = ins.imm64.to_int()
        let p_arity = (packed >> 16) & 0xffff
        let base_h = (stack.length() - p_arity).max(0)
        labels.push({ target_pc: pc, stack_height: base_h, arity: p_arity, is_loop: true })
      }
      0x04 => {
        let cond = pop_i32()
        let packed = ins.imm64.to_int()
        let p_arity = (packed >> 16) & 0xffff
        let r_arity = packed & 0xffff
        let base_h = (stack.length() - p_arity).max(0)
        if cond != 0 {
          labels.push({ target_pc: ins.imm2, stack_height: base_h, arity: r_arity, is_loop: false })
        } else if ins.imm1 >= 0 {
          labels.push({ target_pc: ins.imm2, stack_height: base_h, arity: r_arity, is_loop: false })
          pc = ins.imm1 + 1
        } else {
          pc = ins.imm2
        }
      }
      0x05 => {
        // End of `then` branch: pop the `if` label and jump to after `end`
        if !labels.is_empty() {
          let lbl = labels.pop().unwrap()
          let arity = lbl.arity
          let top_vals : Array[Int64] = Array::make(arity, 0L)
          for i = arity - 1; i >= 0; i = i - 1 {
            top_vals[i] = stack.pop().unwrap_or(0L)
          }
          while stack.length() > lbl.stack_height {
            let _ = stack.pop()
          }
          for v in top_vals {
            stack.push(v)
          }
        }
        pc = ins.imm1
      }
      0x0b => {
        if !labels.is_empty() {
          let lbl = labels.pop().unwrap()
          let arity = if lbl.is_loop {
            if ins.imm1 >= 0 && ins.imm1 < code_len {
              code[ins.imm1].imm64.to_int() & 0xffff
            } else {
              0
            }
          } else {
            lbl.arity
          }
          let top_vals : Array[Int64] = Array::make(arity, 0L)
          for i = arity - 1; i >= 0; i = i - 1 {
            top_vals[i] = stack.pop().unwrap_or(0L)
          }
          while stack.length() > lbl.stack_height {
            let _ = stack.pop()
          }
          for v in top_vals {
            stack.push(v)
          }
        }
      }
      0x0c =>
        pc = match do_branch(ins.imm1) {
          Ok(next_pc) => next_pc
          Err(e) => return Err(e)
        }
      0x0d => {
        let cond = pop_i32()
        if cond != 0 {
          pc = match do_branch(ins.imm1) {
            Ok(next_pc) => next_pc
            Err(e) => return Err(e)
          }
        }
      }
      0x0e => {
        let idx = pop_i32()
        let tbl = ins.table
        let target_depth = if idx >= 0 && idx < tbl.length() - 1 {
          tbl[idx]
        } else {
          tbl[tbl.length() - 1]
        }
        pc = match do_branch(target_depth) {
          Ok(next_pc) => next_pc
          Err(e) => return Err(e)
        }
      }
      0x0f => break
      0x10 => {
        let callee_idx = ins.imm1
        let callee_type_idx = if callee_idx < num_imports {
          inst.imports[callee_idx].type_idx
        } else {
          let d = callee_idx - num_imports
          if d >= 0 && d < inst.funcs.length() { inst.funcs[d].type_idx } else { -1 }
        }
        let ctype = if callee_type_idx >= 0 && callee_type_idx < inst.types.length() {
          inst.types[callee_type_idx]
        } else {
          { params: [], results: [] }
        }
        let n_args = ctype.params.length()
        let call_args : Array[Int64] = Array::make(n_args, 0L)
        for i = n_args - 1; i >= 0; i = i - 1 {
          call_args[i] = pop1()
        }
        let res = match exec_wasm_func(inst, callee_idx, call_args, gas_ref, depth + 1) {
          Ok(r) => r
          Err(e) => return Err(e)
        }
        for v in res {
          stack.push(v)
        }
      }
      0x11 => {
        let elem_idx = pop_i32()
        if elem_idx < 0 || elem_idx >= inst.table.length() {
          return Err("indirect call index out of bounds")
        }
        let callee_idx = inst.table[elem_idx]
        if callee_idx < 0 {
          return Err("uninitialized table element in call_indirect")
        }
        let expected_type_idx = ins.imm1
        let ctype = if expected_type_idx >= 0 && expected_type_idx < inst.types.length() {
          inst.types[expected_type_idx]
        } else {
          { params: [], results: [] }
        }
        let n_args = ctype.params.length()
        let call_args : Array[Int64] = Array::make(n_args, 0L)
        for i = n_args - 1; i >= 0; i = i - 1 {
          call_args[i] = pop1()
        }
        let res = match exec_wasm_func(inst, callee_idx, call_args, gas_ref, depth + 1) {
          Ok(r) => r
          Err(e) => return Err(e)
        }
        for v in res {
          stack.push(v)
        }
      }
      0x1a => ignore(pop1())
      0x1b => {
        let c = pop_i32()
        let v2 = pop1()
        let v1 = pop1()
        stack.push(if c != 0 { v1 } else { v2 })
      }
      0x20 => stack.push(locals[ins.imm1])
      0x21 => locals[ins.imm1] = pop1()
      0x22 => {
        let v = pop1()
        locals[ins.imm1] = v
        stack.push(v)
      }
      0x23 => stack.push(inst.globals[ins.imm1])
      0x24 => inst.globals[ins.imm1] = pop1()
      0x28 | 0x2a => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 4) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        push_i32(mem_read_i32(inst.mem, addr))
      }
      0x29 | 0x2b => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 8) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        stack.push(mem_read_i64(inst.mem, addr))
      }
      0x2c => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 1) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        push_i32(mem_read_i8(inst.mem, addr))
      }
      0x2d => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 1) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        push_i32(mem_read_u8(inst.mem, addr))
      }
      0x2e => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 2) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        push_i32(mem_read_i16(inst.mem, addr))
      }
      0x2f => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 2) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        push_i32(mem_read_u16(inst.mem, addr))
      }
      0x30 => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 1) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        stack.push(mem_read_i8(inst.mem, addr).to_int64())
      }
      0x31 => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 1) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        stack.push(mem_read_u8(inst.mem, addr).to_int64() & 0xffL)
      }
      0x32 => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 2) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        stack.push(mem_read_i16(inst.mem, addr).to_int64())
      }
      0x33 => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 2) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        stack.push(mem_read_u16(inst.mem, addr).to_int64() & 0xffffL)
      }
      0x34 => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 4) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        stack.push(mem_read_i32(inst.mem, addr).to_int64())
      }
      0x35 => {
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 4) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        stack.push(mem_read_i32(inst.mem, addr).to_int64() & 0xffffffffL)
      }
      0x36 | 0x38 => {
        let v = pop_i32()
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 4) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        mem_write_i32(inst.mem, addr, v)
      }
      0x37 | 0x39 => {
        let v = pop1()
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 8) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        mem_write_i64(inst.mem, addr, v)
      }
      0x3a | 0x3c => {
        let v = pop1().to_int()
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 1) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        mem_write_i8(inst.mem, addr, v)
      }
      0x3b | 0x3d => {
        let v = pop1().to_int()
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 2) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        mem_write_i16(inst.mem, addr, v)
      }
      0x3e => {
        let v = pop1().to_int()
        let base = pop_i32()
        let addr = match mem_check(inst.mem, base, ins.imm1, 4) {
          Ok(a) => a
          Err(e) => return Err(e)
        }
        mem_write_i32(inst.mem, addr, v)
      }
      0x3f => push_i32(inst.mem.length() / viz_wasm_page_size)
      0x40 => {
        let delta = pop_i32()
        let cur_pages = inst.mem.length() / viz_wasm_page_size
        if delta < 0 || cur_pages + delta > inst.max_pages {
          push_i32(-1)
        } else {
          let add_bytes = delta * viz_wasm_page_size
          for _ in 0..<add_bytes {
            inst.mem.push(b'\x00')
          }
          push_i32(cur_pages)
        }
      }
      0x41 | 0x42 | 0x43 | 0x44 => stack.push(ins.imm64)
      0x45 => push_bool(pop_i32() == 0)
      0x46 => {
        let b = pop_i32()
        let a = pop_i32()
        push_bool(a == b)
      }
      0x47 => {
        let b = pop_i32()
        let a = pop_i32()
        push_bool(a != b)
      }
      0x48 => {
        let b = pop_i32()
        let a = pop_i32()
        push_bool(a < b)
      }
      0x49 => {
        let b = pop_i32().reinterpret_as_uint()
        let a = pop_i32().reinterpret_as_uint()
        push_bool(a < b)
      }
      0x4a => {
        let b = pop_i32()
        let a = pop_i32()
        push_bool(a > b)
      }
      0x4b => {
        let b = pop_i32().reinterpret_as_uint()
        let a = pop_i32().reinterpret_as_uint()
        push_bool(a > b)
      }
      0x4c => {
        let b = pop_i32()
        let a = pop_i32()
        push_bool(a <= b)
      }
      0x4d => {
        let b = pop_i32().reinterpret_as_uint()
        let a = pop_i32().reinterpret_as_uint()
        push_bool(a <= b)
      }
      0x4e => {
        let b = pop_i32()
        let a = pop_i32()
        push_bool(a >= b)
      }
      0x4f => {
        let b = pop_i32().reinterpret_as_uint()
        let a = pop_i32().reinterpret_as_uint()
        push_bool(a >= b)
      }
      0x50 => push_bool(pop1() == 0L)
      0x51 => {
        let b = pop1()
        let a = pop1()
        push_bool(a == b)
      }
      0x52 => {
        let b = pop1()
        let a = pop1()
        push_bool(a != b)
      }
      0x53 => {
        let b = pop1()
        let a = pop1()
        push_bool(a < b)
      }
      0x54 => {
        let b = pop1().reinterpret_as_uint64()
        let a = pop1().reinterpret_as_uint64()
        push_bool(a < b)
      }
      0x55 => {
        let b = pop1()
        let a = pop1()
        push_bool(a > b)
      }
      0x56 => {
        let b = pop1().reinterpret_as_uint64()
        let a = pop1().reinterpret_as_uint64()
        push_bool(a > b)
      }
      0x57 => {
        let b = pop1()
        let a = pop1()
        push_bool(a <= b)
      }
      0x58 => {
        let b = pop1().reinterpret_as_uint64()
        let a = pop1().reinterpret_as_uint64()
        push_bool(a <= b)
      }
      0x59 => {
        let b = pop1()
        let a = pop1()
        push_bool(a >= b)
      }
      0x5a => {
        let b = pop1().reinterpret_as_uint64()
        let a = pop1().reinterpret_as_uint64()
        push_bool(a >= b)
      }
      0x5b | 0x5c | 0x5d | 0x5e | 0x5f | 0x60 => {
        let b = bits_to_f32_double(pop_i32())
        let a = bits_to_f32_double(pop_i32())
        let r = match op {
          0x5b => a == b
          0x5c => a != b
          0x5d => a < b
          0x5e => a > b
          0x5f => a <= b
          _ => a >= b
        }
        push_bool(r)
      }
      0x61 | 0x62 | 0x63 | 0x64 | 0x65 | 0x66 => {
        let b = pop1().reinterpret_as_double()
        let a = pop1().reinterpret_as_double()
        let r = match op {
          0x61 => a == b
          0x62 => a != b
          0x63 => a < b
          0x64 => a > b
          0x65 => a <= b
          _ => a >= b
        }
        push_bool(r)
      }
      0x67 => push_i32(i32_clz(pop_i32()))
      0x68 => push_i32(i32_ctz(pop_i32()))
      0x69 => push_i32(i32_popcnt(pop_i32()))
      0x6a => {
        let b = pop_i32()
        let a = pop_i32()
        push_i32(a + b)
      }
      0x6b => {
        let b = pop_i32()
        let a = pop_i32()
        push_i32(a - b)
      }
      0x6c => {
        let b = pop_i32()
        let a = pop_i32()
        push_i32(a * b)
      }
      0x6d => {
        let b = pop_i32()
        let a = pop_i32()
        if b == 0 {
          return Err("integer divide by zero")
        }
        push_i32(a / b)
      }
      0x6e => {
        let b = pop_i32().reinterpret_as_uint()
        let a = pop_i32().reinterpret_as_uint()
        if b == 0U {
          return Err("integer divide by zero")
        }
        push_i32((a / b).reinterpret_as_int())
      }
      0x6f => {
        let b = pop_i32()
        let a = pop_i32()
        if b == 0 {
          return Err("integer divide by zero")
        }
        push_i32(a % b)
      }
      0x70 => {
        let b = pop_i32().reinterpret_as_uint()
        let a = pop_i32().reinterpret_as_uint()
        if b == 0U {
          return Err("integer divide by zero")
        }
        push_i32((a % b).reinterpret_as_int())
      }
      0x71 => {
        let b = pop_i32()
        let a = pop_i32()
        push_i32(a & b)
      }
      0x72 => {
        let b = pop_i32()
        let a = pop_i32()
        push_i32(a | b)
      }
      0x73 => {
        let b = pop_i32()
        let a = pop_i32()
        push_i32(a ^ b)
      }
      0x74 => {
        let b = pop_i32() & 31
        let a = pop_i32()
        push_i32(a << b)
      }
      0x75 => {
        let b = pop_i32() & 31
        let a = pop_i32()
        push_i32(a >> b)
      }
      0x76 => {
        let b = pop_i32() & 31
        let a = pop_i32().reinterpret_as_uint()
        push_i32((a >> b).reinterpret_as_int())
      }
      0x77 => {
        let k = pop_i32() & 31
        let a = pop_i32().reinterpret_as_uint()
        let r = if k == 0 { a } else { (a << k) | (a >> (32 - k)) }
        push_i32(r.reinterpret_as_int())
      }
      0x78 => {
        let k = pop_i32() & 31
        let a = pop_i32().reinterpret_as_uint()
        let r = if k == 0 { a } else { (a >> k) | (a << (32 - k)) }
        push_i32(r.reinterpret_as_int())
      }
      0x79 => stack.push(i64_clz(pop1()))
      0x7a => stack.push(i64_ctz(pop1()))
      0x7b => stack.push(i64_popcnt(pop1()))
      0x7c => {
        let b = pop1()
        let a = pop1()
        stack.push(a + b)
      }
      0x7d => {
        let b = pop1()
        let a = pop1()
        stack.push(a - b)
      }
      0x7e => {
        let b = pop1()
        let a = pop1()
        stack.push(a * b)
      }
      0x7f => {
        let b = pop1()
        let a = pop1()
        if b == 0L {
          return Err("integer divide by zero")
        }
        stack.push(a / b)
      }
      0x80 => {
        let b = pop1().reinterpret_as_uint64()
        let a = pop1().reinterpret_as_uint64()
        if b == 0UL {
          return Err("integer divide by zero")
        }
        stack.push((a / b).reinterpret_as_int64())
      }
      0x81 => {
        let b = pop1()
        let a = pop1()
        if b == 0L {
          return Err("integer divide by zero")
        }
        stack.push(a % b)
      }
      0x82 => {
        let b = pop1().reinterpret_as_uint64()
        let a = pop1().reinterpret_as_uint64()
        if b == 0UL {
          return Err("integer divide by zero")
        }
        stack.push((a % b).reinterpret_as_int64())
      }
      0x83 => {
        let b = pop1()
        let a = pop1()
        stack.push(a & b)
      }
      0x84 => {
        let b = pop1()
        let a = pop1()
        stack.push(a | b)
      }
      0x85 => {
        let b = pop1()
        let a = pop1()
        stack.push(a ^ b)
      }
      0x86 => {
        let b = pop1().to_int() & 63
        let a = pop1()
        stack.push(a << b)
      }
      0x87 => {
        let b = pop1().to_int() & 63
        let a = pop1()
        stack.push(a >> b)
      }
      0x88 => {
        let b = pop1().to_int() & 63
        let a = pop1().reinterpret_as_uint64()
        stack.push((a >> b).reinterpret_as_int64())
      }
      0x89 => {
        let k = pop1().to_int() & 63
        let a = pop1().reinterpret_as_uint64()
        let r = if k == 0 { a } else { (a << k) | (a >> (64 - k)) }
        stack.push(r.reinterpret_as_int64())
      }
      0x8a => {
        let k = pop1().to_int() & 63
        let a = pop1().reinterpret_as_uint64()
        let r = if k == 0 { a } else { (a >> k) | (a << (64 - k)) }
        stack.push(r.reinterpret_as_int64())
      }
      _ if op >= 0x8b && op <= 0x98 =>
        if op <= 0x91 {
          let a = bits_to_f32_double(pop_i32())
          let r = match op {
            0x8b => a.abs()
            0x8c => -a
            0x8d => a.ceil()
            0x8e => a.floor()
            0x8f => a.trunc()
            0x90 => a.round()
            _ => a.sqrt()
          }
          push_i32(double_to_f32_bits(r))
        } else {
          let b = bits_to_f32_double(pop_i32())
          let a = bits_to_f32_double(pop_i32())
          let r = match op {
            0x92 => a + b
            0x93 => a - b
            0x94 => a * b
            0x95 => a / b
            0x96 => if a < b { a } else { b }
            0x97 => if a > b { a } else { b }
            _ => if b < 0.0 { -a.abs() } else { a.abs() }
          }
          push_i32(double_to_f32_bits(r))
        }
      _ if op >= 0x99 && op <= 0xa6 =>
        if op <= 0x9f {
          let a = pop1().reinterpret_as_double()
          let r = match op {
            0x99 => a.abs()
            0x9a => -a
            0x9b => a.ceil()
            0x9c => a.floor()
            0x9d => a.trunc()
            0x9e => a.round()
            _ => a.sqrt()
          }
          stack.push(r.reinterpret_as_int64())
        } else {
          let b = pop1().reinterpret_as_double()
          let a = pop1().reinterpret_as_double()
          let r = match op {
            0xa0 => a + b
            0xa1 => a - b
            0xa2 => a * b
            0xa3 => a / b
            0xa4 => if a < b { a } else { b }
            0xa5 => if a > b { a } else { b }
            _ => if b < 0.0 { -a.abs() } else { a.abs() }
          }
          stack.push(r.reinterpret_as_int64())
        }
      0xa7 => push_i32(pop1().to_int())
      0xa8 | 0xa9 | 0xfc00 | 0xfc01 => {
        let a = bits_to_f32_double(pop_i32())
        push_i32(a.to_int())
      }
      0xaa | 0xab | 0xfc02 | 0xfc03 => {
        let a = pop1().reinterpret_as_double()
        push_i32(a.to_int())
      }
      0xac => stack.push(pop_i32().to_int64())
      0xad => stack.push(pop_i32().to_int64() & 0xffffffffL)
      0xae | 0xaf | 0xfc04 | 0xfc05 => {
        let a = bits_to_f32_double(pop_i32())
        stack.push(a.to_int64())
      }
      0xb0 | 0xb1 | 0xfc06 | 0xfc07 => {
        let a = pop1().reinterpret_as_double()
        stack.push(a.to_int64())
      }
      0xb2 => push_i32(double_to_f32_bits(pop_i32().to_double()))
      0xb3 => push_i32(double_to_f32_bits(pop_i32().reinterpret_as_uint().to_double()))
      0xb4 => push_i32(double_to_f32_bits(pop1().to_double()))
      0xb5 => push_i32(double_to_f32_bits(pop1().reinterpret_as_uint64().to_double()))
      0xb6 => push_i32(double_to_f32_bits(pop1().reinterpret_as_double()))
      0xb7 => stack.push(pop_i32().to_double().reinterpret_as_int64())
      0xb8 => stack.push(pop_i32().reinterpret_as_uint().to_double().reinterpret_as_int64())
      0xb9 => stack.push(pop1().to_double().reinterpret_as_int64())
      0xba => stack.push(pop1().reinterpret_as_uint64().to_double().reinterpret_as_int64())
      0xbb => stack.push(bits_to_f32_double(pop_i32()).reinterpret_as_int64())
      0xbc | 0xbd | 0xbe | 0xbf => ()
      0xc0 => {
        let v = pop_i32() & 0xff
        push_i32(if (v & 0x80) != 0 { v | -256 } else { v })
      }
      0xc1 => {
        let v = pop_i32() & 0xffff
        push_i32(if (v & 0x8000) != 0 { v | -65536 } else { v })
      }
      0xc2 => {
        let v = pop1().to_int() & 0xff
        stack.push((if (v & 0x80) != 0 { v | -256 } else { v }).to_int64())
      }
      0xc3 => {
        let v = pop1().to_int() & 0xffff
        stack.push((if (v & 0x8000) != 0 { v | -65536 } else { v }).to_int64())
      }
      0xc4 => stack.push(pop1().to_int().to_int64())
      0xfc08 => {
        let n = pop_i32()
        let s = pop_i32()
        let d = pop_i32()
        let seg_i = ins.imm1
        if seg_i < 0 || seg_i >= inst.data_segments.length() {
          return Err("data segment index out of bounds")
        }
        let seg = inst.data_segments[seg_i]
        if n < 0 || s < 0 || d < 0 || s + n > seg.length() || d + n > inst.mem.length() {
          return Err("out of bounds memory.init")
        }
        for i in 0..<n {
          inst.mem[d + i] = seg[s + i]
        }
      }
      0xfc09 => {
        let seg_i = ins.imm1
        if seg_i >= 0 && seg_i < inst.data_segments.length() {
          inst.data_segments[seg_i].clear()
        }
      }
      0xfc0a => {
        let n = pop_i32()
        let s = pop_i32()
        let d = pop_i32()
        if n < 0 || s < 0 || d < 0 || s + n > inst.mem.length() || d + n > inst.mem.length() {
          return Err("out of bounds memory.copy")
        }
        if d <= s {
          for i in 0..<n {
            inst.mem[d + i] = inst.mem[s + i]
          }
        } else {
          for i = n - 1; i >= 0; i = i - 1 {
            inst.mem[d + i] = inst.mem[s + i]
          }
        }
      }
      0xfc0b => {
        let n = pop_i32()
        let val = (pop_i32() & 0xff).to_byte()
        let d = pop_i32()
        if n < 0 || d < 0 || d + n > inst.mem.length() {
          return Err("out of bounds memory.fill")
        }
        for i in 0..<n {
          inst.mem[d + i] = val
        }
      }
      _ => return Err("unhandled wasm opcode: \{op}")
    }
  }

  let out : Array[Int64] = Array::make(ret_arity, 0L)
  for i = ret_arity - 1; i >= 0; i = i - 1 {
    out[i] = stack.pop().unwrap_or(0L)
  }
  Ok(out)
}

///|
pub fn viz_wasm_call_index(
  inst : VizWasmInstance,
  func_idx : Int,
  args : Array[Int64],
  gas_limit : Int,
) -> Result[Array[Int64], String] {
  let gas_ref : Ref[Int] = Ref(gas_limit)
  let res = exec_wasm_func(inst, func_idx, args, gas_ref, 0)
  let used = gas_limit - gas_ref.val
  inst.last_gas_used = used
  inst.total_gas_used += used
  res
}

///|
pub fn viz_wasm_call(
  inst : VizWasmInstance,
  name : String,
  args : Array[Int64],
  gas_limit? : Int = viz_wasm_default_gas,
) -> Result[Array[Int64], String] {
  match inst.exports_func.get(name) {
    Some(idx) => viz_wasm_call_index(inst, idx, args, gas_limit)
    None => Err("wasm export not found: \{name}")
  }
}

///|
pub fn viz_wasm_func_param_count(inst : VizWasmInstance, name : String) -> Int {
  match inst.exports_func.get(name) {
    Some(idx) => {
      let num_imports = inst.imports.length()
      let tidx = if idx < num_imports {
        inst.imports[idx].type_idx
      } else {
        let d = idx - num_imports
        if d >= 0 && d < inst.funcs.length() { inst.funcs[d].type_idx } else { -1 }
      }
      if tidx >= 0 && tidx < inst.types.length() {
        inst.types[tidx].params.length()
      } else {
        0
      }
    }
    None => -1
  }
}

///|
pub fn viz_wasm_pass_input(
  inst : VizWasmInstance,
  input : Bytes,
  gas_limit? : Int = viz_wasm_default_gas,
) -> Result[(Int, Int), String] {
  inst.host.input_bytes = input
  let len = input.length()
  if len == 0 {
    return Ok((0, 0))
  }
  if viz_wasm_has_export(inst, "mbui_alloc") {
    match viz_wasm_call(inst, "mbui_alloc", [len.to_int64()], gas_limit~) {
      Ok(vals) if vals.length() > 0 => {
        let ptr = vals[0].to_int()
        match viz_wasm_write_bytes(inst, ptr, input) {
          Ok(_) => return Ok((ptr, len))
          Err(e) => return Err(e)
        }
      }
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok((0, len))
}

///|
pub fn viz_wasm_extract_string(
  inst : VizWasmInstance,
  ret_vals : Array[Int64],
) -> Result[String?, String] {
  match inst.host.out_tree {
    Some(s) => {
      inst.host.out_tree = None
      return Ok(Some(s))
    }
    None => ()
  }
  if ret_vals.is_empty() {
    if viz_wasm_has_export(inst, "mbui_tree_ptr") && viz_wasm_has_export(inst, "mbui_tree_len") {
      match (viz_wasm_call(inst, "mbui_tree_ptr", []), viz_wasm_call(inst, "mbui_tree_len", [])) {
        (Ok(p), Ok(l)) if p.length() > 0 && l.length() > 0 => {
          let ptr = p[0].to_int()
          let len = l[0].to_int()
          if len > 0 {
            match viz_wasm_read_utf8(inst, ptr, len) {
              Ok(s) => return Ok(Some(s))
              Err(e) => return Err(e)
            }
          }
        }
        _ => ()
      }
    }
    return Ok(None)
  }
  let v = ret_vals[0]
  let hi = ((v >> 32) & 0xffffffffL).to_int()
  let lo = (v & 0xffffffffL).to_int()
  if hi >= 0 && lo > 0 && hi + lo <= inst.mem.length() {
    match viz_wasm_read_utf8(inst, hi, lo) {
      Ok(s) => return Ok(Some(s))
      Err(e) => return Err(e)
    }
  }
  if ret_vals.length() >= 2 {
    let ptr = ret_vals[0].to_int()
    let len = ret_vals[1].to_int()
    if ptr >= 0 && len > 0 && ptr + len <= inst.mem.length() {
      match viz_wasm_read_utf8(inst, ptr, len) {
        Ok(s) => return Ok(Some(s))
        Err(e) => return Err(e)
      }
    }
  }
  if hi == 0 && lo > 0 && lo < inst.mem.length() {
    if viz_wasm_has_export(inst, "mbui_tree_len") {
      match viz_wasm_call(inst, "mbui_tree_len", []) {
        Ok(l) if l.length() > 0 && l[0].to_int() > 0 =>
          match viz_wasm_read_utf8(inst, lo, l[0].to_int()) {
            Ok(s) => return Ok(Some(s))
            Err(e) => return Err(e)
          }
        _ => ()
      }
    }
    match viz_wasm_read_cstring(inst, lo) {
      Ok(s) if s.trim().has_prefix("{") => return Ok(Some(s))
      _ => ()
    }
  }
  Ok(None)
}
