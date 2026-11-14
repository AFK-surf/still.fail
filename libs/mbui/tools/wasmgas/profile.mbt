// A classic Wasm program made to count what it runs (wasmgas profile IN OUT), deterministically, whatever engine runs
// it: an instruction counted once each time it runs.
//
// Each straight run of a function's instructions (cut after every control instruction: block, loop, if, else, end,
// br, br_if, br_table, br_on_null, br_on_non_null, return, return_call*, unreachable; a call's return is no cut) adds
// as it begins its length to:
// - the exported i64 global `__gas`, all the program has run;
// - the function's own count in a memory of its own, appended and exported as `__pm` (eight i64s a function, at 64·k,
//   k its place among the defined functions: its index less the imported functions'): its own (+0), all run inside
//   its calls (+8: the outermost call alone where it is reentered), its calls (+16); +24 and +32 where its outermost
//   call began and how deep it is; +40 the calls of MoonBit's allocator it made itself (who made what is allocated),
//   +56 those made inside its calls (the outermost alone, as +8), +48 how many there were as its outermost call began. Each defined function gets a wrapper appended that counts around it; every call of
//   it (call, return_call, ref.func, the tables' elements, the exports) goes to the wrapper. The memory holds two such
//   tables, in its halves: the first the program's, the second what the functions counted apart (`apart`, below) run;
// - each kind's (KINDS, below) in an exported i64 global `__k<i>`, i its place in KINDS: how many of each kind the run
//   holds. Their sum is `__gas`.
// The functions counted apart (by their names: a test's own, not the program's: its stand-in for the host, the work a
// device's host does in its own code; its driver looking for what is on screen, a device's runs outside the app): each call of one of them counted as one call of the host's (its own, all inside it,
// its call: one each), what it runs inside left out of the above: `__gas` and the kinds as they were before it, the
// functions it calls counted in the second table; what it ran in the exported i64 global `__a`, the calls the rest of
// the program made of them in `__ac`.
// The start function (the packages' initializers, run once as the module is made) is left as it is, uncounted.
// Nothing else of the module changes. What it cannot read it refuses (a GC type, exceptions, threads): a new
// compiler feature never counted wrong in silence. (A memory, not globals, for the functions: a host makes each
// exported global an object of its own, a hundred thousand of them too many.)

///|
/// The kinds of instruction counted apart: what each costs differs, and by how much differs between a Wasm engine and
/// the native build. In order: what compiles to nothing (block, loop, else, end, nop); locals, constants, drop,
/// select, ref.null; globals; branches (if, br*, return, unreachable, br_on_null*); integer arithmetic; float
/// arithmetic and conversions; division, remainder, square root; linear memory's loads and stores; a GC object's
/// fields (none in classic Wasm); calls of a defined function; calls through a table or a reference; calls of an
/// imported function (the host); casts (none in classic Wasm); calls of MoonBit's allocator; bulk copies and fills
/// (their cost by their length, not counted here); the rest; calls of MoonBit's free; of its incref and decref (linear
/// memory's reference counts, as the native build's). A call of the runtime's is its kind, the instructions it runs
/// inside each of theirs.
let kinds : FixedArray[String] = [
  "struct", "local", "global", "branch", "int", "float", "div", "mem", "field", "call",
  "indirect", "host", "cast", "alloc", "bulk", "other", "free", "rc",
]

///|
const K_STRUCT : Int = 0

///|
const K_LOCAL : Int = 1

///|
const K_GLOBAL : Int = 2

///|
const K_BRANCH : Int = 3

///|
const K_INT : Int = 4

///|
const K_FLOAT : Int = 5

///|
const K_DIV : Int = 6

///|
const K_MEM : Int = 7

///|
const K_CALL : Int = 9

///|
const K_INDIRECT : Int = 10

///|
const K_HOST : Int = 11

///|
const K_ALLOC : Int = 13

///|
const K_BULK : Int = 14

///|
const K_OTHER : Int = 15

///|
const K_FREE : Int = 16

///|
const K_RC : Int = 17

///|
/// The runtime's functions whose calls are a kind of their own, by their name (the name section's)
fn runtime_kind(name : String) -> Int? {
  match name {
    "moonbit.malloc" | "moonbit.malloc_no_grow" | "moonbit.gc.malloc" | "moonbit.gc.malloc_with_prefix" =>
      Some(K_ALLOC)
    "moonbit.free" | "moonbit.gc.free" => Some(K_FREE)
    "moonbit.incref" | "moonbit.incref_n" | "moonbit.decref" => Some(K_RC)
    _ => None
  }
}

