// Built by libs/base/build.sh from libs/base/src (MoonBit): not to be edited, built again.
function _M0TPC16string10StringView(param0, param1, param2) {
  this.str = param0;
  this.start = param1;
  this.end = param2;
}
function $oob() {
  throw new Error("Index out of bounds");
}
class $PanicError extends Error {}
function $panic(message) {
  throw new $PanicError(message);
}
function _M0TPB13StringBuilder(param0) {
  this.val = param0;
}
const _M0FPB19int__to__string__js = (x, radix) => {
  return x.toString(radix);
};
function $make_array_len_and_init(a, b) {
  const arr = new Array(a);
  arr.fill(b);
  return arr;
}
function $makebytes(a, b) {
  const arr = new Uint8Array(a);
  if (b !== 0) {
    arr.fill(b);
  }
  return arr;
}
const _M0FPB22js__code__unit__string = (c) => String.fromCharCode(c);
const _M0FPB13js__index__of = (s, start, end, p) => {
  if (end - start < p.length) return -1;
  if (end === s.length) return s.indexOf(p, start);
  const i = s.substring(start, end).indexOf(p);
  return i < 0 ? i : start + i;
};
const _M0FPB13js__substring = (s, start, end) => start === 0 && end === s.length ? s : s.substring(start, end);
function _M0TPC15bytes9BytesView(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGsE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
const _M0FPC28encoding4utf823decode__utf8__lossy__js = ((preserveBOMDecoder, dropBOMDecoder) => function(bytes, start, len, preserveBOM) {
   const end = start + len;
   const slice = bytes.subarray(start, end);
   const decoder = preserveBOM ? preserveBOMDecoder : dropBOMDecoder;
   return decoder.decode(slice);
 })(
   new TextDecoder("utf-8", { ignoreBOM: true }),
   new TextDecoder("utf-8", { ignoreBOM: false }),
 );
const _M0FP24base4wire3put = (to, at, chunk) => {
  if (chunk.indexOf(13) < 0) {
    to.set(chunk, at);
    return at + chunk.length;
  }
  for (let i = 0; i < chunk.length; i++) if (chunk[i] !== 13) to[at++] = chunk[i];
  return at;
};
const _M0FP24base4wire5moved = (to, from, start, end) => {
  if (to === from) to.copyWithin(0, start, end);
  else to.set(from.subarray(start, end));
};
const _M0FP24base4wire7newline = (held, from, end) => held.subarray(0, end).indexOf(10, from);
function _M0TP24base4wire3Sse(param0, param1, param2, param3) {
  this.held = param0;
  this.start = param1;
  this.end = param2;
  this.looked = param3;
}
function _M0TPB5ArrayGsE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TP24base4wire5Event(param0, param1, param2) {
  this.name = param0;
  this.data = param1;
  this.id = param2;
}
function _M0TPB5ArrayGRP24base4wire5EventE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
const _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger = { method_0: _M0IPB13StringBuilderPB6Logger13write__string, method_1: _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE, method_2: _M0IPB13StringBuilderPB6Logger11write__view, method_3: _M0IPB13StringBuilderPB6Logger11write__char, method_4: _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE, method_5: _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE };
const _M0MPC16string10StringView4findN6constrS227 = 0;
const _M0FP24base4wire9event__ofN6recordS311 = new _M0TPC16string10StringView("data:", 0, 5);
const _M0FP24base4wire9event__ofN6recordS312 = new _M0TPC16string10StringView("event:", 0, 6);
const _M0FP24base4wire9event__ofN6recordS313 = new _M0TPC16string10StringView("id:", 0, 3);
const _M0FP24base4wire9event__ofN6recordS314 = new _M0TPC16string10StringView("\n", 0, 1);
const _M0FP24base4wire9event__ofN6recordS315 = new _M0TPC16string10StringView("\n", 0, 1);
function _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGsEE(dst, dst_offset, src, src_offset, len) {
  if (dst === src && dst_offset < src_offset) {
    let _tmp = 0;
    while (true) {
      const i = _tmp;
      if (i < len) {
        const _tmp$2 = dst_offset + i | 0;
        const _tmp$3 = src_offset + i | 0;
        if (_tmp$2 >>> 0 < dst.length) {
          dst[_tmp$2] = _tmp$3 >>> 0 < src.length ? src[_tmp$3] : $oob();
        } else {
          $oob();
        }
        _tmp = i + 1 | 0;
        continue;
      } else {
        return;
      }
    }
  } else {
    let _tmp = len - 1 | 0;
    let _tmp$2 = len > 0;
    while (true) {
      const i = _tmp;
      const _more = _tmp$2;
      if (_more) {
        const _tmp$3 = dst_offset + i | 0;
        const _tmp$4 = src_offset + i | 0;
        if (_tmp$3 >>> 0 < dst.length) {
          dst[_tmp$3] = _tmp$4 >>> 0 < src.length ? src[_tmp$4] : $oob();
        } else {
          $oob();
        }
        _tmp = i - 1 | 0;
        _tmp$2 = i > 0;
        continue;
      } else {
        return;
      }
    }
  }
}
function _M0MPB18UninitializedArray12unsafe__blitGRP24base4wire5EventE(dst, dst_offset, src, src_offset, len) {
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGsEE(dst, dst_offset, src, src_offset, len);
}
function _M0MPB18UninitializedArray23unsafe__make__and__blitGRP24base4wire5EventE(src, allocate_len, src_offset, dst_offset, blit_len) {
  const dst = new Array(allocate_len);
  _M0MPB18UninitializedArray12unsafe__blitGRP24base4wire5EventE(dst, dst_offset, src, src_offset, blit_len);
  return dst;
}
function _M0MPB13StringBuilder13write__objectGiE(self, obj) {
  _M0IP016_24default__implPB4Show6outputGiE(obj, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0MPB18UninitializedArray23make__and__blit_2einnerGRP24base4wire5EventE(src, allocate_len, len, src_offset, dst_offset) {
  let _tmp;
  if (allocate_len >= 0) {
    let _tmp$2;
    if (len >= 0) {
      let _tmp$3;
      const _p = src.length;
      if (src_offset >= 0 && src_offset <= (_p - len | 0)) {
        _tmp$3 = dst_offset >= 0 && dst_offset <= (allocate_len - len | 0);
      } else {
        _tmp$3 = false;
      }
      _tmp$2 = _tmp$3;
    } else {
      _tmp$2 = false;
    }
    _tmp = _tmp$2;
  } else {
    _tmp = false;
  }
  if (_tmp) {
    return _M0MPB18UninitializedArray23unsafe__make__and__blitGRP24base4wire5EventE(src, allocate_len, src_offset, dst_offset, len);
  } else {
    const _string_builder = _M0MPB13StringBuilder21StringBuilder_2einner(89);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, "bounds check failed: allocate_len = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, allocate_len);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, ", src_offset = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src_offset);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, ", dst_offset = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, dst_offset);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, ", len = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, len);
    _M0IPB13StringBuilderPB6Logger13write__string(_string_builder, ", src.length = ");
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src.length);
    return $panic(_string_builder.val);
  }
}
function _M0MPB13StringBuilder21StringBuilder_2einner(size_hint) {
  return size_hint >= 0 ? new _M0TPB13StringBuilder("") : $panic("size_hint must be non-negative");
}
function _M0IPB13StringBuilderPB6Logger11write__char(self, ch) {
  self.val = `${self.val}${String.fromCodePoint(ch)}`;
}
function _M0IPB13StringBuilderPB6Logger13write__string(self, str) {
  self.val = `${self.val}${str}`;
}
function _M0MPC16string10StringView21clamped__view_2einner(self, start, end) {
  const len = self.end - self.start | 0;
  const str = self.str;
  const base = self.start;
  let lo;
  if (start <= 0) {
    lo = 0;
  } else {
    if (start >= len) {
      lo = len;
    } else {
      let _tmp;
      const _p = str.charCodeAt(base + start | 0);
      if (_p >= 56320 && _p <= 57343) {
        const _p$2 = str.charCodeAt((base + start | 0) - 1 | 0);
        _tmp = _p$2 >= 55296 && _p$2 <= 56319;
      } else {
        _tmp = false;
      }
      if (_tmp) {
        lo = start + 1 | 0;
      } else {
        lo = start;
      }
    }
  }
  let hi;
  if (end === undefined) {
    hi = len;
  } else {
    const _Some = end;
    const _e = _Some;
    if (_e <= 0) {
      hi = 0;
    } else {
      if (_e >= len) {
        hi = len;
      } else {
        let _tmp;
        const _p = str.charCodeAt(base + _e | 0);
        if (_p >= 56320 && _p <= 57343) {
          const _p$2 = str.charCodeAt((base + _e | 0) - 1 | 0);
          _tmp = _p$2 >= 55296 && _p$2 <= 56319;
        } else {
          _tmp = false;
        }
        if (_tmp) {
          hi = _e - 1 | 0;
        } else {
          hi = _e;
        }
      }
    }
  }
  return lo >= hi ? new _M0TPC16string10StringView(str, base + lo | 0, base + lo | 0) : new _M0TPC16string10StringView(str, base + lo | 0, base + hi | 0);
}
function _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE(self, show) {
  show.method_table.method_0(show.self, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE(self, show) {
  show.method_table.method_0(show.self, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0MPC16string6String21clamped__view_2einner(self, start, end) {
  const len = self.length;
  let lo;
  if (start <= 0) {
    lo = 0;
  } else {
    if (start >= len) {
      lo = len;
    } else {
      let _tmp;
      const _p = self.charCodeAt(start);
      if (_p >= 56320 && _p <= 57343) {
        const _p$2 = self.charCodeAt(start - 1 | 0);
        _tmp = _p$2 >= 55296 && _p$2 <= 56319;
      } else {
        _tmp = false;
      }
      if (_tmp) {
        lo = start + 1 | 0;
      } else {
        lo = start;
      }
    }
  }
  let hi;
  if (end === undefined) {
    hi = len;
  } else {
    const _Some = end;
    const _e = _Some;
    if (_e <= 0) {
      hi = 0;
    } else {
      if (_e >= len) {
        hi = len;
      } else {
        let _tmp;
        const _p = self.charCodeAt(_e);
        if (_p >= 56320 && _p <= 57343) {
          const _p$2 = self.charCodeAt(_e - 1 | 0);
          _tmp = _p$2 >= 55296 && _p$2 <= 56319;
        } else {
          _tmp = false;
        }
        if (_tmp) {
          hi = _e - 1 | 0;
        } else {
          hi = _e;
        }
      }
    }
  }
  return lo >= hi ? new _M0TPC16string10StringView(self, lo, lo) : new _M0TPC16string10StringView(self, lo, hi);
}
function _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(self, value, start, len) {
  _M0IPB13StringBuilderPB6Logger11write__view(self, _M0MPC16string6String21clamped__view_2einner(value, start, start + len | 0));
}
function _M0IP016_24default__implPB4Show6outputGiE(self, logger) {
  logger.method_table.method_0(logger.self, _M0IPC13int3IntPB4Show10to__string(self));
}
function _M0MPC13int3Int18to__string_2einner(self, radix) {
  return _M0FPB19int__to__string__js(self, radix);
}
function _M0MPC15array10FixedArray5makeiGAsE(length, value) {
  if (length <= 0) {
    return [];
  } else {
    const array = $make_array_len_and_init(length, value(0));
    let _tmp = 1;
    while (true) {
      const i = _tmp;
      if (i < length) {
        if (i >>> 0 < array.length) {
          array[i] = value(i);
        } else {
          $oob();
        }
        _tmp = i + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    return array;
  }
}
function _M0MPC16string10StringView9to__owned(self) {
  return self.str.substring(self.start, self.end);
}
function _M0MPC16string6String20unsafe__range__equal(self, start, other, other_start, len) {
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < len) {
      if (self.charCodeAt(start + i | 0) === other.charCodeAt(other_start + i | 0)) {
      } else {
        return false;
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return true;
}
function _M0IPB13StringBuilderPB6Logger11write__view(self, str) {
  self.val = `${self.val}${_M0MPC16string10StringView9to__owned(str)}`;
}
function _M0FPB24find__code__unit__scalar(data, start, end, code) {
  let _tmp = start;
  while (true) {
    const pos = _tmp;
    if (pos < end) {
      if (data.charCodeAt(pos) === code) {
        return pos;
      }
      _tmp = pos + 1 | 0;
      continue;
    } else {
      return -1;
    }
  }
}
function _M0FPB30find__code__unit__from__string(data, start, end, code) {
  return (end - start | 0) <= 8 ? _M0FPB24find__code__unit__scalar(data, start, end, code) : _M0FPB13js__index__of(data, start, end, _M0FPB22js__code__unit__string(code));
}
function _M0FPB28find__code__unit__from__view(target, start, end, code) {
  const target_start = target.start;
  const found = _M0FPB30find__code__unit__from__string(target.str, target_start + start | 0, target_start + end | 0, code);
  return found < 0 ? -1 : found - target_start | 0;
}
function _M0FPB19kmp__failure__table(pattern) {
  const m = pattern.end - pattern.start | 0;
  const table = $make_array_len_and_init(m, 0);
  let k = 0;
  let _tmp = 1;
  while (true) {
    const i = _tmp;
    if (i < m) {
      const c = pattern.str.charCodeAt(pattern.start + i | 0);
      while (true) {
        if (k > 0 && c !== pattern.str.charCodeAt(pattern.start + k | 0)) {
          const _tmp$2 = k - 1 | 0;
          k = _tmp$2 >>> 0 < table.length ? table[_tmp$2] : $oob();
          continue;
        } else {
          break;
        }
      }
      if (c === pattern.str.charCodeAt(pattern.start + k | 0)) {
        k = k + 1 | 0;
      }
      if (i >>> 0 < table.length) {
        table[i] = k;
      } else {
        $oob();
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return table;
}
function _M0FPB24find__pattern__kmp__from(target, pattern, start) {
  const n = target.end - target.start | 0;
  const m = pattern.end - pattern.start | 0;
  const table = _M0FPB19kmp__failure__table(pattern);
  let k = 0;
  let _tmp = start;
  while (true) {
    const i = _tmp;
    if (i < n) {
      const c = target.str.charCodeAt(target.start + i | 0);
      while (true) {
        if (k > 0 && c !== pattern.str.charCodeAt(pattern.start + k | 0)) {
          const _tmp$2 = k - 1 | 0;
          k = _tmp$2 >>> 0 < table.length ? table[_tmp$2] : $oob();
          continue;
        } else {
          break;
        }
      }
      if (c === pattern.str.charCodeAt(pattern.start + k | 0)) {
        k = k + 1 | 0;
      }
      if (k === m) {
        return (i - m | 0) + 1 | 0;
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return undefined;
}
function _M0FPB36find__two__anchor__candidate__scalar(data, start, candidate_end, first, last_offset, last) {
  let _tmp = start;
  while (true) {
    const pos = _tmp;
    if (pos < candidate_end) {
      if (data.charCodeAt(pos) === first && data.charCodeAt(pos + last_offset | 0) === last) {
        return pos;
      }
      _tmp = pos + 1 | 0;
      continue;
    } else {
      return -1;
    }
  }
}
function _M0FPB42find__two__anchor__candidate__from__string(data, start, candidate_end, first, last_offset, last) {
  return _M0FPB36find__two__anchor__candidate__scalar(data, start, candidate_end, first, last_offset, last);
}
function _M0FPB21string__ranges__equal(left, left_start, right, right_start, length) {
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < length) {
      if (left.charCodeAt(left_start + i | 0) !== right.charCodeAt(right_start + i | 0)) {
        return false;
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return true;
}
function _M0FPB22find__by__two__anchors(target, pattern) {
  const target_len = target.end - target.start | 0;
  const pattern_len = pattern.end - pattern.start | 0;
  const target_start = target.start;
  const pattern_start = pattern.start;
  const last_offset = pattern_len - 1 | 0;
  const candidate_end = ((target_start + target_len | 0) - pattern_len | 0) + 1 | 0;
  const first = pattern.str.charCodeAt(pattern.start);
  const last = pattern.str.charCodeAt(pattern.start + last_offset | 0);
  const middle_len = last_offset - 1 | 0;
  let _tmp = target_start;
  let _tmp$2 = 0;
  while (true) {
    const pos = _tmp;
    const failures = _tmp$2;
    if (pos < candidate_end) {
      const found = _M0FPB42find__two__anchor__candidate__from__string(target.str, pos, candidate_end, first, last_offset, last);
      if (found < 0) {
        return undefined;
      }
      if (_M0FPB21string__ranges__equal(target.str, found + 1 | 0, pattern.str, pattern_start + 1 | 0, middle_len)) {
        return found - target_start | 0;
      }
      const failures$2 = failures + 1 | 0;
      const scanned = found - target_start | 0;
      if (failures$2 > 64 || failures$2 > (4 + (scanned / 8 | 0) | 0)) {
        return _M0FPB24find__pattern__kmp__from(target, pattern, scanned + 1 | 0);
      }
      _tmp = found + 1 | 0;
      _tmp$2 = failures$2;
      continue;
    } else {
      return undefined;
    }
  }
}
function _M0FPB13find__pattern(target, pattern) {
  if ((pattern.end - pattern.start | 0) <= 250) {
    const target_start = target.start;
    const pattern_start = pattern.start;
    const found = _M0FPB13js__index__of(target.str, target_start, target_start + (target.end - target.start | 0) | 0, _M0FPB13js__substring(pattern.str, pattern_start, pattern_start + (pattern.end - pattern.start | 0) | 0));
    return found < 0 ? undefined : found - target_start | 0;
  } else {
    return _M0FPB22find__by__two__anchors(target, pattern);
  }
}
function _M0MPC16string10StringView4find(self, str) {
  const pattern_len = str.end - str.start | 0;
  switch (pattern_len) {
    case 0: {
      return _M0MPC16string10StringView4findN6constrS227;
    }
    case 1: {
      const found = _M0FPB28find__code__unit__from__view(self, 0, self.end - self.start | 0, str.str.charCodeAt(str.start));
      return found < 0 ? undefined : found;
    }
    default: {
      return pattern_len > (self.end - self.start | 0) ? undefined : _M0FPB13find__pattern(self, str);
    }
  }
}
function _M0MPC16string10StringView11has__prefix(self, str) {
  const str_len = str.end - str.start | 0;
  return str_len <= (self.end - self.start | 0) ? (str_len === 0 || self.str.charCodeAt(self.start) === str.str.charCodeAt(str.start) ? _M0MPC16string6String20unsafe__range__equal(self.str, self.start, str.str, str.start, str_len) : false) : false;
}
function _M0FPB23array__growth__capacity(current, len, required) {
  if (required < len) {
    $panic("Array capacity overflow");
  }
  const start = current === 0 ? 8 : current;
  let _tmp = start;
  while (true) {
    const space = _tmp;
    if (space < required) {
      const next = Math.imul(space, 2) | 0;
      if (next <= space) {
        return required;
      }
      _tmp = next;
      continue;
    } else {
      return space;
    }
  }
}
function _M0MPC15array5Array8capacityGRP24base4wire5EventE(self) {
  return self.buf.length;
}
function _M0MPC15array5Array14resize__bufferGRP24base4wire5EventE(self, new_capacity) {
  const old_buf = self.buf;
  self.buf = [];
  const len = self.len;
  const copy_len = len < new_capacity ? len : new_capacity;
  const new_buf = _M0MPB18UninitializedArray23make__and__blit_2einnerGRP24base4wire5EventE(old_buf, new_capacity, copy_len, 0, 0);
  self.buf = new_buf;
}
function _M0MPC15array5Array7reallocGRP24base4wire5EventE(self, required) {
  const old_cap = _M0MPC15array5Array8capacityGRP24base4wire5EventE(self);
  const new_cap = _M0FPB23array__growth__capacity(old_cap, self.len, required);
  _M0MPC15array5Array14resize__bufferGRP24base4wire5EventE(self, new_cap);
}
function _M0MPC15array5Array4pushGRP24base4wire5EventE(self, value) {
  if (self.len === self.buf.length) {
    _M0MPC15array5Array7reallocGRP24base4wire5EventE(self, self.len + 1 | 0);
  }
  const length = self.len;
  self.buf[length] = value;
  self.len = length + 1 | 0;
}
function _M0IPC16string6StringPB12ToStringView16to__string__view(self) {
  return new _M0TPC16string10StringView(self, 0, self.length);
}
function _M0FPB19join__string__viewsGsE(parts, separator) {
  if ((parts.end - parts.start | 0) === 0) {
    return "";
  } else {
    if ((parts.end - parts.start | 0) === 1) {
      const _one = parts.buf[parts.start];
      return _M0MPC16string10StringView9to__owned(_M0IPC16string6StringPB12ToStringView16to__string__view(_one));
    } else {
      const _first = parts.buf[parts.start];
      const _x_buf = parts.buf;
      const _x_start = 1 + parts.start | 0;
      const _x_end = parts.end;
      const separator$2 = _M0MPC16string10StringView9to__owned(separator);
      let result = _M0MPC16string10StringView9to__owned(_M0IPC16string6StringPB12ToStringView16to__string__view(_first));
      const _bind = _x_end - _x_start | 0;
      let _tmp = 0;
      while (true) {
        const _ = _tmp;
        if (_ < _bind) {
          const part = _x_buf[_x_start + _ | 0];
          result = `${result}${separator$2}`;
          result = `${result}${_M0MPC16string10StringView9to__owned(_M0IPC16string6StringPB12ToStringView16to__string__view(part))}`;
          _tmp = _ + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      return result;
    }
  }
}
function _M0IPC13int3IntPB4Show10to__string(self) {
  return _M0MPC13int3Int18to__string_2einner(self, 10);
}
function _M0MPC15array9ArrayView4joinGsE(self, separator) {
  return _M0FPB19join__string__viewsGsE(self, separator);
}
function _M0MPC15bytes5Bytes21clamped__view_2einner(self, start, end) {
  const len = self.length;
  const lo = start < 0 ? 0 : start > len ? len : start;
  let hi;
  if (end === undefined) {
    hi = len;
  } else {
    const _Some = end;
    const _end = _Some;
    hi = _end < 0 ? 0 : _end > len ? len : _end;
  }
  const hi$2 = hi > lo ? hi : lo;
  return new _M0TPC15bytes9BytesView(self, lo, hi$2);
}
function _M0MPC15array5Array4joinGsE(self, separator) {
  return _M0MPC15array9ArrayView4joinGsE(new _M0TPB9ArrayViewGsE(self.buf, 0, self.len), separator);
}
function _M0FPC28encoding4utf821decode__lossy_2einner(bytes, ignore_bom) {
  return _M0FPC28encoding4utf823decode__utf8__lossy__js(bytes.buf, bytes.start, bytes.end - bytes.start | 0, !ignore_bom);
}
function _M0MP24base4wire3Sse3new() {
  return new _M0TP24base4wire3Sse($makebytes(4096, 0), 0, 0, 0);
}
function _M0FP24base4wire5blank(unit) {
  const c = unit;
  return c <= 32 ? c === 32 || c >= 9 && c <= 13 : c < 160 ? false : c === 160 || (c === 5760 || (c >= 8192 && c <= 8202 || (c === 8232 || (c === 8233 || (c === 8239 || (c === 8287 || (c === 12288 || c === 65279)))))));
}
function _M0FP24base4wire7trimmed(text) {
  let from = 0;
  let to = text.end - text.start | 0;
  while (true) {
    let _tmp;
    if (from < to) {
      const _bind = from;
      if (_bind < 0 || _bind >= (text.end - text.start | 0)) {
        $panic();
      }
      _tmp = _M0FP24base4wire5blank(text.str.charCodeAt(text.start + _bind | 0));
    } else {
      _tmp = false;
    }
    if (_tmp) {
      from = from + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  while (true) {
    let _tmp;
    if (to > from) {
      const _bind = to - 1 | 0;
      if (_bind < 0 || _bind >= (text.end - text.start | 0)) {
        $panic();
      }
      _tmp = _M0FP24base4wire5blank(text.str.charCodeAt(text.start + _bind | 0));
    } else {
      _tmp = false;
    }
    if (_tmp) {
      to = to - 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0MPC16string10StringView21clamped__view_2einner(text, from, to);
}
function _M0FP24base4wire9event__of(block) {
  let name = "message";
  let id = undefined;
  const data = new _M0TPB5ArrayGsE([], 0);
  let rest = new _M0TPC16string10StringView(block, 0, block.length);
  while (true) {
    let line;
    let after;
    _L: {
      const _bind = _M0MPC16string10StringView4find(rest, _M0FP24base4wire9event__ofN6recordS314);
      if (_bind === undefined) {
        line = rest;
        after = undefined;
        break _L;
      } else {
        const _Some = _bind;
        const _i = _Some;
        line = _M0MPC16string10StringView21clamped__view_2einner(rest, 0, _i);
        after = _M0MPC16string10StringView21clamped__view_2einner(rest, _i + 1 | 0, undefined);
        break _L;
      }
    }
    if (_M0MPC16string10StringView11has__prefix(line, _M0FP24base4wire9event__ofN6recordS311)) {
      let from;
      let _tmp;
      if ((line.end - line.start | 0) > 5) {
        if (5 >= (line.end - line.start | 0)) {
          $panic();
        }
        _tmp = line.str.charCodeAt(line.start + 5 | 0) === 32;
      } else {
        _tmp = false;
      }
      if (_tmp) {
        from = 6;
      } else {
        from = 5;
      }
      _M0MPC15array5Array4pushGRP24base4wire5EventE(data, _M0MPC16string10StringView9to__owned(_M0MPC16string10StringView21clamped__view_2einner(line, from, undefined)));
    } else {
      if (_M0MPC16string10StringView11has__prefix(line, _M0FP24base4wire9event__ofN6recordS312)) {
        name = _M0MPC16string10StringView9to__owned(_M0FP24base4wire7trimmed(_M0MPC16string10StringView21clamped__view_2einner(line, 6, undefined)));
      } else {
        if (_M0MPC16string10StringView11has__prefix(line, _M0FP24base4wire9event__ofN6recordS313)) {
          id = _M0MPC16string10StringView9to__owned(_M0FP24base4wire7trimmed(_M0MPC16string10StringView21clamped__view_2einner(line, 3, undefined)));
        }
      }
    }
    if (after === undefined) {
      break;
    } else {
      const _Some = after;
      const _more = _Some;
      rest = _more;
    }
    continue;
  }
  if (data.len === 1) {
    const _tmp = name;
    if (0 >= data.len) {
      $panic();
    }
    return new _M0TP24base4wire5Event(_tmp, data.buf[0], id);
  } else {
    if (data.len > 1) {
      return new _M0TP24base4wire5Event(name, _M0MPC15array5Array4joinGsE(data, _M0FP24base4wire9event__ofN6recordS315), id);
    } else {
      const _bind = id;
      return _bind === undefined ? undefined : new _M0TP24base4wire5Event("", "", id);
    }
  }
}
function _M0MP24base4wire3Sse6append(self, chunk) {
  const kept = self.end - self.start | 0;
  const room = self.held.length;
  if ((self.end + chunk.length | 0) > room) {
    if ((kept + chunk.length | 0) > room) {
      const grown = (Math.imul(room, 2) | 0) > (kept + chunk.length | 0) ? Math.imul(room, 2) | 0 : kept + chunk.length | 0;
      const to = $makebytes(grown, 0);
      _M0FP24base4wire5moved(to, self.held, self.start, self.end);
      self.held = to;
    } else {
      _M0FP24base4wire5moved(self.held, self.held, self.start, self.end);
    }
    self.looked = self.looked - self.start | 0;
    self.start = 0;
    self.end = kept;
  }
  self.end = _M0FP24base4wire3put(self.held, self.end, chunk);
}
function _M0MP24base4wire3Sse5blank(self) {
  const from = self.looked > self.start ? self.looked : self.start;
  let i = _M0FP24base4wire7newline(self.held, from, self.end);
  while (true) {
    if (i >= 0 && (i + 1 | 0) < self.end) {
      const _tmp = self.held;
      const _tmp$2 = i + 1 | 0;
      if ((_tmp$2 >>> 0 < _tmp.length ? _tmp[_tmp$2] : $oob()) === 10) {
        return i;
      }
      i = _M0FP24base4wire7newline(self.held, i + 1 | 0, self.end);
      continue;
    } else {
      break;
    }
  }
  self.looked = i >= 0 ? i : self.end;
  return undefined;
}
function _M0MP24base4wire3Sse4feed(self, chunk) {
  _M0MP24base4wire3Sse6append(self, chunk);
  const events = new _M0TPB5ArrayGRP24base4wire5EventE([], 0);
  while (true) {
    const _bind = _M0MP24base4wire3Sse5blank(self);
    if (_bind === undefined) {
      break;
    } else {
      const _Some = _bind;
      const _end = _Some;
      const block = _M0FPC28encoding4utf821decode__lossy_2einner(_M0MPC15bytes5Bytes21clamped__view_2einner(self.held, self.start, _end), true);
      self.start = _end + 2 | 0;
      self.looked = self.start;
      const _bind$2 = _M0FP24base4wire9event__of(block);
      if (_bind$2 === undefined) {
      } else {
        const _Some$2 = _bind$2;
        const _event = _Some$2;
        _M0MPC15array5Array4pushGRP24base4wire5EventE(events, _event);
      }
      continue;
    }
  }
  if (self.start === self.end) {
    self.start = 0;
    self.end = 0;
    self.looked = 0;
  }
  return events;
}
function _M0FP24base2js8sse__new() {
  return _M0MP24base4wire3Sse3new();
}
function _M0FP24base2js9sse__feed(sse, chunk) {
  const events = _M0MP24base4wire3Sse4feed(sse, chunk);
  return _M0MPC15array10FixedArray5makeiGAsE(events.len, (i) => {
    if (i < 0 || i >= events.len) {
      $panic();
    }
    const event = events.buf[i];
    const _bind = event.id;
    if (_bind === undefined) {
      return [event.name, event.data];
    } else {
      const _Some = _bind;
      const _id = _Some;
      return [event.name, event.data, _id];
    }
  });
}
export { _M0FP24base2js8sse__new as sse_new, _M0FP24base2js9sse__feed as sse_feed }
