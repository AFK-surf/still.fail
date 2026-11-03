// MoonBit's classic Wasm linker puts every package's initializers in the start function. For the app this can have
// tens of thousands of locals, although very few are live at once; V8 then spends seconds and many GiB preparing it.
// Reuse same-typed locals whose lifetimes cannot overlap. No application code, data or other function is changed.
// Unsupported instruction encodings fail closed: a new compiler feature must not silently change a picture.
export function compactStart(data) {
  if (!Buffer.isBuffer(data)) data = Buffer.from(data);
  if (data.length < 8 || !data.subarray(0, 8).equals(Buffer.from([0, 97, 115, 109, 1, 0, 0, 0]))) {
    throw new Error('not a classic Wasm module');
  }
  let p = 8;
  let imported = 0;
  let start = -1;
  let code;
  function uint() {
    let value = 0;
    let shift = 0;
    for (let n = 0; n < 5; n++) {
      if (p >= data.length) throw new Error('truncated Wasm integer');
      const c = data[p++];
      value += (c & 127) * 2 ** shift;
      if (!(c & 128)) {
        if (value > 0xffffffff) throw new Error('Wasm integer is too large');
        return value;
      }
      shift += 7;
    }
    throw new Error('invalid Wasm integer');
  }
  function skipSigned() {
    for (let n = 0; n < 10; n++) {
      if (p >= data.length) throw new Error('truncated Wasm integer');
      if (!(data[p++] & 128)) return;
    }
    throw new Error('invalid signed Wasm integer');
  }
  function name() {
    const n = uint();
    p += n;
    if (p > data.length) throw new Error('truncated Wasm name');
  }
  function limits() {
    const flags = uint();
    if (flags & ~1) throw new Error('unsupported Wasm limits');
    uint();
    if (flags & 1) uint();
  }
  while (p < data.length) {
    const sectionStart = p;
    const type = data[p++];
    const size = uint();
    const payload = p;
    const end = p + size;
    if (end > data.length) throw new Error('truncated Wasm section');
    if (type === 2) {
      const count = uint();
      for (let i = 0; i < count; i++) {
        name(); name();
        const kind = data[p++];
        if (kind === 0) { uint(); imported++; }
        else if (kind === 1) { p++; limits(); }
        else if (kind === 2) limits();
        else if (kind === 3) p += 2;
        else throw new Error(`unsupported Wasm import ${kind}`);
      }
    } else if (type === 8) {
      start = uint();
    } else if (type === 10) {
      code = { sectionStart, payload, end };
    }
    if (p > end) throw new Error('invalid Wasm section');
    p = end;
  }
  if (!code || start < imported) throw new Error('Wasm has no local start function');
  p = code.payload;
  const count = uint();
  const codePrefixEnd = p;
  let target;
  for (let i = 0; i < count; i++) {
    const sizeAt = p;
    const size = uint();
    const body = p;
    const end = body + size;
    if (end > code.end) throw new Error('truncated Wasm function');
    if (i + imported === start) target = { sizeAt, body, end };
    p = end;
  }
  if (!target || p !== code.end) throw new Error('invalid Wasm start function');
  p = target.body;
  const groups = uint();
  const types = [];
  for (let i = 0; i < groups; i++) {
    const n = uint();
    const type = data[p++];
    if (![0x7f, 0x7e, 0x7d, 0x7c].includes(type)) throw new Error('unsupported Wasm local type');
    if (types.length + n > 1_000_000) throw new Error('too many Wasm locals');
    for (let j = 0; j < n; j++) types.push(type);
  }
  const instructions = p;
  const uses = types.map(() => null);
  const refs = [];
  // A scope is the body of a block, a loop, or one arm of an if. A branch can leave one, never enter it midway.
  const scopes = [{ parent: -1, start: instructions, end: target.end }];
  const frames = [];
  const loops = [];
  let scope = 0;
  function isAncestor(ancestor, child) {
    while (child !== ancestor && child > 0) child = scopes[child].parent;
    return child === ancestor;
  }
  function childScope(parent, at) {
    const id = scopes.length;
    scopes.push({ parent, start: at, end: -1 });
    return id;
  }
  let ended = false;
  while (p < target.end) {
    const at = p;
    const op = data[p++];
    if (op >= 0x20 && op <= 0x22) {
      const pos = p;
      const id = uint();
      if (id >= uses.length) throw new Error('invalid Wasm local index');
      let use = uses[id];
      if (!use) {
        use = { first: at, last: at, op, scope, within: true, loops: new Set() };
        uses[id] = use;
      } else {
        use.last = at;
        if (!isAncestor(use.scope, scope)) use.within = false;
      }
      if (loops.length) use.loops.add(loops[0]);
      refs.push({ pos, end: p, id });
    } else if (op === 0x02 || op === 0x03 || op === 0x04) {
      skipSigned();
      const parent = scope;
      scope = childScope(parent, at);
      frames.push({ op, parent });
      if (op === 0x03) loops.push(scope);
    } else if (op === 0x05) {
      const frame = frames.at(-1);
      if (!frame || frame.op !== 0x04) throw new Error('unexpected Wasm else');
      scopes[scope].end = at;
      scope = childScope(frame.parent, at);
    } else if (op === 0x0b) {
      if (!frames.length) { ended = p === target.end; break; }
      const frame = frames.pop();
      scopes[scope].end = at;
      if (frame.op === 0x03 && loops.pop() !== scope) throw new Error('invalid Wasm loop');
      scope = frame.parent;
    } else if (op === 0x0c || op === 0x0d || op === 0x10 || op === 0x12 ||
               op === 0x23 || op === 0x24 || op === 0x25 || op === 0x26 ||
               op === 0xd2 || op === 0xd5 || op === 0xd6) {
      uint();
    } else if (op === 0x0e) {
      const n = uint();
      for (let i = 0; i < n; i++) uint();
      uint();
    } else if (op === 0x11 || op === 0x13) {
      uint(); uint();
    } else if (op === 0x1c) {
      const n = uint();
      for (let i = 0; i < n; i++) {
        if (![0x7f, 0x7e, 0x7d, 0x7c, 0x70, 0x6f].includes(data[p++])) throw new Error('unsupported select type');
      }
    } else if (op >= 0x28 && op <= 0x3e) {
      uint(); uint();
    } else if (op === 0x3f || op === 0x40) {
      uint();
    } else if (op === 0x41 || op === 0x42 || op === 0xd0) {
      skipSigned();
    } else if (op === 0x43) p += 4;
    else if (op === 0x44) p += 8;
    else if (op === 0xfc) {
      const sub = uint();
      if (sub === 8 || sub === 10 || sub === 12 || sub === 14) { uint(); uint(); }
      else if (sub === 9 || sub === 11 || sub === 13 || sub === 15 || sub === 16 || sub === 17) uint();
      else if (sub > 7) throw new Error(`unsupported Wasm instruction fc ${sub}`);
    } else if (!(op === 0x00 || op === 0x01 || op === 0x0f || op === 0x1a || op === 0x1b ||
                 op === 0xd1 || (op >= 0x45 && op <= 0xc4))) {
      throw new Error(`unsupported Wasm instruction ${op.toString(16)}`);
    }
    if (p > target.end) throw new Error('truncated Wasm instruction');
  }
  if (!ended || frames.length) throw new Error('invalid Wasm start body');
  // A local is eligible only if its first use writes it, and every later use stays in that same scope or its children.
  // Thus every path to a read passes its first write. A loop touched by the local expands its lifetime to the entire
  // loop: a later iteration must never see another local's value. Everything else keeps a private slot.
  const byType = new Map();
  for (let i = 0; i < types.length; i++) {
    const type = types[i];
    if (!byType.has(type)) byType.set(type, { reserved: [], shared: [], colors: 0 });
    const group = byType.get(type);
    const use = uses[i];
    if (!use) continue;
    if (!use.within || use.op === 0x20) { group.reserved.push(i); continue; }
    for (const id of use.loops) {
      use.first = Math.min(use.first, scopes[id].start);
      use.last = Math.max(use.last, scopes[id].end);
    }
    group.shared.push(i);
  }
  for (const group of byType.values()) {
    group.shared.sort((a, b) => uses[a].first - uses[b].first);
    const ends = [];
    for (const id of group.shared) {
      let color = ends.findIndex(end => end < uses[id].first);
      if (color < 0) color = ends.length;
      ends[color] = uses[id].last;
      uses[id].color = color;
    }
    group.colors = ends.length;
  }
  let next = 0;
  const remap = new Array(types.length);
  const declarations = [];
  for (const [type, group] of byType) {
    const base = next;
    for (const id of group.reserved) remap[id] = next++;
    const shared = next;
    next += group.colors;
    for (const id of group.shared) remap[id] = shared + uses[id].color;
    if (next > base) declarations.push({ type, count: next - base });
  }
  function leb(n) {
    const a = [];
    do {
      let c = n % 128;
      n = Math.floor(n / 128);
      if (n) c |= 128;
      a.push(c);
    } while (n);
    return Buffer.from(a);
  }
  const chunks = [leb(declarations.length)];
  for (const group of declarations) chunks.push(leb(group.count), Buffer.from([group.type]));
  let cursor = instructions;
  for (const ref of refs) {
    chunks.push(data.subarray(cursor, ref.pos), leb(remap[ref.id]));
    cursor = ref.end;
  }
  chunks.push(data.subarray(cursor, target.end));
  const body = Buffer.concat(chunks);
  const payload = Buffer.concat([
    data.subarray(code.payload, codePrefixEnd), data.subarray(codePrefixEnd, target.sizeAt),
    leb(body.length), body, data.subarray(target.end, code.end),
  ]);
  return Buffer.concat([data.subarray(0, code.sectionStart), Buffer.from([10]), leb(payload.length), payload, data.subarray(code.end)]);
}