///|
/// A numeric instruction's kind (0x45 to 0xc4: no immediates)
fn numeric_kind(op : Int) -> Int {
  match op {
    // i32.div_s/u, rem_s/u; i64's; f32.sqrt, f32.div; f64's
    0x6d | 0x6e | 0x6f | 0x70 | 0x7f | 0x80 | 0x81 | 0x82 | 0x91 | 0x95 | 0x9f | 0xa3 => K_DIV
    // f32 and f64 comparisons
    _ if op >= 0x5b && op <= 0x66 => K_FLOAT
    // f32 and f64 arithmetic
    _ if op >= 0x8b && op <= 0xa6 => K_FLOAT
    // i32.wrap_i64, i64.extend_i32_s/u: integers; every other conversion has a float on a side
    0xa7 | 0xac | 0xad => K_INT
    _ if op >= 0xa8 && op <= 0xbf => K_FLOAT
    _ => K_INT
  }
}

///|
/// One instruction read: its kind, whether it ends a straight run, the function a call, a return_call or a ref.func
/// names (-1 for any other)
priv struct Op {
  mut kind : Int
  mut ends : Bool
  mut target : Int
}

///|
/// The instruction at `r`'s place read past (its immediates too), told in `op`
fn Reader::op(
  self : Reader,
  op : Op,
  imported : Int,
  runtime : Map[Int, Int],
) -> Unit {
  let code = self.byte()
  op.ends = false
  op.target = -1
  op.kind = match code {
    0x00 => {
      op.ends = true
      K_BRANCH
    }
    0x01 => K_STRUCT
    0x02 | 0x03 => {
      self.skip_signed()
      op.ends = true
      K_STRUCT
    }
    0x04 => {
      self.skip_signed()
      op.ends = true
      K_BRANCH
    }
    0x05 | 0x0b => {
      op.ends = true
      K_STRUCT
    }
    0x0c | 0x0d | 0xd5 | 0xd6 => {
      ignore(self.uint())
      op.ends = true
      K_BRANCH
    }
    0x0e => {
      let n = self.uint()
      for _ in 0..=n {
        ignore(self.uint())
      }
      op.ends = true
      K_BRANCH
    }
    0x0f => {
      op.ends = true
      K_BRANCH
    }
    0x10 | 0x12 => {
      let f = self.uint()
      op.target = f
      op.ends = code == 0x12
      if f < imported {
        K_HOST
      } else {
        match runtime.get(f) {
          Some(k) => k
          None => K_CALL
        }
      }
    }
    0x11 | 0x13 => {
      ignore(self.uint())
      ignore(self.uint())
      op.ends = code == 0x13
      K_INDIRECT
    }
    0x14 | 0x15 => {
      ignore(self.uint())
      op.ends = code == 0x15
      K_INDIRECT
    }
    0x1a | 0x1b => K_LOCAL
    0x1c => {
      let n = self.uint()
      for _ in 0..<n {
        let t = self.byte()
        if t != 0x7f && t != 0x7e && t != 0x7d && t != 0x7c && t != 0x70 && t != 0x6f {
          fail("a select of a type this reads not (\{t})")
        }
      }
      K_LOCAL
    }
    0x20 | 0x21 | 0x22 => {
      ignore(self.uint())
      K_LOCAL
    }
    0x23 | 0x24 => {
      ignore(self.uint())
      K_GLOBAL
    }
    0x25 | 0x26 => {
      ignore(self.uint())
      K_OTHER
    }
    _ if code >= 0x28 && code <= 0x3e => {
      self.memarg()
      K_MEM
    }
    0x3f | 0x40 => {
      ignore(self.uint())
      K_OTHER
    }
    0x41 | 0x42 => {
      self.skip_signed()
      K_LOCAL
    }
    0x43 => {
      self.p += 4
      K_LOCAL
    }
    0x44 => {
      self.p += 8
      K_LOCAL
    }
    _ if code >= 0x45 && code <= 0xc4 => numeric_kind(code)
    0xd0 => {
      self.skip_signed()
      K_LOCAL
    }
    0xd1 | 0xd3 | 0xd4 => K_OTHER
    0xd2 => {
      op.target = self.uint()
      K_OTHER
    }
    0xfc =>
      match self.uint() {
        sub if sub <= 7 => K_FLOAT
        8 | 12 | 10 | 14 => {
          ignore(self.uint())
          ignore(self.uint())
          K_BULK
        }
        11 | 17 => {
          ignore(self.uint())
          K_BULK
        }
        9 | 13 | 15 | 16 => {
          ignore(self.uint())
          K_OTHER
        }
        sub => fail("an instruction this reads not: 0xfc \{sub}")
      }
    0xfd => {
      let sub = self.uint()
      if (sub >= 0 && sub <= 11) || sub == 92 || sub == 93 {
        self.memarg()
      } else if sub >= 84 && sub <= 91 {
        self.memarg()
        self.p += 1
      } else if sub == 12 || sub == 13 {
        self.p += 16
      } else if sub >= 21 && sub <= 34 {
        self.p += 1
      } else if sub > 275 || (sub >= 154 && sub <= 255 && reserved_simd(sub)) {
        fail("an instruction this reads not: 0xfd \{sub}")
      }
      simd_kind(sub)
    }
    _ => fail("an instruction this reads not: \{code} (a GC, exceptions' or threads' one?)")
  }
}

///|
/// A memarg passed over: its alignment, with 0x40 a memory's index after it, and its offset
fn Reader::memarg(self : Reader) -> Unit {
  let align = self.uint()
  if (align & 0x40) != 0 {
    ignore(self.uint())
  }
  ignore(self.uint64())
}

///|
fn reserved_simd(sub : Int) -> Bool {
  match sub {
    154 | 162 | 165 | 166 | 175 | 176 | 178 | 179 | 180 | 187 | 194 | 197 | 198 | 207 | 208 | 210 | 211 | 212 | 226 |
    238 => true
    _ => false
  }
}

///|
/// A SIMD instruction's kind (0xfd's), by the lanes it works on as the scalar ones are: a load or a store; f32x4's and
/// f64x2's, and what converts to or from them, float; i32x4's and i64x2's integers; v128's own, i8x16's and i16x8's
/// the rest
fn simd_kind(sub : Int) -> Int {
  match sub {
    _ if sub <= 11 || (sub >= 84 && sub <= 93) => K_MEM
    19 | 20 | 31 | 32 | 33 | 34 | 94 | 95 | 103 | 104 | 105 | 106 | 116 | 117 | 122 | 148 => K_FLOAT
    _ if (sub >= 65 && sub <= 76) ||
      (sub >= 224 && sub <= 255) ||
      (sub >= 257 && sub <= 264) ||
      (sub >= 269 && sub <= 272) => K_FLOAT
    17 | 18 | 27 | 28 | 29 | 30 | 126 | 127 | 267 | 268 | 275 => K_INT
    _ if (sub >= 55 && sub <= 64) || (sub >= 160 && sub <= 223) => K_INT
    _ => K_OTHER
  }
}

///|
/// What profile needs of the module, read first
priv struct Shape {
  mut imported_funcs : Int
  mut imported_globals : Int
  mut defined_globals : Int
  mut memories : Int
  mut has_memory_section : Bool
  func_types : Array[Int]
  type_params : Array[Int]
  mut start : Int
  runtime : Map[Int, Int]
  // the functions counted apart (profile's `apart`), by their index
  apart : Map[Int, Bool]
  // the function whose calls are looked into (profile's `focus`), by its index; -1, none
  mut focus : Int
  // whether it is the `focus`'s callers that are looked into (profile's `callers`), not what it calls
  callers : Bool
}

///|
fn shape(data : Bytes, apart : (String) -> Bool, focus : String, callers : Bool) -> Shape {
  let s : Shape = {
    imported_funcs: 0,
    imported_globals: 0,
    defined_globals: 0,
    memories: 0,
    has_memory_section: false,
    func_types: [],
    type_params: [],
    start: -1,
    runtime: {},
    apart: {},
    focus: -1,
    callers,
  }
  let r = Reader::new(data, 8)
  while r.p < data.length() {
    let id = r.byte()
    let size = r.uint()
    let end = r.p + size
    match id {
      1 => {
        let n = r.uint()
        for _ in 0..<n {
          let form = r.byte()
          if form != 0x60 {
            fail("a type this reads not (\{form}): a GC program's? this counts classic Wasm")
          }
          let np = r.uint()
          for _ in 0..<np {
            value_type(r)
          }
          let nr = r.uint()
          for _ in 0..<nr {
            value_type(r)
          }
          s.type_params.push(np)
        }
      }
      2 => {
        let n = r.uint()
        for _ in 0..<n {
          ignore(r.name())
          ignore(r.name())
          match r.byte() {
            0 => {
              ignore(r.uint())
              s.imported_funcs += 1
            }
            1 => {
              ignore(r.byte())
              r.limits()
            }
            2 => {
              r.limits()
              s.memories += 1
            }
            3 => {
              value_type(r)
              ignore(r.byte())
              s.imported_globals += 1
            }
            k => fail("an import this reads not (\{k})")
          }
        }
      }
      3 => {
        let n = r.uint()
        for _ in 0..<n {
          s.func_types.push(r.uint())
        }
      }
      5 => {
        s.memories += r.uint()
        s.has_memory_section = true
      }
      6 => s.defined_globals = r.uint()
      8 => s.start = r.uint()
      0 =>
        if r.name() == "name" {
          while r.p < end {
            let sub = r.byte()
            let n = r.uint()
            let sub_end = r.p + n
            if sub == 1 {
              let count = r.uint()
              for _ in 0..<count {
                let index = r.uint()
                let name = r.name()
                match runtime_kind(name) {
                  Some(k) => s.runtime[index] = k
                  None => ()
                }
                if apart(name) {
                  s.apart[index] = true
                }
                if focus != "" && focus_is(focus, name) {
                  if s.focus >= 0 {
                    fail("focus=\{focus}: more than one function of that name")
                  }
                  s.focus = index
                }
              }
            }
            r.p = sub_end
          }
        }
      _ => ()
    }
    r.p = end
  }
  s
}

///|
/// A value's type passed over: classic Wasm's, one byte each
fn value_type(r : Reader) -> Unit {
  let t = r.byte()
  if t != 0x7f && t != 0x7e && t != 0x7d && t != 0x7c && t != 0x7b && t != 0x70 && t != 0x6f {
    fail("a value type this reads not (\{t})")
  }
}

///|
/// A constant expression copied (i32/i64.const, global.get, ref.null, ref.func, end), ref.func's target as `wrap` says
fn const_expr(r : Reader, out : @buffer.Buffer, wrap : (Int) -> Int) -> Unit {
  while true {
    let op = r.byte()
    out.write_byte(op.to_byte())
    match op {
      0x0b => return
      0x41 | 0x42 => {
        let s = r.p
        r.skip_signed()
        out.write_bytesview(r.data[s:r.p])
      }
      0x23 => leb_u(out, r.uint().to_int64())
      0xd0 => out.write_byte(r.byte().to_byte())
      0xd2 => leb_u(out, wrap(r.uint()).to_int64())
      _ => fail("a constant expression this reads not (\{op})")
    }
  }
}

///|
/// i64.load at `off` of memory `mi`'s table in use (global `pb`'s address + off)
fn ld(v : @buffer.Buffer, pb : Int, mi : Int, off : Int) -> Unit {
  v.write_byte(b'\x23')
  leb_u(v, pb.to_int64())
  put(v, [0x29, 0x43])
  leb_u(v, mi.to_int64())
  leb_u(v, off.to_int64())
}

///|
/// i64.store at `off` of memory `mi`, its address and value given
fn st(v : @buffer.Buffer, mi : Int, off : Int) -> Unit {
  put(v, [0x37, 0x43])
  leb_u(v, mi.to_int64())
  leb_u(v, off.to_int64())
}

///|
/// memory `mi`'s i64 at `off` of the table in use += n
fn bump(v : @buffer.Buffer, pb : Int, mi : Int, off : Int, n : Int64) -> Unit {
  v.write_byte(b'\x23')
  leb_u(v, pb.to_int64())
  ld(v, pb, mi, off)
  v.write_byte(b'\x42')
  leb_s(v, n)
  v.write_byte(b'\x7c')
  st(v, mi, off)
}

///|
/// global `g` += n: global.get, i64.const, i64.add, global.set
fn counter(v : @buffer.Buffer, g : Int, n : Int64) -> Unit {
  v.write_byte(b'\x23')
  leb_u(v, g.to_int64())
  v.write_byte(b'\x42')
  leb_s(v, n)
  v.write_byte(b'\x7c')
  v.write_byte(b'\x24')
  leb_u(v, g.to_int64())
}

///|
/// `data` made to count what it runs (the head of this file)
fn profile(data : Bytes, apart : (String) -> Bool, focus~ : String = "", callers~ : Bool = false) -> Bytes {
  check_magic(data)
  let s = shape(data, apart, focus, callers)
  if focus != "" && s.focus < 0 {
    fail("focus=\{focus}: no function of that name")
  }
  let imported = s.imported_funcs
  let nd = s.func_types.length()
  let funcs = imported + nd
  let wrap = fn(f : Int) { if f >= imported && f < funcs { funcs + (f - imported) } else { f } }
  let g = s.imported_globals + s.defined_globals
  // ours: __gas at g, each kind's at g + 1 + k, then the table in use's address, __a and __ac; our memory after the
  // others, its two tables in its halves
  let gas = g
  let nk = kinds.length()
  let mi = s.memories
  let half = ((nd * 64 + 65535) / 65536).max(1)
  let mem_entry = Buffer()
  mem_entry.write_byte(b'\x00')
  leb_u(mem_entry, (2 * half).to_int64())
  let globals_entry = Buffer()
  for _ in 0..=nk {
    put(globals_entry, [0x7e, 0x01, 0x42, 0x00, 0x0b])
  }
  put(globals_entry, [0x7f, 0x01, 0x41, 0x00, 0x0b])
  put(globals_entry, [0x7e, 0x01, 0x42, 0x00, 0x0b])
  put(globals_entry, [0x7e, 0x01, 0x42, 0x00, 0x0b])
  // (the defined function running now, for `focus`: its place among them, -1 none)
  put(globals_entry, [0x7f, 0x01, 0x41, 0x7f, 0x0b])
  let out = Buffer()
  out.write_bytesview(data[0:8])
  let mut had_globals = false
  let mut had_memory = false
  let mut had_exports = false
  let memory_section = fn(body : BytesView?) {
    let b = Buffer()
    match body {
      Some(body) => {
        let r = Reader::new(body.to_owned(), 0)
        let n = r.uint()
        leb_u(b, (n + 1).to_int64())
        b.write_bytesview(body[r.p:])
      }
      None => leb_u(b, 1L)
    }
    b.write_bytes(mem_entry.to_bytes())
    section(out, 5, b)
  }
  let r = Reader::new(data, 8)
  while r.p < data.length() {
    let sec_start = r.p
    let id = r.byte()
    let size = r.uint()
    let p = r.p
    let next = p + size
    let body = data[p:next]
    // (our memory where the memories go: in theirs, else before what comes after it)
    if !s.has_memory_section &&
      !had_memory &&
      (id == 13 || id == 6 || id == 7 || id == 8 || id == 9 || id == 12 || id == 10 || id == 11) {
      memory_section(None)
      had_memory = true
    }
    match id {
      3 => {
        let n = r.uint()
        let b = Buffer()
        leb_u(b, (n + nd).to_int64())
        b.write_bytesview(data[r.p:next])
        for t in s.func_types {
          leb_u(b, t.to_int64())
        }
        section(out, 3, b)
      }
      5 => {
        memory_section(Some(body))
        had_memory = true
      }
      6 => {
        had_globals = true
        let n = r.uint()
        let b = Buffer()
        leb_u(b, (n + 5 + nk).to_int64())
        b.write_bytesview(data[r.p:next])
        b.write_bytes(globals_entry.to_bytes())
        section(out, 6, b)
      }
      7 => {
        if !had_globals {
          let b = Buffer()
          leb_u(b, (5 + nk).to_int64())
          b.write_bytes(globals_entry.to_bytes())
          section(out, 6, b)
          had_globals = true
        }
        had_exports = true
        let n = r.uint()
        let b = Buffer()
        leb_u(b, (n + 4 + nk).to_int64())
        for _ in 0..<n {
          let l = r.uint()
          leb_u(b, l.to_int64())
          b.write_bytesview(data[r.p:r.p + l])
          r.p += l
          let kind = r.byte()
          b.write_byte(kind.to_byte())
          let idx = r.uint()
          leb_u(b, (if kind == 0 { wrap(idx) } else { idx }).to_int64())
        }
        let ours = [("__gas", 3, gas), ("__pm", 2, mi)]
        for k in 0..<nk {
          ours.push(("__k\{k}", 3, gas + 1 + k))
        }
        ours.push(("__a", 3, gas + nk + 2))
        ours.push(("__ac", 3, gas + nk + 3))
        for o in ours {
          let (name, kind, idx) = o
          leb_u(b, name.length().to_int64())
          for c in name {
            b.write_byte(c.to_int().to_byte())
          }
          b.write_byte(kind.to_byte())
          leb_u(b, idx.to_int64())
        }
        section(out, 7, b)
      }
      9 => {
        let n = r.uint()
        let b = Buffer()
        leb_u(b, n.to_int64())
        for _ in 0..<n {
          let flags = r.uint()
          leb_u(b, flags.to_int64())
          if (flags & 1) == 0 && (flags & 2) != 0 {
            leb_u(b, r.uint().to_int64())
          }
          if (flags & 1) == 0 {
            const_expr(r, b, wrap)
          }
          if (flags & 3) != 0 {
            b.write_byte(r.byte().to_byte())
          }
          let c = r.uint()
          leb_u(b, c.to_int64())
          for _ in 0..<c {
            if (flags & 4) == 0 {
              leb_u(b, wrap(r.uint()).to_int64())
            } else {
              const_expr(r, b, wrap)
            }
          }
        }
        section(out, 9, b)
      }
      10 => {
        if !had_globals || !had_exports {
          fail("a module with code but no exports section")
        }
        code_section(r, next, s, wrap, gas, nk, half * 65536, out)
      }
      _ => out.write_bytesview(data[sec_start:next])
    }
    r.p = next
  }
  out.to_bytes()
}

///|
/// The code section: each function's runs counted, then the wrappers appended
fn code_section(
  r : Reader,
  next : Int,
  s : Shape,
  wrap : (Int) -> Int,
  gas : Int,
  nk : Int,
  apart_at : Int,
  out : @buffer.Buffer,
) -> Unit {
  let pb = gas + nk + 1
  let data = r.data
  let mi = s.memories
  let imported = s.imported_funcs
  let nd = s.func_types.length()
  let count = r.uint()
  if count != nd {
    fail("the code section has \{count} functions, the function section \{nd}")
  }
  let b = Buffer()
  leb_u(b, (count + nd).to_int64())
  let starts : Array[Int] = []
  let ends : Array[Bool] = []
  let kinds_of : Array[Int] = []
  let targets : Array[Int] = []
  let per = FixedArray::make(nk, 0L)
  let op : Op = { kind: 0, ends: false, target: -1 }
  for fi in 0..<count {
    let size = r.uint()
    let fstart = r.p
    let fend = fstart + size
    if s.start == imported + fi {
      leb_u(b, size.to_int64())
      b.write_bytesview(data[fstart:fend])
      r.p = fend
      continue
    }
    let base = 64 * fi
    // its locals
    let groups = r.uint()
    for _ in 0..<groups {
      ignore(r.uint())
      value_type(r)
    }
    let nb = Buffer()
    nb.write_bytesview(data[fstart:r.p])
    starts.clear()
    ends.clear()
    kinds_of.clear()
    targets.clear()
    while r.p < fend {
      starts.push(r.p)
      r.op(op, imported, s.runtime)
      ends.push(op.ends)
      kinds_of.push(op.kind)
      targets.push(op.target)
    }
    if r.p != fend {
      fail("function \{imported + fi} read past its end")
    }
    let n_ops = starts.length()
    let mut i = 0
    while i < n_ops {
      let mut j = i
      while j < n_ops && !ends[j] {
        j += 1
      }
      let last = if j < n_ops { j } else { n_ops - 1 }
      let n = (last - i + 1).to_int64()
      counter(nb, gas, n)
      bump(nb, pb, mi, base, n)
      for k in 0..<nk {
        per[k] = 0L
      }
      for k in i..=last {
        per[kinds_of[k]] += 1L
      }
      for k in 0..<nk {
        if per[k] > 0L {
          counter(nb, gas + 1 + k, per[k])
        }
      }
      if per[K_ALLOC] > 0L {
        bump(nb, pb, mi, base + 40, per[K_ALLOC])
      }
      for k in i..=last {
        let to = if k + 1 < n_ops { starts[k + 1] } else { fend }
        let t = targets[k]
        if t >= 0 && wrap(t) != t {
          // (call, return_call, ref.func: the wrapper's index for the function's)
          nb.write_byte(data[starts[k]])
          leb_u(nb, wrap(t).to_int64())
        } else {
          nb.write_bytesview(data[starts[k]:to])
        }
      }
      i = last + 1
    }
    leb_u(b, nb.length().to_int64())
    b.write_bytes(nb.to_bytes())
  }
  if r.p != next {
    fail("the code section read past its end")
  }
  // the wrappers: the k-th at funcs + k, counting around the k-th defined function
  for k in 0..<nd {
    let nb = if s.apart.contains(imported + k) {
      apart_wrapper(s, k, gas, nk, pb, apart_at)
    } else if s.focus >= 0 {
      focus_wrapper(s, k, gas, pb, gas + nk + 4, s.focus - imported)
    } else {
      wrapper(s, k, gas, pb)
    }
    leb_u(b, nb.length().to_int64())
    b.write_bytes(nb.to_bytes())
  }
  section(out, 10, b)
}

///|
/// The k-th defined function's wrapper: its call counted, and where its outermost call began and how deep it is, for
/// all run inside its calls
fn wrapper(s : Shape, k : Int, gas : Int, pb : Int) -> @buffer.Buffer {
  let mi = s.memories
  let base = 64 * k
  let incl = base + 8
  let calls = base + 16
  let began = base + 24
  let d = base + 32
  let a_began = base + 48
  let a_incl = base + 56
  // (the allocator's calls so far: the kind's global, KINDS)
  let allocs = gas + 1 + K_ALLOC
  let params = s.type_params[s.func_types[k]]
  let nb = Buffer()
  // no locals
  nb.write_byte(b'\x00')
  bump(nb, pb, mi, calls, 1L)
  // if depth == 0 { began = gas; a_began = allocs }; depth += 1
  ld(nb, pb, mi, d)
  put(nb, [0x50, 0x04, 0x40, 0x23])
  leb_u(nb, pb.to_int64())
  nb.write_byte(b'\x23')
  leb_u(nb, gas.to_int64())
  st(nb, mi, began)
  nb.write_byte(b'\x23')
  leb_u(nb, pb.to_int64())
  nb.write_byte(b'\x23')
  leb_u(nb, allocs.to_int64())
  st(nb, mi, a_began)
  nb.write_byte(b'\x0b')
  bump(nb, pb, mi, d, 1L)
  for a in 0..<params {
    nb.write_byte(b'\x20')
    leb_u(nb, a.to_int64())
  }
  nb.write_byte(b'\x10')
  leb_u(nb, (s.imported_funcs + k).to_int64())
  // depth -= 1; if depth == 0 { incl += gas - began; a_incl += allocs - a_began }
  bump(nb, pb, mi, d, -1L)
  ld(nb, pb, mi, d)
  put(nb, [0x50, 0x04, 0x40, 0x23])
  leb_u(nb, pb.to_int64())
  ld(nb, pb, mi, incl)
  nb.write_byte(b'\x23')
  leb_u(nb, gas.to_int64())
  ld(nb, pb, mi, began)
  put(nb, [0x7d, 0x7c])
  st(nb, mi, incl)
  nb.write_byte(b'\x23')
  leb_u(nb, pb.to_int64())
  ld(nb, pb, mi, a_incl)
  nb.write_byte(b'\x23')
  leb_u(nb, allocs.to_int64())
  ld(nb, pb, mi, a_began)
  put(nb, [0x7d, 0x7c])
  st(nb, mi, a_incl)
  nb.write_byte(b'\x0b')
  nb.write_byte(b'\x0b')
  nb
}

///|
/// Whether a function's `name` is `focus`'s: the same, or with one `*` in it, what is before it the start of the name
/// and what is after it its end (a closure's number changes from build to build: `…GsEC*l439`)
fn focus_is(focus : String, name : String) -> Bool {
  match focus.find("*") {
    None => name == focus
    Some(at) => {
      let head = focus.exact_view(end=at).to_owned()
      let tail = focus.exact_view(start=at + 1).to_owned()
      name.length() >= head.length() + tail.length() &&
      name.has_prefix(head) &&
      name.has_suffix(tail)
    }
  }
}

///|
/// The k-th defined function's wrapper where the calls of the `f`-th (profile's `focus`) are looked into: its call
/// counted, and all run inside it where the `f`-th called it itself (its +8, and the allocator's calls at +56), each
/// call apart; the function running now in global `cur` (its place, as each wrapper sets it around its call). Where it
/// is the `f`-th's callers (profile's `callers`), the `f`-th's wrapper counts that into its caller's +8 and +56 instead,
/// the others nothing there.
fn focus_wrapper(s : Shape, k : Int, gas : Int, pb : Int, cur : Int, f : Int) -> @buffer.Buffer {
  let mi = s.memories
  let base = 64 * k
  let incl = base + 8
  let calls = base + 16
  let a_incl = base + 56
  let allocs = gas + 1 + K_ALLOC
  let params = s.type_params[s.func_types[k]]
  // its locals after its parameters: who called it, __gas and the allocator's calls as it began
  let prev = params
  let began = params + 1
  let a_began = params + 2
  let nb = Buffer()
  put(nb, [0x02, 0x01, 0x7f, 0x02, 0x7e])
  let op = fn(o : Int, i : Int) {
    nb.write_byte(o.to_byte())
    leb_u(nb, i.to_int64())
  }
  bump(nb, pb, mi, calls, 1L)
  op(0x23, cur)
  op(0x21, prev)
  nb.write_byte(b'\x41')
  leb_s(nb, k.to_int64())
  op(0x24, cur)
  op(0x23, gas)
  op(0x21, began)
  op(0x23, allocs)
  op(0x21, a_began)
  for a in 0..<params {
    op(0x20, a)
  }
  op(0x10, s.imported_funcs + k)
  op(0x20, prev)
  op(0x24, cur)
  if s.callers {
    if k == f {
      // if prev >= 0 { prev's incl += gas - began; prev's a_incl += allocs - a_began }
      op(0x20, prev)
      put(nb, [0x41, 0x00, 0x4e, 0x04, 0x40])
      let at_prev = fn() {
        op(0x23, pb)
        op(0x20, prev)
        put(nb, [0x41, 0x06, 0x74, 0x6a])
      }
      at_prev()
      at_prev()
      put(nb, [0x29, 0x43])
      leb_u(nb, mi.to_int64())
      leb_u(nb, 8L)
      op(0x23, gas)
      op(0x20, began)
      put(nb, [0x7d, 0x7c])
      st(nb, mi, 8)
      at_prev()
      at_prev()
      put(nb, [0x29, 0x43])
      leb_u(nb, mi.to_int64())
      leb_u(nb, 56L)
      op(0x23, allocs)
      op(0x20, a_began)
      put(nb, [0x7d, 0x7c])
      st(nb, mi, 56)
      nb.write_byte(b'\x0b')
    }
    nb.write_byte(b'\x0b')
    return nb
  }
  // if prev == f { incl += gas - began; a_incl += allocs - a_began }
  op(0x20, prev)
  nb.write_byte(b'\x41')
  leb_s(nb, f.to_int64())
  put(nb, [0x46, 0x04, 0x40])
  op(0x23, pb)
  ld(nb, pb, mi, incl)
  op(0x23, gas)
  op(0x20, began)
  put(nb, [0x7d, 0x7c])
  st(nb, mi, incl)
  op(0x23, pb)
  ld(nb, pb, mi, a_incl)
  op(0x23, allocs)
  op(0x20, a_began)
  put(nb, [0x7d, 0x7c])
  st(nb, mi, a_incl)
  nb.write_byte(b'\x0b')
  nb.write_byte(b'\x0b')
  nb
}

///|
/// The wrapper of a function counted apart (profile's `apart`: a test's own, its stand-in for the host or its driver's
/// looking): each of its calls one call of the host's, its own, all inside it and its calls one each in
/// the table in use; what it runs inside counted in `__a` (its calls in `__ac`) and the other table, the counts as
/// they were before it (its calls in `__ac` where the app made them, not one of those)
fn apart_wrapper(s : Shape, k : Int, gas : Int, nk : Int, pb : Int, apart_at : Int) -> @buffer.Buffer {
  let mi = s.memories
  let base = 64 * k
  let params = s.type_params[s.func_types[k]]
  // its locals after its parameters: the table in use's address, then __gas and each kind's as they were
  let at = params
  let was = params + 1
  let nb = Buffer()
  put(nb, [0x02, 0x01, 0x7f])
  leb_u(nb, (1 + nk).to_int64())
  nb.write_byte(b'\x7e')
  bump(nb, pb, mi, base, 1L)
  bump(nb, pb, mi, base + 8, 1L)
  bump(nb, pb, mi, base + 16, 1L)
  let get = fn(op : Int, i : Int) {
    nb.write_byte(op.to_byte())
    leb_u(nb, i.to_int64())
  }
  get(0x23, pb)
  get(0x21, at)
  for i in 0..=nk {
    get(0x23, gas + i)
    get(0x21, was + i)
  }
  nb.write_byte(b'\x41')
  leb_s(nb, apart_at.to_int64())
  get(0x24, pb)
  for a in 0..<params {
    get(0x20, a)
  }
  get(0x10, s.imported_funcs + k)
  // __a += gas - gas before; __ac += 1
  get(0x23, gas + nk + 2)
  get(0x23, gas)
  get(0x20, was)
  put(nb, [0x7d, 0x7c])
  get(0x24, gas + nk + 2)
  // (a call of the host's from the app: one of them inside another, its own)
  get(0x20, at)
  put(nb, [0x45, 0x04, 0x40])
  counter(nb, gas + nk + 3, 1L)
  nb.write_byte(b'\x0b')
  // __gas and the kinds as they were, the host's one more
  for i in 0..=nk {
    get(0x20, was + i)
    if i == 0 || i == 1 + K_HOST {
      put(nb, [0x42, 0x01, 0x7c])
    }
    get(0x24, gas + i)
  }
  get(0x20, at)
  get(0x24, pb)
  nb.write_byte(b'\x0b')
  nb
}
