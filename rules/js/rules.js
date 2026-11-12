// Built by rules/build.sh from rules/src (MoonBit): not to be edited, built again.
function _M0TPB5ArrayGsE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TPC16string10StringView(param0, param1, param2) {
  this.str = param0;
  this.start = param1;
  this.end = param2;
}
function _M0DTPC16option6OptionGdE4None() {}
_M0DTPC16option6OptionGdE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGdE4None__ = new _M0DTPC16option6OptionGdE4None();
function _M0DTPC16option6OptionGdE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGdE4Some.prototype.$tag = 1;
function _M0DTP39stillfail5rules4lock3Off8NotValid(param0) {
  this._0 = param0;
}
_M0DTP39stillfail5rules4lock3Off8NotValid.prototype.$tag = 0;
function _M0DTP39stillfail5rules4lock3Off8NoParent() {}
_M0DTP39stillfail5rules4lock3Off8NoParent.prototype.$tag = 1;
const _M0DTP39stillfail5rules4lock3Off8NoParent__ = new _M0DTP39stillfail5rules4lock3Off8NoParent();
function _M0DTP39stillfail5rules4lock3Off6Beaten(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP39stillfail5rules4lock3Off6Beaten.prototype.$tag = 2;
function _M0DTP39stillfail5rules4lock3Off5Below(param0) {
  this._0 = param0;
}
_M0DTP39stillfail5rules4lock3Off5Below.prototype.$tag = 3;
function _M0DTP39stillfail5rules4lock3Off5Again() {}
_M0DTP39stillfail5rules4lock3Off5Again.prototype.$tag = 4;
const _M0DTP39stillfail5rules4lock3Off5Again__ = new _M0DTP39stillfail5rules4lock3Off5Again();
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
const _M0FPB12random__seed = () => {
  if (globalThis.crypto?.getRandomValues) {
    const array = new Uint32Array(1);
    globalThis.crypto.getRandomValues(array);
    return array[0] | 0; // Convert to signed 32
  } else {
    return Math.floor(Math.random() * 0x100000000) | 0; // Fallback to Math.random
  }
};
const _M0FPB19int__to__string__js = (x, radix) => {
  return x.toString(radix);
};
const _M0FPB21int64__to__string__js = (num, radix) => BigInt.asIntN(64, num).toString(radix);
function _M0TPB4IterGUsRP39stillfail5rules4lock9PersonWebEE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function _M0TPB4IterGORPC14json4JsonE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function _M0TPB4IterGcE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function $make_array_len_and_init(a, b) {
  const arr = new Array(a);
  arr.fill(b);
  return arr;
}
function _M0TPB8MutLocalGiE(param0) {
  this.val = param0;
}
const _M0FPB22js__code__unit__string = (c) => String.fromCharCode(c);
const _M0FPB13js__index__of = (s, start, end, p) => {
  if (end - start < p.length) return -1;
  if (end === s.length) return s.indexOf(p, start);
  const i = s.substring(start, end).indexOf(p);
  return i < 0 ? i : start + i;
};
const _M0FPB13js__substring = (s, start, end) => start === 0 && end === s.length ? s : s.substring(start, end);
function _M0TPB5ArrayGUssEE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TPB4IterGRPC14json4JsonE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function _M0TPB4IterGRPC16string10StringViewE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function _M0TPB8MutLocalGORPC16string10StringViewE(param0) {
  this.val = param0;
}
function $compare_int(a, b) {
  return (a >= b) - (a <= b);
}
function _M0DTPC16option6OptionGORPC14json4JsonE4None() {}
_M0DTPC16option6OptionGORPC14json4JsonE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGORPC14json4JsonE4None__ = new _M0DTPC16option6OptionGORPC14json4JsonE4None();
function _M0DTPC16option6OptionGORPC14json4JsonE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGORPC14json4JsonE4Some.prototype.$tag = 1;
function _M0TPB9ArrayViewGRP39stillfail5rules4lock4StmtE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGORPC14json4JsonE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB5ArrayGORPC14json4JsonE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TPB5ArrayGiE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TPB3MapGsiE(param0, param1, param2, param3, param4, param5, param6) {
  this.entries = param0;
  this.size = param1;
  this.capacity = param2;
  this.capacity_mask = param3;
  this.grow_at = param4;
  this.head = param5;
  this.tail = param6;
}
function _M0TPB3MapGsUssOsEE(param0, param1, param2, param3, param4, param5, param6) {
  this.entries = param0;
  this.size = param1;
  this.capacity = param2;
  this.capacity_mask = param3;
  this.grow_at = param4;
  this.head = param5;
  this.tail = param6;
}
function _M0TPB3MapGsuE(param0, param1, param2, param3, param4, param5, param6) {
  this.entries = param0;
  this.size = param1;
  this.capacity = param2;
  this.capacity_mask = param3;
  this.grow_at = param4;
  this.head = param5;
  this.tail = param6;
}
function _M0TPB3MapGiRP39stillfail5rules4lock3OffE(param0, param1, param2, param3, param4, param5, param6) {
  this.entries = param0;
  this.size = param1;
  this.capacity = param2;
  this.capacity_mask = param3;
  this.grow_at = param4;
  this.head = param5;
  this.tail = param6;
}
function _M0TPB5EntryGsiE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsUssOsEE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules4lock12PersonDeviceE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGssE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRPC14json4JsonE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules4lock6DeviceE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules5vault6DeviceE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsuE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRPB5ArrayGiEE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGiRP39stillfail5rules4lock3OffE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRPB5ArrayGsEE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules4lock6MemberE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules4lock7StationE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules4lock7PasskeyE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsUssEE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsUsssEE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules4lock4StmtE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB5EntryGsRP39stillfail5rules4lock9PersonWebE(param0, param1, param2, param3, param4, param5) {
  this.prev = param0;
  this.next = param1;
  this.psl = param2;
  this.hash = param3;
  this.key = param4;
  this.value = param5;
}
function _M0TPB8MutLocalGORPB5EntryGsRP39stillfail5rules4lock12PersonDeviceEE(param0) {
  this.val = param0;
}
function _M0TPB8MutLocalGORPB5EntryGsuEE(param0) {
  this.val = param0;
}
function _M0TPB12MutArrayViewGUssEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB12MutArrayViewGiE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB12MutArrayViewGsE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok.prototype.$tag = 1;
function _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(param0) {
  this._0 = param0;
}
_M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused.prototype.$tag = 2;
function _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal(param0) {
  this._0 = param0;
}
_M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal.prototype.$tag = 1;
function _M0DTPC15error5Error44stillfail_2frules_2fform_2eInvalid_2eInvalid(param0) {
  this._0 = param0;
}
_M0DTPC15error5Error44stillfail_2frules_2fform_2eInvalid_2eInvalid.prototype.$tag = 0;
function $i64_trunc_f64(a) {
  if (Number.isNaN(a)) return 0n;
  if (a >= 9223372036854775807) return 9223372036854775807n;
  if (a <= -9223372036854775808) return 9223372036854775808n;
  return BigInt.asUintN(64, BigInt(Math.trunc(a)));
}
function _M0DTPC16result6ResultGsRP39stillfail5rules4form7InvalidE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGsRP39stillfail5rules4form7InvalidE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGsRP39stillfail5rules4form7InvalidE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGsRP39stillfail5rules4form7InvalidE2Ok.prototype.$tag = 1;
function _M0TPB9ArrayViewGUsRPC14json4JsonEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0DTPC14json4Json4Null() {}
_M0DTPC14json4Json4Null.prototype.$tag = 0;
const _M0DTPC14json4Json4Null__ = new _M0DTPC14json4Json4Null();
function _M0DTPC14json4Json4True() {}
_M0DTPC14json4Json4True.prototype.$tag = 1;
const _M0DTPC14json4Json4True__ = new _M0DTPC14json4Json4True();
function _M0DTPC14json4Json5False() {}
_M0DTPC14json4Json5False.prototype.$tag = 2;
const _M0DTPC14json4Json5False__ = new _M0DTPC14json4Json5False();
function _M0DTPC14json4Json6Number(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTPC14json4Json6Number.prototype.$tag = 3;
function _M0DTPC14json4Json6String(param0) {
  this._0 = param0;
}
_M0DTPC14json4Json6String.prototype.$tag = 4;
function _M0DTPC14json4Json5Array(param0) {
  this._0 = param0;
}
_M0DTPC14json4Json5Array.prototype.$tag = 5;
function _M0DTPC14json4Json6Object(param0) {
  this._0 = param0;
}
_M0DTPC14json4Json6Object.prototype.$tag = 6;
function _M0TPB5ArrayGRPC14json4JsonE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TPB9ArrayViewGUsRP39stillfail5rules4lock12PersonDeviceEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUssEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6DeviceEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsuEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6MemberEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsRP39stillfail5rules4lock7StationEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsRP39stillfail5rules4lock7PasskeyEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsRP39stillfail5rules4lock9PersonWebEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0DTPC16result6ResultGRP39stillfail5rules4lock12PersonDeviceRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock12PersonDeviceRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock12PersonDeviceRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock12PersonDeviceRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TP39stillfail5rules4lock12PersonDevice(param0, param1, param2) {
  this.key = param0;
  this.id = param1;
  this.label = param2;
}
function _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TP39stillfail5rules4lock9PersonWeb(param0, param1, param2, param3) {
  this.id = param0;
  this.label = param1;
  this.at = param2;
  this.exp = param3;
}
function _M0TP39stillfail5rules4lock6Person(param0, param1, param2, param3, param4, param5) {
  this.sub = param0;
  this.genesis = param1;
  this.head = param2;
  this.seq = param3;
  this.devices = param4;
  this.webs = param5;
}
function _M0TPB9ArrayViewGUsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0DTPB6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPB6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPB6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPB6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0DTPB6ResultGsRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPB6ResultGsRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPB6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPB6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TPB5ArrayGUssRPC14json4JsonsEE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TP39stillfail5rules4lock6Roster(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9, param10, param11, param12) {
  this.rooted = param0;
  this.members = param1;
  this.stations = param2;
  this.pairs = param3;
  this.undecided = param4;
  this.cancelled = param5;
  this.statements = param6;
  this.labels = param7;
  this.refused = param8;
  this.in_force = param9;
  this.lacking = param10;
  this.newest = param11;
  this.settings = param12;
}
function _M0TPB5ArrayGRP39stillfail5rules4lock5BoundE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TPB5ArrayGUsssEE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TPB5ArrayGRP39stillfail5rules4lock4SaidE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TPB5ArrayGRP39stillfail5rules4lock4StmtE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TP39stillfail5rules4lock4Stmt(param0, param1, param2, param3, param4) {
  this.hash = param0;
  this.kind = param1;
  this.body = param2;
  this.log = param3;
  this.by = param4;
}
function _M0TPB9ArrayViewGUsRP39stillfail5rules4lock4StmtEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsUssEEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsUsssEEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsUssOsEEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TP39stillfail5rules4lock4Said(param0, param1, param2, param3, param4, param5, param6) {
  this.hash = param0;
  this.kind = param1;
  this.log = param2;
  this.by = param3;
  this.label = param4;
  this.why = param5;
  this.decided = param6;
}
function _M0TP39stillfail5rules4lock5Bound(param0, param1, param2, param3, param4) {
  this.sub = param0;
  this.role = param1;
  this.lock = param2;
  this.admit = param3;
  this.keys = param4;
}
function _M0TP39stillfail5rules4lock9LockState(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9, param10, param11, param12, param13, param14, param15, param16) {
  this.ws = param0;
  this.seq = param1;
  this.head = param2;
  this.genesis = param3;
  this.origins = param4;
  this.rp_id = param5;
  this.cloud_keys = param6;
  this.members = param7;
  this.devices = param8;
  this.sign_keys = param9;
  this.passkeys = param10;
  this.signed = param11;
  this.stations = param12;
  this.gateways = param13;
  this.persons = param14;
  this.disabled = param15;
  this.moved = param16;
}
function _M0TP39stillfail5rules4lock6Member(param0, param1, param2) {
  this.sub = param0;
  this.email = param1;
  this.role = param2;
}
function _M0TP39stillfail5rules4lock6Device(param0, param1, param2, param3, param4, param5, param6, param7, param8) {
  this.id = param0;
  this.sub = param1;
  this.kind = param2;
  this.label = param3;
  this.sign_key = param4;
  this.endpoints = param5;
  this.exp = param6;
  this.by = param7;
  this.own = param8;
}
function _M0TP39stillfail5rules4lock7Station(param0, param1) {
  this.key = param0;
  this.name = param1;
}
function _M0TP39stillfail5rules4lock6State4(param0, param1) {
  this.on = param0;
  this.lock = param1;
}
function _M0DTPC16result6ResultGURP39stillfail5rules4lock12PersonDevicesRP39stillfail5rules4lock6PersonERP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGURP39stillfail5rules4lock12PersonDevicesRP39stillfail5rules4lock6PersonERP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGURP39stillfail5rules4lock12PersonDevicesRP39stillfail5rules4lock6PersonERP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGURP39stillfail5rules4lock12PersonDevicesRP39stillfail5rules4lock6PersonERP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock6MemberRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock6MemberRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock6MemberRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock6MemberRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock7PasskeyRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock7PasskeyRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock7PasskeyRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock7PasskeyRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TP39stillfail5rules4lock7Passkey(param0, param1, param2, param3, param4) {
  this.id = param0;
  this.sub = param1;
  this.key = param2;
  this.label = param3;
  this.own = param4;
}
function _M0DTPC16result6ResultGRP39stillfail5rules4lock7StationRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock7StationRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock7StationRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock7StationRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TP39stillfail5rules4lock6Signer(param0, param1, param2, param3) {
  this.sub = param0;
  this.role = param1;
  this.passkey = param2;
  this.own = param3;
}
function _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0DTP39stillfail5rules4role6Change9MemberSet(param0, param1) {
  this._0 = param0;
  this._1 = param1;
}
_M0DTP39stillfail5rules4role6Change9MemberSet.prototype.$tag = 0;
function _M0DTP39stillfail5rules4role6Change12MemberRemove(param0) {
  this._0 = param0;
}
_M0DTP39stillfail5rules4role6Change12MemberRemove.prototype.$tag = 1;
function _M0DTP39stillfail5rules4role6Change3Own(param0) {
  this._0 = param0;
}
_M0DTP39stillfail5rules4role6Change3Own.prototype.$tag = 2;
function _M0DTP39stillfail5rules4role6Change6Roster() {}
_M0DTP39stillfail5rules4role6Change6Roster.prototype.$tag = 3;
const _M0DTP39stillfail5rules4role6Change6Roster__ = new _M0DTP39stillfail5rules4role6Change6Roster();
function _M0DTP39stillfail5rules4role6Change9CloudKeys() {}
_M0DTP39stillfail5rules4role6Change9CloudKeys.prototype.$tag = 4;
const _M0DTP39stillfail5rules4role6Change9CloudKeys__ = new _M0DTP39stillfail5rules4role6Change9CloudKeys();
function _M0DTP39stillfail5rules4role6Change7Disable() {}
_M0DTP39stillfail5rules4role6Change7Disable.prototype.$tag = 5;
const _M0DTP39stillfail5rules4role6Change7Disable__ = new _M0DTP39stillfail5rules4role6Change7Disable();
function _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TPB9ArrayViewGUsiEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0DTPB6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPB6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPB6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPB6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateE(param0, param1, param2) {
  this.at = param0;
  this.hash = param1;
  this.state = param2;
}
function _M0TPB9ArrayViewGUiRP39stillfail5rules4lock3OffEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsRPB5ArrayGiEEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0DTPC16result6ResultGRP39stillfail5rules4lock5ChainRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock5ChainRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock5ChainRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock5ChainRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
function _M0TPB9ArrayViewGUsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB9ArrayViewGUsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TPB5ArrayGUiRP39stillfail5rules4lock3OffEE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TP39stillfail5rules4lock5Chain(param0, param1, param2, param3) {
  this.entries = param0;
  this.at = param1;
  this.hashes = param2;
  this.off = param3;
}
function _M0TP39stillfail5rules4lock3LogGRP39stillfail5rules4lock9LockStateE(param0, param1, param2, param3) {
  this.start = param0;
  this.next = param1;
  this.weight = param2;
  this.removal = param3;
}
function _M0TP39stillfail5rules4lock3LogGRP39stillfail5rules4lock6PersonE(param0, param1, param2, param3) {
  this.start = param0;
  this.next = param1;
  this.weight = param2;
  this.removal = param3;
}
function _M0TPB5ArrayGRP39stillfail5rules4lock6CommitE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
const _M0FP39stillfail5rules2js8js__kind = (v) => v === null ? 0 : typeof v === "boolean" ? 1 : typeof v === "number" ? 2 : typeof v === "string" ? 3 : Array.isArray(v) ? 4 : typeof v === "object" ? 5 : 6;
const _M0FP39stillfail5rules2js8js__bool = (v) => v;
const _M0FP39stillfail5rules2js7js__num = (v) => v;
const _M0FP39stillfail5rules2js7js__str = (v) => v;
const _M0FP39stillfail5rules2js7js__len = (v) => v.length;
const _M0FP39stillfail5rules2js6js__at = (v, i) => v[i];
const _M0FP39stillfail5rules2js8js__keys = (v) => Object.keys(v).filter((k) => v[k] !== undefined);
const _M0FP39stillfail5rules2js7js__get = (v, k) => v[k];
function _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok.prototype.$tag = 1;
const _M0FP39stillfail5rules2js15js__sha256__hex = (c, s) => c.sha256Hex(s);
const _M0FP39stillfail5rules2js14js__sig__valid = (c, sig, hash, origins, rp, passkey) => c.sigValid(sig, hash, origins, rp, passkey);
const _M0FP39stillfail5rules2js18js__valid__key__id = (c, id) => c.validKeyId(id);
const _M0FP39stillfail5rules2js19js__endpoint__proof = (c, ws, base, endpoint, proof) => c.endpointProof(ws, base, endpoint, proof);
const _M0FP39stillfail5rules2js14js__new__array = () => [];
const _M0FP39stillfail5rules2js15js__new__object = () => ({});
const _M0FP39stillfail5rules2js8js__null = () => null;
const _M0FP39stillfail5rules2js12js__of__bool = (b) => b;
const _M0FP39stillfail5rules2js11js__of__num = (n) => n;
const _M0FP39stillfail5rules2js11js__of__str = (s) => s;
const _M0FP39stillfail5rules2js8js__push = (a, v) => { a.push(v) };
const _M0FP39stillfail5rules2js7js__put = (o, k, v) => { o[k] = v };
function _M0DTPC16result6ResultGRPB5ArrayGRPC14json4JsonERP39stillfail5rules4form7InvalidE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRPB5ArrayGRPC14json4JsonERP39stillfail5rules4form7InvalidE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRPB5ArrayGRPC14json4JsonERP39stillfail5rules4form7InvalidE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRPB5ArrayGRPC14json4JsonERP39stillfail5rules4form7InvalidE2Ok.prototype.$tag = 1;
const _M0FP39stillfail5rules2js6handle = (s) => s;
const _M0FP39stillfail5rules2js11js__entries = (m) => [...m];
const _M0FP39stillfail5rules2js22js__record__sig__valid = (c, sig, tag, text) => c.recordSigValid(sig, tag, text);
function _M0TPB9ArrayViewGUsRP39stillfail5rules5vault6DeviceEE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function _M0TP39stillfail5rules5vault6Device(param0, param1, param2, param3) {
  this.sub = param0;
  this.kind = param1;
  this.sign_key = param2;
  this.own = param3;
}
function _M0TP39stillfail5rules5vault8LockView(param0, param1, param2, param3) {
  this.ws = param0;
  this.members = param1;
  this.devices = param2;
  this.sign_keys = param3;
}
function _M0DTPB6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE3Err(param0) {
  this._0 = param0;
}
_M0DTPB6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE3Err.prototype.$tag = 0;
function _M0DTPB6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(param0) {
  this._0 = param0;
}
_M0DTPB6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok.prototype.$tag = 1;
function _M0TPB5ArrayGRPB5ArrayGRPC14json4JsonEE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0DTPC16result6ResultGRPB5ArrayGRPB5ArrayGRPC14json4JsonEERP39stillfail5rules4form7InvalidE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRPB5ArrayGRPB5ArrayGRPC14json4JsonEERP39stillfail5rules4form7InvalidE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRPB5ArrayGRPB5ArrayGRPC14json4JsonEERP39stillfail5rules4form7InvalidE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRPB5ArrayGRPB5ArrayGRPC14json4JsonEERP39stillfail5rules4form7InvalidE2Ok.prototype.$tag = 1;
function _M0TP39stillfail5rules4lock6Commit(param0, param1) {
  this.genesis = param0;
  this.chain = param1;
}
const _M0FP078stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2fvault_2eCrypto = { method_0: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules5vault6Crypto18record__sig__valid };
const _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger = { method_0: _M0IPB13StringBuilderPB6Logger13write__string, method_1: _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE, method_2: _M0IPB13StringBuilderPB6Logger11write__view, method_3: _M0IPB13StringBuilderPB6Logger11write__char, method_4: _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE, method_5: _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE };
const _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto = { method_0: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto11sha256__hex, method_1: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto10sig__valid, method_2: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto14valid__key__id, method_3: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto15endpoint__proof };
function _M0FP15Error10to__string(_e) {
  const _f = _M0FP15Error10_2amethods[_e.$tag]._1;
  return _f(_e);
}
const _M0FP15Error13_2amethods__0 = { _0: "stillfail/rules/form.Invalid.Invalid", _1: (_e) => _M0FP15Error10_2amethods[_e.$tag]._0 };
const _M0FP15Error13_2amethods__1 = { _0: "stillfail/rules/lock.LockError.Refusal", _1: (_e) => _M0FP15Error10_2amethods[_e.$tag]._0 };
const _M0FP15Error13_2amethods__2 = { _0: "stillfail/rules/lock.LockError.Refused", _1: (_e) => _M0FP15Error10_2amethods[_e.$tag]._0 };
const _M0FP15Error10_2amethods = [_M0FP15Error13_2amethods__0, _M0FP15Error13_2amethods__1, _M0FP15Error13_2amethods__2];
const _M0MPB4Iter4nextN6constrS538GUsRP39stillfail5rules4lock9PersonWebEE = 0;
const _M0MPB4Iter4nextN6constrS539GUsRP39stillfail5rules4lock9PersonWebEE = 0;
const _M0MPB4Iter4nextN6constrS626GORPC14json4JsonE = 0;
const _M0MPB4Iter4nextN6constrS627GORPC14json4JsonE = 0;
const _M0MPB4Iter4nextN6constrS634GcE = 0;
const _M0MPB4Iter4nextN6constrS635GcE = 0;
const _M0MPB4Iter3newN6constrS726GUsRP39stillfail5rules4lock9PersonWebEE = 0;
const _M0MPB4Iter3newN6constrS792GORPC14json4JsonE = 0;
const _M0MPB4Iter3newN6constrS798GcE = 0;
const _M0FP39stillfail5rules4form11hex__digits = "0123456789abcdef";
const _M0FP39stillfail5rules4lock8role__ofN6constrS6006 = 3;
const _M0FP39stillfail5rules4lock8role__ofN6constrS6007 = 2;
const _M0FP39stillfail5rules4lock8role__ofN6constrS6008 = 1;
const _M0FP39stillfail5rules4lock8role__ofN6constrS6009 = 0;
const _M0FP39stillfail5rules5vault6scopes = new _M0TPB5ArrayGsE(["once", "hour", "chat"], 3);
const _M0FP39stillfail5rules5vault5kinds = new _M0TPB5ArrayGsE(["token", "ssh_key", "login", "file", "browser"], 5);
const _M0FP39stillfail5rules5vault5modes = new _M0TPB5ArrayGsE(["proxy", "ssh", "env", "file", "browser"], 5);
let _M0FPB4seed__held;
const _M0FPB4seed__drawn = () => (_M0FPB4seed__held === undefined ? (_M0FPB4seed__held = _M0FPB12random__seed()) : _M0FPB4seed__held);
const _M0FP39stillfail5rules4lock7passkeyN6recordS6062 = new _M0TPC16string10StringView("p256:", 0, 5);
const _M0FP39stillfail5rules4lock5applyN6constrS6238 = new _M0DTPC16option6OptionGdE4Some(1);
const _M0FP39stillfail5rules4lock7genesisN6constrS6138 = "genesis";
const _M0FP39stillfail5rules4lock7genesisN6constrS6139 = new _M0DTPC16option6OptionGdE4Some(0);
const _M0FP39stillfail5rules4lock7genesisN6constrS6140 = new _M0DTPC16option6OptionGdE4Some(1);
const _M0FP39stillfail5rules4lock14person__deviceN6recordS5366 = new _M0TPC16string10StringView("ed25519:", 0, 8);
const _M0FP39stillfail5rules4lock12person__stepN6constrS5395 = new _M0DTPC16option6OptionGdE4Some(1);
const _M0FP39stillfail5rules5vault8box__keyN6recordS6918 = new _M0TPC16string10StringView("x25519:", 0, 7);
const _M0FP39stillfail5rules5vault10sig__shapeN6constrS6959 = "Ed25519";
const _M0FP39stillfail5rules5vault10sig__shapeN6constrS6960 = "ES256";
const _M0FP39stillfail5rules5vault8cert__okN6constrS6993 = "the box certificate's device is not an app device in the lock";
const _M0FP39stillfail5rules5vault8cert__okN6constrS6994 = "the box certificate's device was put in the lock by someone else, not its person";
const _M0FP39stillfail5rules5vault8cert__okN6constrS6995 = "a box certificate is signed by its own device's key";
const _M0FP39stillfail5rules5vault8cert__okN6constrS6996 = "the box certificate's signature is invalid";
const _M0FP39stillfail5rules5vault8cert__okN5shapeS6997 = "a box certificate is {v: 1, ws, device, box, at, sig} of this workspace";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7021 = "a vault is {v: 1, ws, …} of this workspace";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7022 = "a vault's id is v_<ULID>";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7023 = "seq, epoch and at are whole numbers";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7024 = "a vault has an owner and a name";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7025 = "members are distinct subs";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7026 = "the owner is a member";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7027 = "keys is a list";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7028 = "recovery is a seal";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7029 = "lasts is once, hour or chat";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7030 = "a deleted vault is sealed to no one";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7031 = "a vault is signed";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7032 = "a vault's first version is seq 0";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7033 = "another vault";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7034 = "a vault's owner does not change";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7035 = "a deleted vault stays deleted";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7036 = "the epoch does not go back";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7037 = "removing a member or device takes a new epoch (a new vault key)";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7038 = "a key is {cert, wrapped}";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7039 = "the vault's signature is invalid";
const _M0FP39stillfail5rules5vault9vault__okN6constrS7040 = "a vault is signed by one of its owner's devices in the lock";
const _M0MPC16string10StringView4findN6constrS994 = 0;
const _M0FP39stillfail5rules5vault4hostN6recordS6924 = new _M0TPC16string10StringView("*.", 0, 2);
const _M0FP39stillfail5rules5vault4hostN6recordS6925 = new _M0TPC16string10StringView(".", 0, 1);
const _M0FP39stillfail5rules5vault20browser__listing__okN6constrS7135 = "a sign-in (kind browser) is given into a chat's browser (modes: [\"browser\"]), and only a sign-in is";
const _M0FP39stillfail5rules5vault20browser__listing__okN6recordS7136 = new _M0TPC16string10StringView("*.", 0, 2);
const _M0FP39stillfail5rules5vault20browser__listing__okN6constrS7137 = "a sign-in names the sites it is for (github.com: its subdomains with it)";
const _M0FP39stillfail5rules5vault11listing__okN6constrS7143 = "a listing is {name, kind, modes, hosts, env?}";
const _M0FP39stillfail5rules5vault11listing__okN6constrS7144 = "modes are proxy, ssh, env, file or browser";
const _M0FP39stillfail5rules5vault11listing__okN6constrS7145 = "hosts are domain names (*.example.com allowed)";
const _M0FP39stillfail5rules5vault11listing__okN6constrS7146 = "env is a variable name";
const _M0FP39stillfail5rules5vault11listing__okN6constrS7147 = "lasts is once, hour or chat";
const _M0FP39stillfail5rules5vault8item__okN6constrS7191 = "an item is {v: 1, ws, vault, …} of this vault";
const _M0FP39stillfail5rules5vault8item__okN6constrS7192 = "an item's id is i_<ULID>";
const _M0FP39stillfail5rules5vault8item__okN6constrS7193 = "version, epoch and at are whole numbers";
const _M0FP39stillfail5rules5vault8item__okN6constrS7194 = "deleted is true or absent";
const _M0FP39stillfail5rules5vault8item__okN6constrS7195 = "ct is base64url";
const _M0FP39stillfail5rules5vault8item__okN6constrS7196 = "a deleted item has no ciphertext or listing";
const _M0FP39stillfail5rules5vault8item__okN6constrS7197 = "an item holds a ciphertext";
const _M0FP39stillfail5rules5vault8item__okN6constrS7198 = "an item is signed";
const _M0FP39stillfail5rules5vault8item__okN6constrS7199 = "an item's first version is 0";
const _M0FP39stillfail5rules5vault8item__okN6constrS7200 = "another item";
const _M0FP39stillfail5rules5vault8item__okN6constrS7201 = "the item was deleted";
const _M0FP39stillfail5rules5vault8item__okN6constrS7202 = "the item's signature is invalid";
const _M0FP39stillfail5rules5vault8item__okN6constrS7203 = "an item is signed by a vault member's device in the lock";
const _M0FP39stillfail5rules4fork4stepN6constrS5020 = 0;
const _M0FP39stillfail5rules4fork4stepN6constrS5021 = 1;
const _M0FP39stillfail5rules4fork4stepN6constrS5022 = 2;
const _M0FP39stillfail5rules4fork4stepN6constrS5023 = 3;
const _M0FP39stillfail5rules4lock6beforeN5tupleS6379 = { _0: 0, _1: 1 };
const _M0FP39stillfail5rules4lock6beforeN5tupleS6380 = { _0: 1, _1: 0 };
const _M0FP39stillfail5rules4lock6beforeN5tupleS6381 = { _0: 0, _1: 0 };
const _M0FP39stillfail5rules4lock6activeN6constrS6410GRP39stillfail5rules4lock9LockStateE = new _M0DTP39stillfail5rules4lock3Off8NotValid("not the genesis this log is pinned to");
const _M0FP39stillfail5rules4lock11lock__chainN6constrS6776 = "device.remove";
const _M0FP39stillfail5rules4lock13person__chainN6constrS6797 = "device.remove";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5222 = "a body is {ws, kind, …, salt}";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5223 = "a body is {ws, kind, …, salt}";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5224 = "a body names the statement before it";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5225 = "no such statement";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5226 = "an admit names a person, their email, a lock and a role";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5227 = "a removal names whom and what it cancels";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5228 = "a station is named by its key";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5229 = "a removal names whom and what it cancels";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5230 = "open names the settings";
const _M0FP39stillfail5rules4lock9body__whyN6constrS5231 = "off says nothing more";
const _M0FP39stillfail5rules4lock3mgrN6constrS5462 = "owner";
const _M0FP39stillfail5rules4lock3mgrN6constrS5463 = "admin";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5478 = "ws";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5479 = "open";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5480 = "off";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5481 = "in";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5482 = "out";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5483 = "in";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5484 = "in";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5485 = "admit cancelled";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5486 = "its signer may not give that role";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5487 = "another admit of the person outranks it (a lower role given later changes nothing)";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5488 = "its cancellations are undecided (a circle of removals)";
const _M0FP39stillfail5rules4lock10roster__ofN6constrS5489 = "station cancelled";
const _M0FP39stillfail5rules4lock6state4N6constrS5874 = "off";
const _M0FP39stillfail5rules4lock13body__refusalN6constrS6810 = "no entry it keeps commits to it";
const _M0FP39stillfail5rules4lock13body__refusalN6constrS6811 = "ws";
const _M0FP39stillfail5rules4lock13body__refusalN6constrS6812 = "ws";
const _M0FP39stillfail5rules4lock13body__refusalN6constrS6813 = "its prev is not a statement before it in that log";
const _M0FP39stillfail5rules4lock13body__refusalN6constrS6814 = "its entry's tag is not its workspace's in that log";
const _M0FP39stillfail5rules4lock13body__refusalN6constrS6815 = "no entry it keeps commits to it";
const _M0FP39stillfail5rules4lock13body__refusalN6constrS6816 = "it names no workspace this keeper keeps";
function _M0MPC16string10StringView12unsafe__view(self, start, end) {
  return new _M0TPC16string10StringView(self.str, self.start + start | 0, self.start + end | 0);
}
function _M0FPB13consume4__acc(acc, input) {
  const _p = (acc >>> 0) + ((Math.imul(input, -1028477379) | 0) >>> 0) | 0;
  return Math.imul(_p << 17 | (_p >>> 15 | 0), 668265263) | 0;
}
function _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGRPC16string10StringViewEE(dst, dst_offset, src, src_offset, len) {
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
function _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGiEE(dst, dst_offset, src, src_offset, len) {
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
function _M0MPB18UninitializedArray12unsafe__blitGRP39stillfail5rules4lock4StmtE(dst, dst_offset, src, src_offset, len) {
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGRPC16string10StringViewEE(dst, dst_offset, src, src_offset, len);
}
function _M0MPB18UninitializedArray12unsafe__blitGiE(dst, dst_offset, src, src_offset, len) {
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGiEE(dst, dst_offset, src, src_offset, len);
}
function _M0MPB18UninitializedArray23unsafe__make__and__blitGRP39stillfail5rules4lock4StmtE(src, allocate_len, src_offset, dst_offset, blit_len) {
  const dst = new Array(allocate_len);
  _M0MPB18UninitializedArray12unsafe__blitGRP39stillfail5rules4lock4StmtE(dst, dst_offset, src, src_offset, blit_len);
  return dst;
}
function _M0MPB18UninitializedArray23unsafe__make__and__blitGiE(src, allocate_len, src_offset, dst_offset, blit_len) {
  const dst = new Array(allocate_len);
  _M0MPB18UninitializedArray12unsafe__blitGiE(dst, dst_offset, src, src_offset, blit_len);
  return dst;
}
function _M0MPB13StringBuilder13write__objectGiE(self, obj) {
  _M0IP016_24default__implPB4Show6outputGiE(obj, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0MPB18UninitializedArray23make__and__blit_2einnerGRP39stillfail5rules4lock4StmtE(src, allocate_len, len, src_offset, dst_offset) {
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
    return _M0MPB18UninitializedArray23unsafe__make__and__blitGRP39stillfail5rules4lock4StmtE(src, allocate_len, src_offset, dst_offset, len);
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
function _M0MPB18UninitializedArray23make__and__blit_2einnerGiE(src, allocate_len, len, src_offset, dst_offset) {
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
    return _M0MPB18UninitializedArray23unsafe__make__and__blitGiE(src, allocate_len, src_offset, dst_offset, len);
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
function _M0FPB32code__point__of__surrogate__pair(leading, trailing) {
  return (((Math.imul(leading - 55296 | 0, 1024) | 0) + trailing | 0) - 56320 | 0) + 65536 | 0;
}
function _M0IPC15tuple6Tuple2PB7Compare7compareGssE(self, other) {
  const t0 = _M0IPC16string6StringPB7Compare7compare(self._0, other._0);
  return t0 === 0 ? _M0IPC16string6StringPB7Compare7compare(self._1, other._1) : t0;
}
function _M0IPC15tuple6Tuple3PB7Compare7compareGsssE(self, other) {
  const t0 = _M0IPC16string6StringPB7Compare7compare(self._0, other._0);
  if (t0 === 0) {
    const t1 = _M0IPC16string6StringPB7Compare7compare(self._1, other._1);
    return t1 === 0 ? _M0IPC16string6StringPB7Compare7compare(self._2, other._2) : t1;
  } else {
    return t0;
  }
}
function _M0IP016_24default__implPB2Eq10not__equalGORPC14json4JsonE(x, y) {
  return !_M0IPC16option6OptionPB2Eq5equalGRPC14json4JsonE(x, y);
}
function _M0IP016_24default__implPB2Eq10not__equalGOsE(x, y) {
  return !_M0IPC16option6OptionPB2Eq5equalGsE(x, y);
}
function _M0IP016_24default__implPB2Eq10not__equalGOdE(x, y) {
  return !_M0IPC16option6OptionPB2Eq5equalGdE(x, y);
}
function _M0IP016_24default__implPB7Compare6op__ltGsE(x, y) {
  return _M0IPC16string6StringPB7Compare7compare(x, y) < 0;
}
function _M0IP016_24default__implPB7Compare6op__gtGsE(x, y) {
  return _M0IPC16string6StringPB7Compare7compare(x, y) > 0;
}
function _M0IP016_24default__implPB7Compare6op__leGsE(x, y) {
  return _M0IPC16string6StringPB7Compare7compare(x, y) <= 0;
}
function _M0IP016_24default__implPB7Compare6op__geGsE(x, y) {
  return _M0IPC16string6StringPB7Compare7compare(x, y) >= 0;
}
function _M0FPB14avalanche__acc(acc) {
  let acc$2 = acc;
  acc$2 = acc$2 ^ (acc$2 >>> 15 | 0);
  acc$2 = Math.imul(acc$2, -2048144777) | 0;
  acc$2 = acc$2 ^ (acc$2 >>> 13 | 0);
  acc$2 = Math.imul(acc$2, -1028477379) | 0;
  acc$2 = acc$2 ^ (acc$2 >>> 16 | 0);
  return acc$2;
}
function _M0FPB13finalize__acc(acc) {
  return _M0FPB14avalanche__acc(acc);
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
function _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(self) {
  const _func = self.f;
  const result = _func();
  const _bind = self.size_hint;
  if (result === undefined) {
    self.size_hint = _M0MPB4Iter4nextN6constrS539GUsRP39stillfail5rules4lock9PersonWebEE;
  } else {
    if (_bind === undefined) {
    } else {
      const _Some = _bind;
      const _n = _Some;
      self.size_hint = _n > 0 ? _n - 1 | 0 : _M0MPB4Iter4nextN6constrS538GUsRP39stillfail5rules4lock9PersonWebEE;
    }
  }
  return result;
}
function _M0MPB4Iter4nextGORPC14json4JsonE(self) {
  const _func = self.f;
  const result = _func();
  const _bind = self.size_hint;
  if (result.$tag === 1) {
    if (_bind === undefined) {
    } else {
      const _Some = _bind;
      const _n = _Some;
      self.size_hint = _n > 0 ? _n - 1 | 0 : _M0MPB4Iter4nextN6constrS626GORPC14json4JsonE;
    }
  } else {
    self.size_hint = _M0MPB4Iter4nextN6constrS627GORPC14json4JsonE;
  }
  return result;
}
function _M0MPB4Iter4nextGcE(self) {
  const _func = self.f;
  const result = _func();
  const _bind = self.size_hint;
  if (result === -1) {
    self.size_hint = _M0MPB4Iter4nextN6constrS635GcE;
  } else {
    if (_bind === undefined) {
    } else {
      const _Some = _bind;
      const _n = _Some;
      self.size_hint = _n > 0 ? _n - 1 | 0 : _M0MPB4Iter4nextN6constrS634GcE;
    }
  }
  return result;
}
function _M0MPC13int3Int18to__string_2einner(self, radix) {
  return _M0FPB19int__to__string__js(self, radix);
}
function _M0MPC15int645Int6418to__string_2einner(self, radix) {
  return _M0FPB21int64__to__string__js(self, radix);
}
function _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(f, size_hint) {
  let size_hint$2;
  if (size_hint === undefined) {
    size_hint$2 = undefined;
  } else {
    const _Some = size_hint;
    const _n = _Some;
    size_hint$2 = _n > 0 ? _n : _M0MPB4Iter3newN6constrS726GUsRP39stillfail5rules4lock9PersonWebEE;
  }
  return new _M0TPB4IterGUsRP39stillfail5rules4lock9PersonWebEE(f, size_hint$2);
}
function _M0MPB4Iter3newGORPC14json4JsonE(f, size_hint) {
  let size_hint$2;
  if (size_hint === undefined) {
    size_hint$2 = undefined;
  } else {
    const _Some = size_hint;
    const _n = _Some;
    size_hint$2 = _n > 0 ? _n : _M0MPB4Iter3newN6constrS792GORPC14json4JsonE;
  }
  return new _M0TPB4IterGORPC14json4JsonE(f, size_hint$2);
}
function _M0MPB4Iter3newGcE(f, size_hint) {
  let size_hint$2;
  if (size_hint === undefined) {
    size_hint$2 = undefined;
  } else {
    const _Some = size_hint;
    const _n = _Some;
    size_hint$2 = _n > 0 ? _n : _M0MPB4Iter3newN6constrS798GcE;
  }
  return new _M0TPB4IterGcE(f, size_hint$2);
}
function _M0MPC15array10FixedArray5makeiGiE(length, value) {
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
function _M0MPC15array10FixedArray5makeiGbE(length, value) {
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
function _M0MPC16string10StringView4iter(self) {
  const start = self.start;
  const end = self.end;
  const index = new _M0TPB8MutLocalGiE(start);
  return _M0MPB4Iter3newGcE(() => {
    if (index.val < end) {
      const c1 = self.str.charCodeAt(index.val);
      if (c1 >= 55296 && c1 <= 56319 && (index.val + 1 | 0) < self.end) {
        const c2 = self.str.charCodeAt(index.val + 1 | 0);
        if (c2 >= 56320 && c2 <= 57343) {
          index.val = index.val + 2 | 0;
          return _M0FPB32code__point__of__surrogate__pair(c1, c2);
        }
      }
      index.val = index.val + 1 | 0;
      return c1;
    } else {
      return -1;
    }
  }, undefined);
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
      return _M0MPC16string10StringView4findN6constrS994;
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
function _M0MPC16string6String11has__prefix(self, str) {
  return _M0MPC16string10StringView11has__prefix(new _M0TPC16string10StringView(self, 0, self.length), str);
}
function _M0MPC15array5Array13Array_2einnerGUssEE(capacity) {
  return capacity === 0 ? new _M0TPB5ArrayGUssEE([], 0) : new _M0TPB5ArrayGUssEE(new Array(capacity), 0);
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
function _M0MPC15array5Array8capacityGRP39stillfail5rules4lock4StmtE(self) {
  return self.buf.length;
}
function _M0MPC15array5Array8capacityGiE(self) {
  return self.buf.length;
}
function _M0MPC15array5Array14resize__bufferGRP39stillfail5rules4lock4StmtE(self, new_capacity) {
  const old_buf = self.buf;
  self.buf = [];
  const len = self.len;
  const copy_len = len < new_capacity ? len : new_capacity;
  const new_buf = _M0MPB18UninitializedArray23make__and__blit_2einnerGRP39stillfail5rules4lock4StmtE(old_buf, new_capacity, copy_len, 0, 0);
  self.buf = new_buf;
}
function _M0MPC15array5Array14resize__bufferGiE(self, new_capacity) {
  const old_buf = self.buf;
  self.buf = [];
  const len = self.len;
  const copy_len = len < new_capacity ? len : new_capacity;
  const new_buf = _M0MPB18UninitializedArray23make__and__blit_2einnerGiE(old_buf, new_capacity, copy_len, 0, 0);
  self.buf = new_buf;
}
function _M0MPC15array5Array7reallocGRP39stillfail5rules4lock4StmtE(self, required) {
  const old_cap = _M0MPC15array5Array8capacityGRP39stillfail5rules4lock4StmtE(self);
  const new_cap = _M0FPB23array__growth__capacity(old_cap, self.len, required);
  _M0MPC15array5Array14resize__bufferGRP39stillfail5rules4lock4StmtE(self, new_cap);
}
function _M0MPC15array5Array7reallocGiE(self, required) {
  const old_cap = _M0MPC15array5Array8capacityGiE(self);
  const new_cap = _M0FPB23array__growth__capacity(old_cap, self.len, required);
  _M0MPC15array5Array14resize__bufferGiE(self, new_cap);
}
function _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(self, value) {
  if (self.len === self.buf.length) {
    _M0MPC15array5Array7reallocGRP39stillfail5rules4lock4StmtE(self, self.len + 1 | 0);
  }
  const length = self.len;
  self.buf[length] = value;
  self.len = length + 1 | 0;
}
function _M0MPC15array5Array4pushGiE(self, value) {
  if (self.len === self.buf.length) {
    _M0MPC15array5Array7reallocGiE(self, self.len + 1 | 0);
  }
  const length = self.len;
  self.buf[length] = value;
  self.len = length + 1 | 0;
}
function _M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(self, f) {
  return new _M0TPB4IterGRPC14json4JsonE(() => {
    const _bind = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(self);
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _x = _Some;
      return f(_x);
    }
  }, self.size_hint);
}
function _M0MPB4Iter3mapGcRPC16string10StringViewE(self, f) {
  return new _M0TPB4IterGRPC16string10StringViewE(() => {
    const _bind = _M0MPB4Iter4nextGcE(self);
    if (_bind === -1) {
      return undefined;
    } else {
      const _Some = _bind;
      const _x = _Some;
      return f(_x);
    }
  }, self.size_hint);
}
function _M0IPC14char4CharPB4Show10to__string(self) {
  return String.fromCodePoint(self);
}
function _M0MPC16string10StringView5split(self, sep) {
  const sep_len = sep.end - sep.start | 0;
  if (sep_len === 0) {
    return _M0MPB4Iter3mapGcRPC16string10StringViewE(_M0MPC16string10StringView4iter(self), (c) => {
      const _bind = _M0IPC14char4CharPB4Show10to__string(c);
      return new _M0TPC16string10StringView(_bind, 0, _bind.length);
    });
  }
  const remaining = new _M0TPB8MutLocalGORPC16string10StringViewE(self);
  return _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(() => {
    const _bind = remaining.val;
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _view = _Some;
      const _bind$2 = _M0MPC16string10StringView4find(_view, sep);
      if (_bind$2 === undefined) {
        remaining.val = undefined;
        return _view;
      } else {
        const _Some$2 = _bind$2;
        const _end = _Some$2;
        remaining.val = _M0MPC16string10StringView12unsafe__view(_view, _end + sep_len | 0, _view.end - _view.start | 0);
        return _M0MPC16string10StringView12unsafe__view(_view, 0, _end);
      }
    }
  }, undefined);
}
function _M0MPC16string6String5split(self, sep) {
  return _M0MPC16string10StringView5split(new _M0TPC16string10StringView(self, 0, self.length), sep);
}
function _M0MPB4Iter9to__arrayGUssEE(self) {
  const _bind = self.size_hint;
  let result;
  if (_bind === undefined) {
    result = new _M0TPB5ArrayGUssEE([], 0);
  } else {
    const _Some = _bind;
    const _n = _Some;
    result = _M0MPC15array5Array13Array_2einnerGUssEE(_n);
  }
  while (true) {
    const _bind$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(self);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(result, _x);
      continue;
    }
  }
  return result;
}
function _M0IPC16string6StringPB7Compare7compare(self, other) {
  const len = self.length;
  const _bind = $compare_int(len, other.length);
  if (_bind === 0) {
    let _tmp = 0;
    while (true) {
      const i = _tmp;
      if (i < len) {
        const x = self.charCodeAt(i);
        const y = other.charCodeAt(i);
        if (x !== y) {
          return x < y ? -1 : 1;
        }
        _tmp = i + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    return 0;
  } else {
    return _bind;
  }
}
function _M0IPC13int3IntPB4Show10to__string(self) {
  return _M0MPC13int3Int18to__string_2einner(self, 10);
}
function _M0MPC15array9ArrayView4iterGRP39stillfail5rules4lock4StmtE(self) {
  const i = new _M0TPB8MutLocalGiE(0);
  const len = self.end - self.start | 0;
  return _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(() => {
    if (i.val < len) {
      const elem = self.buf[self.start + i.val | 0];
      i.val = i.val + 1 | 0;
      return elem;
    } else {
      return undefined;
    }
  }, len);
}
function _M0MPC15array9ArrayView4iterGORPC14json4JsonE(self) {
  const i = new _M0TPB8MutLocalGiE(0);
  const len = self.end - self.start | 0;
  return _M0MPB4Iter3newGORPC14json4JsonE(() => {
    if (i.val < len) {
      const elem = self.buf[self.start + i.val | 0];
      i.val = i.val + 1 | 0;
      return new _M0DTPC16option6OptionGORPC14json4JsonE4Some(elem);
    } else {
      return _M0DTPC16option6OptionGORPC14json4JsonE4None__;
    }
  }, len);
}
function _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(self) {
  return _M0MPC15array9ArrayView4iterGRP39stillfail5rules4lock4StmtE(new _M0TPB9ArrayViewGRP39stillfail5rules4lock4StmtE(self.buf, 0, self.len));
}
function _M0MPC15array5Array4iterGORPC14json4JsonE(self) {
  return _M0MPC15array9ArrayView4iterGORPC14json4JsonE(new _M0TPB9ArrayViewGORPC14json4JsonE(self.buf, 0, self.len));
}
function _M0MPC15array5Array20unsafe__make__uninitGUssEE(len) {
  return new _M0TPB5ArrayGUssEE(new Array(len), len);
}
function _M0MPC15array5Array20unsafe__make__uninitGORPC14json4JsonE(len) {
  return new _M0TPB5ArrayGORPC14json4JsonE(new Array(len), len);
}
function _M0MPC15array5Array20unsafe__make__uninitGiE(len) {
  return new _M0TPB5ArrayGiE(new Array(len), len);
}
function _M0IPC16option6OptionPB2Eq5equalGRPC14json4JsonE(self, other) {
  if (self === undefined) {
    return other === undefined;
  } else {
    const _Some = self;
    const _x = _Some;
    if (other === undefined) {
      return false;
    } else {
      const _Some$2 = other;
      const _y = _Some$2;
      return _M0IPC14json4JsonPB2Eq5equal(_x, _y);
    }
  }
}
function _M0IPC16option6OptionPB2Eq5equalGsE(self, other) {
  if (self === undefined) {
    return other === undefined;
  } else {
    const _Some = self;
    const _x = _Some;
    if (other === undefined) {
      return false;
    } else {
      const _Some$2 = other;
      const _y = _Some$2;
      return _x === _y;
    }
  }
}
function _M0IPC16option6OptionPB2Eq5equalGdE(self, other) {
  if (self.$tag === 0) {
    if (other.$tag === 0) {
      return true;
    } else {
      return false;
    }
  } else {
    const _Some = self;
    const _x = _Some._0;
    if (other.$tag === 1) {
      const _Some$2 = other;
      const _y = _Some$2._0;
      return _x === _y;
    } else {
      return false;
    }
  }
}
function _M0MPC16option6Option6unwrapGdE(self) {
  if (self.$tag === 0) {
    return $panic();
  } else {
    const _Some = self;
    return _Some._0;
  }
}
function _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(self, default_) {
  if (self === undefined) {
    return default_;
  } else {
    const _Some = self;
    const _t = _Some;
    return _t;
  }
}
function _M0MPC16option6Option10unwrap__orGRP39stillfail5rules4fork4StepE(self, default_) {
  if (self === undefined) {
    return default_;
  } else {
    const _Some = self;
    const _t = _Some;
    return _t;
  }
}
function _M0MPC16option6Option10unwrap__orGdE(self, default_) {
  if (self.$tag === 1) {
    const _Some = self;
    const _t = _Some._0;
    return _t;
  } else {
    return default_;
  }
}
function _M0MPC16option6Option10unwrap__orGbE(self, default_) {
  if (self === -1) {
    return default_;
  } else {
    const _Some = self;
    const _t = _Some;
    return _t;
  }
}
function _M0MPC16option6Option3mapGUsssEsE(self, f) {
  if (self === undefined) {
    return undefined;
  } else {
    const _Some = self;
    const _t = _Some;
    return f(_t);
  }
}
function _M0MPC16option6Option3mapGRP39stillfail5rules4lock6MembersE(self, f) {
  if (self === undefined) {
    return undefined;
  } else {
    const _Some = self;
    const _t = _Some;
    return f(_t);
  }
}
function _M0MPC16option6Option3mapGUssEbE(self, f) {
  if (self === undefined) {
    return -1;
  } else {
    const _Some = self;
    const _t = _Some;
    return f(_t);
  }
}
function _M0FPB21calc__grow__threshold(capacity) {
  return (Math.imul(capacity / 16 | 0, 13) | 0) + ((Math.imul(capacity % 16 | 0, 13) | 0) / 16 | 0) | 0;
}
function _M0MPC13int3Int20next__power__of__two(self) {
  if (self >= 0) {
    if (self <= 1) {
      return 1;
    }
    if (self > 1073741824) {
      return 1073741824;
    }
    return (2147483647 >> (Math.clz32(self - 1 | 0) - 1 | 0)) + 1 | 0;
  } else {
    return $panic();
  }
}
function _M0FPB8new__mapGsiE(capacity) {
  const capacity$2 = _M0MPC13int3Int20next__power__of__two(capacity);
  const _bind = capacity$2 - 1 | 0;
  const _bind$2 = _M0FPB21calc__grow__threshold(capacity$2);
  const _bind$3 = $make_array_len_and_init(capacity$2, undefined);
  const _bind$4 = undefined;
  return new _M0TPB3MapGsiE(_bind$3, 0, capacity$2, _bind, _bind$2, _bind$4, -1);
}
function _M0FPB8new__mapGsUssOsEE(capacity) {
  const capacity$2 = _M0MPC13int3Int20next__power__of__two(capacity);
  const _bind = capacity$2 - 1 | 0;
  const _bind$2 = _M0FPB21calc__grow__threshold(capacity$2);
  const _bind$3 = $make_array_len_and_init(capacity$2, undefined);
  const _bind$4 = undefined;
  return new _M0TPB3MapGsUssOsEE(_bind$3, 0, capacity$2, _bind, _bind$2, _bind$4, -1);
}
function _M0FPB8new__mapGsuE(capacity) {
  const capacity$2 = _M0MPC13int3Int20next__power__of__two(capacity);
  const _bind = capacity$2 - 1 | 0;
  const _bind$2 = _M0FPB21calc__grow__threshold(capacity$2);
  const _bind$3 = $make_array_len_and_init(capacity$2, undefined);
  const _bind$4 = undefined;
  return new _M0TPB3MapGsuE(_bind$3, 0, capacity$2, _bind, _bind$2, _bind$4, -1);
}
function _M0FPB8new__mapGiRP39stillfail5rules4lock3OffE(capacity) {
  const capacity$2 = _M0MPC13int3Int20next__power__of__two(capacity);
  const _bind = capacity$2 - 1 | 0;
  const _bind$2 = _M0FPB21calc__grow__threshold(capacity$2);
  const _bind$3 = $make_array_len_and_init(capacity$2, undefined);
  const _bind$4 = undefined;
  return new _M0TPB3MapGiRP39stillfail5rules4lock3OffE(_bind$3, 0, capacity$2, _bind, _bind$2, _bind$4, -1);
}
function _M0FPB21capacity__for__length(length) {
  if (length <= _M0FPB21calc__grow__threshold(1073741824)) {
    let capacity = _M0MPC13int3Int20next__power__of__two(length);
    if (length > _M0FPB21calc__grow__threshold(capacity)) {
      capacity = Math.imul(capacity, 2) | 0;
    }
    return capacity;
  } else {
    return $panic("Map capacity overflow");
  }
}
function _M0MPB3Map20add__entry__to__tailGsiE(self, idx, entry) {
  const _bind = self.tail;
  if (_bind === -1) {
    self.head = entry;
  } else {
    const _tmp = self.entries;
    const _p = _bind >>> 0 < _tmp.length ? _tmp[_bind] : $oob();
    let _tmp$2;
    if (_p === undefined) {
      _tmp$2 = $panic();
    } else {
      const _p$2 = _p;
      _tmp$2 = _p$2;
    }
    _tmp$2.next = entry;
  }
  self.tail = idx;
  self.entries[idx] = entry;
  self.size = self.size + 1 | 0;
}
function _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry) {
  const _bind = self.tail;
  if (_bind === -1) {
    self.head = entry;
  } else {
    const _tmp = self.entries;
    const _p = _bind >>> 0 < _tmp.length ? _tmp[_bind] : $oob();
    let _tmp$2;
    if (_p === undefined) {
      _tmp$2 = $panic();
    } else {
      const _p$2 = _p;
      _tmp$2 = _p$2;
    }
    _tmp$2.next = entry;
  }
  self.tail = idx;
  self.entries[idx] = entry;
  self.size = self.size + 1 | 0;
}
function _M0MPB3Map20add__entry__to__tailGsuE(self, idx, entry) {
  const _bind = self.tail;
  if (_bind === -1) {
    self.head = entry;
  } else {
    const _tmp = self.entries;
    const _p = _bind >>> 0 < _tmp.length ? _tmp[_bind] : $oob();
    let _tmp$2;
    if (_p === undefined) {
      _tmp$2 = $panic();
    } else {
      const _p$2 = _p;
      _tmp$2 = _p$2;
    }
    _tmp$2.next = entry;
  }
  self.tail = idx;
  self.entries[idx] = entry;
  self.size = self.size + 1 | 0;
}
function _M0MPB3Map20add__entry__to__tailGiRP39stillfail5rules4lock3OffE(self, idx, entry) {
  const _bind = self.tail;
  if (_bind === -1) {
    self.head = entry;
  } else {
    const _tmp = self.entries;
    const _p = _bind >>> 0 < _tmp.length ? _tmp[_bind] : $oob();
    let _tmp$2;
    if (_p === undefined) {
      _tmp$2 = $panic();
    } else {
      const _p$2 = _p;
      _tmp$2 = _p$2;
    }
    _tmp$2.next = entry;
  }
  self.tail = idx;
  self.entries[idx] = entry;
  self.size = self.size + 1 | 0;
}
function _M0MPB3Map10set__entryGsiE(self, entry, new_idx) {
  const _bind = entry.next;
  if (_bind === undefined) {
    self.tail = new_idx;
  } else {
    const _Some = _bind;
    const _next = _Some;
    _next.prev = new_idx;
  }
  self.entries[new_idx] = entry;
}
function _M0MPB3Map10set__entryGsUssOsEE(self, entry, new_idx) {
  const _bind = entry.next;
  if (_bind === undefined) {
    self.tail = new_idx;
  } else {
    const _Some = _bind;
    const _next = _Some;
    _next.prev = new_idx;
  }
  self.entries[new_idx] = entry;
}
function _M0MPB3Map10set__entryGsuE(self, entry, new_idx) {
  const _bind = entry.next;
  if (_bind === undefined) {
    self.tail = new_idx;
  } else {
    const _Some = _bind;
    const _next = _Some;
    _next.prev = new_idx;
  }
  self.entries[new_idx] = entry;
}
function _M0MPB3Map10set__entryGiRP39stillfail5rules4lock3OffE(self, entry, new_idx) {
  const _bind = entry.next;
  if (_bind === undefined) {
    self.tail = new_idx;
  } else {
    const _Some = _bind;
    const _next = _Some;
    _next.prev = new_idx;
  }
  self.entries[new_idx] = entry;
}
function _M0MPB3Map10push__awayGsiE(self, idx, entry) {
  let _tmp = entry.psl + 1 | 0;
  let _tmp$2 = idx + 1 & self.capacity_mask;
  let _tmp$3 = entry;
  while (true) {
    const psl = _tmp;
    const idx$2 = _tmp$2;
    const entry$2 = _tmp$3;
    const _bind = self.entries[idx$2];
    if (_bind === undefined) {
      entry$2.psl = psl;
      _M0MPB3Map10set__entryGsiE(self, entry$2, idx$2);
      return;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (psl > _curr_entry.psl) {
        entry$2.psl = psl;
        _M0MPB3Map10set__entryGsiE(self, entry$2, idx$2);
        _tmp = _curr_entry.psl + 1 | 0;
        _tmp$2 = idx$2 + 1 & self.capacity_mask;
        _tmp$3 = _curr_entry;
        continue;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx$2 + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map10push__awayGsUssOsEE(self, idx, entry) {
  let _tmp = entry.psl + 1 | 0;
  let _tmp$2 = idx + 1 & self.capacity_mask;
  let _tmp$3 = entry;
  while (true) {
    const psl = _tmp;
    const idx$2 = _tmp$2;
    const entry$2 = _tmp$3;
    const _bind = self.entries[idx$2];
    if (_bind === undefined) {
      entry$2.psl = psl;
      _M0MPB3Map10set__entryGsUssOsEE(self, entry$2, idx$2);
      return;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (psl > _curr_entry.psl) {
        entry$2.psl = psl;
        _M0MPB3Map10set__entryGsUssOsEE(self, entry$2, idx$2);
        _tmp = _curr_entry.psl + 1 | 0;
        _tmp$2 = idx$2 + 1 & self.capacity_mask;
        _tmp$3 = _curr_entry;
        continue;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx$2 + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map10push__awayGsuE(self, idx, entry) {
  let _tmp = entry.psl + 1 | 0;
  let _tmp$2 = idx + 1 & self.capacity_mask;
  let _tmp$3 = entry;
  while (true) {
    const psl = _tmp;
    const idx$2 = _tmp$2;
    const entry$2 = _tmp$3;
    const _bind = self.entries[idx$2];
    if (_bind === undefined) {
      entry$2.psl = psl;
      _M0MPB3Map10set__entryGsuE(self, entry$2, idx$2);
      return;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (psl > _curr_entry.psl) {
        entry$2.psl = psl;
        _M0MPB3Map10set__entryGsuE(self, entry$2, idx$2);
        _tmp = _curr_entry.psl + 1 | 0;
        _tmp$2 = idx$2 + 1 & self.capacity_mask;
        _tmp$3 = _curr_entry;
        continue;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx$2 + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map10push__awayGiRP39stillfail5rules4lock3OffE(self, idx, entry) {
  let _tmp = entry.psl + 1 | 0;
  let _tmp$2 = idx + 1 & self.capacity_mask;
  let _tmp$3 = entry;
  while (true) {
    const psl = _tmp;
    const idx$2 = _tmp$2;
    const entry$2 = _tmp$3;
    const _bind = self.entries[idx$2];
    if (_bind === undefined) {
      entry$2.psl = psl;
      _M0MPB3Map10set__entryGiRP39stillfail5rules4lock3OffE(self, entry$2, idx$2);
      return;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (psl > _curr_entry.psl) {
        entry$2.psl = psl;
        _M0MPB3Map10set__entryGiRP39stillfail5rules4lock3OffE(self, entry$2, idx$2);
        _tmp = _curr_entry.psl + 1 | 0;
        _tmp$2 = idx$2 + 1 & self.capacity_mask;
        _tmp$3 = _curr_entry;
        continue;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx$2 + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map20rehash__place__entryGsiE(self, outer) {
  const hash = outer.hash;
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      outer.psl = psl;
      outer.prev = self.tail;
      _M0MPB3Map20add__entry__to__tailGsiE(self, idx, outer);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr = _Some;
      if (psl > _curr.psl) {
        _M0MPB3Map10push__awayGsiE(self, idx, _curr);
        outer.psl = psl;
        outer.prev = self.tail;
        _M0MPB3Map20add__entry__to__tailGsiE(self, idx, outer);
        return undefined;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map20rehash__place__entryGsUssOsEE(self, outer) {
  const hash = outer.hash;
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      outer.psl = psl;
      outer.prev = self.tail;
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, outer);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr = _Some;
      if (psl > _curr.psl) {
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr);
        outer.psl = psl;
        outer.prev = self.tail;
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, outer);
        return undefined;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map20rehash__place__entryGsuE(self, outer) {
  const hash = outer.hash;
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      outer.psl = psl;
      outer.prev = self.tail;
      _M0MPB3Map20add__entry__to__tailGsuE(self, idx, outer);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr = _Some;
      if (psl > _curr.psl) {
        _M0MPB3Map10push__awayGsuE(self, idx, _curr);
        outer.psl = psl;
        outer.prev = self.tail;
        _M0MPB3Map20add__entry__to__tailGsuE(self, idx, outer);
        return undefined;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map20rehash__place__entryGiRP39stillfail5rules4lock3OffE(self, outer) {
  const hash = outer.hash;
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      outer.psl = psl;
      outer.prev = self.tail;
      _M0MPB3Map20add__entry__to__tailGiRP39stillfail5rules4lock3OffE(self, idx, outer);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr = _Some;
      if (psl > _curr.psl) {
        _M0MPB3Map10push__awayGiRP39stillfail5rules4lock3OffE(self, idx, _curr);
        outer.psl = psl;
        outer.prev = self.tail;
        _M0MPB3Map20add__entry__to__tailGiRP39stillfail5rules4lock3OffE(self, idx, outer);
        return undefined;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map4growGsiE(self) {
  const old_head = self.head;
  const new_capacity = self.capacity << 1;
  self.entries = $make_array_len_and_init(new_capacity, undefined);
  self.capacity = new_capacity;
  self.capacity_mask = new_capacity - 1 | 0;
  self.grow_at = _M0FPB21calc__grow__threshold(self.capacity);
  self.size = 0;
  self.head = undefined;
  self.tail = -1;
  let _tmp = old_head;
  while (true) {
    const x = _tmp;
    if (x === undefined) {
      return;
    } else {
      const _Some = x;
      const _e = _Some;
      const next_in_chain = _e.next;
      _e.next = undefined;
      _M0MPB3Map20rehash__place__entryGsiE(self, _e);
      _tmp = next_in_chain;
      continue;
    }
  }
}
function _M0MPB3Map4growGsUssOsEE(self) {
  const old_head = self.head;
  const new_capacity = self.capacity << 1;
  self.entries = $make_array_len_and_init(new_capacity, undefined);
  self.capacity = new_capacity;
  self.capacity_mask = new_capacity - 1 | 0;
  self.grow_at = _M0FPB21calc__grow__threshold(self.capacity);
  self.size = 0;
  self.head = undefined;
  self.tail = -1;
  let _tmp = old_head;
  while (true) {
    const x = _tmp;
    if (x === undefined) {
      return;
    } else {
      const _Some = x;
      const _e = _Some;
      const next_in_chain = _e.next;
      _e.next = undefined;
      _M0MPB3Map20rehash__place__entryGsUssOsEE(self, _e);
      _tmp = next_in_chain;
      continue;
    }
  }
}
function _M0MPB3Map4growGsuE(self) {
  const old_head = self.head;
  const new_capacity = self.capacity << 1;
  self.entries = $make_array_len_and_init(new_capacity, undefined);
  self.capacity = new_capacity;
  self.capacity_mask = new_capacity - 1 | 0;
  self.grow_at = _M0FPB21calc__grow__threshold(self.capacity);
  self.size = 0;
  self.head = undefined;
  self.tail = -1;
  let _tmp = old_head;
  while (true) {
    const x = _tmp;
    if (x === undefined) {
      return;
    } else {
      const _Some = x;
      const _e = _Some;
      const next_in_chain = _e.next;
      _e.next = undefined;
      _M0MPB3Map20rehash__place__entryGsuE(self, _e);
      _tmp = next_in_chain;
      continue;
    }
  }
}
function _M0MPB3Map4growGiRP39stillfail5rules4lock3OffE(self) {
  const old_head = self.head;
  const new_capacity = self.capacity << 1;
  self.entries = $make_array_len_and_init(new_capacity, undefined);
  self.capacity = new_capacity;
  self.capacity_mask = new_capacity - 1 | 0;
  self.grow_at = _M0FPB21calc__grow__threshold(self.capacity);
  self.size = 0;
  self.head = undefined;
  self.tail = -1;
  let _tmp = old_head;
  while (true) {
    const x = _tmp;
    if (x === undefined) {
      return;
    } else {
      const _Some = x;
      const _e = _Some;
      const next_in_chain = _e.next;
      _e.next = undefined;
      _M0MPB3Map20rehash__place__entryGiRP39stillfail5rules4lock3OffE(self, _e);
      _tmp = next_in_chain;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsiE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsiE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsiE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsiE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsiE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsiE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsiE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsiE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsUssOsEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsUssOsEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsUssOsEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock12PersonDeviceE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock12PersonDeviceE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock12PersonDeviceE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGssE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGssE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGssE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRPC14json4JsonE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRPC14json4JsonE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRPC14json4JsonE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock6DeviceE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock6DeviceE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock6DeviceE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules5vault6DeviceE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules5vault6DeviceE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules5vault6DeviceE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsuE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsuE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsuE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsuE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsuE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsuE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsuE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsuE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRPB5ArrayGiEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRPB5ArrayGiEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRPB5ArrayGiEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGiRP39stillfail5rules4lock3OffE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGiRP39stillfail5rules4lock3OffE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGiRP39stillfail5rules4lock3OffE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGiRP39stillfail5rules4lock3OffE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGiRP39stillfail5rules4lock3OffE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGiRP39stillfail5rules4lock3OffE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGiRP39stillfail5rules4lock3OffE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGiRP39stillfail5rules4lock3OffE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRPB5ArrayGsEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRPB5ArrayGsEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRPB5ArrayGsEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock6MemberE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock6MemberE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock6MemberE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock7StationE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock7StationE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock7StationE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock7PasskeyE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock7PasskeyE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock7PasskeyE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsUssEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsUssEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsUssEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsUsssEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsUsssEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsUsssEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock4StmtE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock4StmtE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock4StmtE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock9PersonWebE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsUssOsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock9PersonWebE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (_curr_entry.hash === hash && _curr_entry.key === key) {
        _curr_entry.value = value;
        return undefined;
      }
      if (psl > _curr_entry.psl) {
        if (self.size >= self.grow_at) {
          _M0MPB3Map4growGsUssOsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsUssOsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock9PersonWebE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsUssOsEE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3setGsiE(self, key, value) {
  _M0MPB3Map15set__with__hashGsiE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsUssOsEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsUssOsEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock12PersonDeviceE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock12PersonDeviceE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGssE(self, key, value) {
  _M0MPB3Map15set__with__hashGssE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRPC14json4JsonE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRPC14json4JsonE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock6DeviceE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock6DeviceE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules5vault6DeviceE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules5vault6DeviceE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsuE(self, key, value) {
  _M0MPB3Map15set__with__hashGsuE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRPB5ArrayGiEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRPB5ArrayGiEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGiRP39stillfail5rules4lock3OffE(self, key, value) {
  _M0MPB3Map15set__with__hashGiRP39stillfail5rules4lock3OffE(self, key, value, _M0IPC13int3IntPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRPB5ArrayGsEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRPB5ArrayGsEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock6MemberE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock6MemberE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock7StationE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock7StationE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock7PasskeyE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock7PasskeyE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsUssEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsUssEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsUsssEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsUsssEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock4StmtE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock4StmtE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock9PersonWebE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock9PersonWebE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3MapGsiE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsiE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsiE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsUssOsEE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsUssOsEE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules4lock12PersonDeviceE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules4lock12PersonDeviceE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGssE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGssE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRPC14json4JsonE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRPC14json4JsonE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules5vault6DeviceE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules5vault6DeviceE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules4lock6DeviceE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules4lock6DeviceE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsuE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsuE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsuE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRPB5ArrayGiEE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRPB5ArrayGiEE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGiRP39stillfail5rules4lock3OffE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGiRP39stillfail5rules4lock3OffE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGiRP39stillfail5rules4lock3OffE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRPB5ArrayGsEE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRPB5ArrayGsEE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules4lock6MemberE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules4lock6MemberE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules4lock7StationE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules4lock7StationE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules4lock7PasskeyE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules4lock7PasskeyE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsUsssEE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsUsssEE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsUssEE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsUssEE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules4lock4StmtE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules4lock4StmtE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3MapGsRP39stillfail5rules4lock9PersonWebE(arr, capacity) {
  const length = arr.end - arr.start | 0;
  let capacity$2;
  if (capacity === undefined) {
    capacity$2 = length === 0 ? 8 : _M0FPB21capacity__for__length(length);
  } else {
    const _Some = capacity;
    const _capacity = _Some;
    capacity$2 = _M0FPB21capacity__for__length(_capacity > length ? _capacity : length);
  }
  const m = _M0FPB8new__mapGsUssOsEE(capacity$2);
  const _bind = arr.end - arr.start | 0;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = arr.buf[arr.start + _ | 0];
      _M0MPB3Map3setGsRP39stillfail5rules4lock9PersonWebE(m, e._0, e._1);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return m;
}
function _M0MPB3Map3getGsiE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsUssOsEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGssE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRPC14json4JsonE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRP39stillfail5rules5vault6DeviceE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGiRP39stillfail5rules4lock3OffE(self, key) {
  const hash = _M0IPC13int3IntPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRPB5ArrayGiEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRPB5ArrayGsEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRP39stillfail5rules4lock7PasskeyE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsUsssEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRP39stillfail5rules4lock4StmtE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3getGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return _entry.value;
      }
      if (i > _entry.psl) {
        return undefined;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map8containsGsiE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map8containsGssE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map8containsGsRP39stillfail5rules4lock12PersonDeviceE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map8containsGsuE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map8containsGiRP39stillfail5rules4lock3OffE(self, key) {
  const hash = _M0IPC13int3IntPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map8containsGsRPB5ArrayGiEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map8containsGsRP39stillfail5rules4lock6MemberE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map8containsGsUssEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map12contains__kvGsRPC14json4JsonE(self, key, value) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && (_entry.key === key && _M0IPC14json4JsonPB2Eq5equal(_entry.value, value))) {
        return true;
      }
      if (i > _entry.psl) {
        return false;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, entry) {
  const _bind = entry.prev;
  if (_bind === -1) {
    self.head = entry.next;
  } else {
    const _tmp = self.entries;
    const _p = _bind >>> 0 < _tmp.length ? _tmp[_bind] : $oob();
    let _tmp$2;
    if (_p === undefined) {
      _tmp$2 = $panic();
    } else {
      const _p$2 = _p;
      _tmp$2 = _p$2;
    }
    _tmp$2.next = entry.next;
  }
  const _bind$2 = entry.next;
  if (_bind$2 === undefined) {
    self.tail = entry.prev;
    return;
  } else {
    const _Some = _bind$2;
    const _next = _Some;
    _next.prev = entry.prev;
    return;
  }
}
function _M0MPB3Map13remove__entryGsuE(self, entry) {
  const _bind = entry.prev;
  if (_bind === -1) {
    self.head = entry.next;
  } else {
    const _tmp = self.entries;
    const _p = _bind >>> 0 < _tmp.length ? _tmp[_bind] : $oob();
    let _tmp$2;
    if (_p === undefined) {
      _tmp$2 = $panic();
    } else {
      const _p$2 = _p;
      _tmp$2 = _p$2;
    }
    _tmp$2.next = entry.next;
  }
  const _bind$2 = entry.next;
  if (_bind$2 === undefined) {
    self.tail = entry.prev;
    return;
  } else {
    const _Some = _bind$2;
    const _next = _Some;
    _next.prev = entry.prev;
    return;
  }
}
function _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx) {
  let _tmp = idx;
  while (true) {
    const cur = _tmp;
    const next = cur + 1 & self.capacity_mask;
    _L: {
      const _bind = self.entries[next];
      if (_bind === undefined) {
        break _L;
      } else {
        const _Some = _bind;
        const _x = _Some;
        const _x$2 = _x.psl;
        if (_x$2 === 0) {
          break _L;
        } else {
          _x.psl = _x.psl - 1 | 0;
          _M0MPB3Map10set__entryGsUssOsEE(self, _x, cur);
          _tmp = next;
          continue;
        }
      }
    }
    self.entries[cur] = undefined;
    return;
  }
}
function _M0MPB3Map11shift__backGsuE(self, idx) {
  let _tmp = idx;
  while (true) {
    const cur = _tmp;
    const next = cur + 1 & self.capacity_mask;
    _L: {
      const _bind = self.entries[next];
      if (_bind === undefined) {
        break _L;
      } else {
        const _Some = _bind;
        const _x = _Some;
        const _x$2 = _x.psl;
        if (_x$2 === 0) {
          break _L;
        } else {
          _x.psl = _x.psl - 1 | 0;
          _M0MPB3Map10set__entryGsuE(self, _x, cur);
          _tmp = next;
          continue;
        }
      }
    }
    self.entries[cur] = undefined;
    return;
  }
}
function _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock12PersonDeviceE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map18remove__with__hashGssE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock6DeviceE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map18remove__with__hashGsuE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsuE(self, _entry);
        _M0MPB3Map11shift__backGsuE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock6MemberE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock7StationE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock7PasskeyE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map18remove__with__hashGsUssEE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock9PersonWebE(self, key, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock12PersonDeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock12PersonDeviceE(self, idx);
        self.size = self.size - 1 | 0;
        return;
      }
      if (i > _entry.psl) {
        return;
      }
      _tmp = i + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map6removeGsRP39stillfail5rules4lock12PersonDeviceE(self, key) {
  _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock12PersonDeviceE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map6removeGssE(self, key) {
  _M0MPB3Map18remove__with__hashGssE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map6removeGsRP39stillfail5rules4lock6DeviceE(self, key) {
  _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock6DeviceE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map6removeGsuE(self, key) {
  _M0MPB3Map18remove__with__hashGsuE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map6removeGsRP39stillfail5rules4lock6MemberE(self, key) {
  _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock6MemberE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map6removeGsRP39stillfail5rules4lock7StationE(self, key) {
  _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock7StationE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map6removeGsRP39stillfail5rules4lock7PasskeyE(self, key) {
  _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock7PasskeyE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map6removeGsUssEE(self, key) {
  _M0MPB3Map18remove__with__hashGsUssEE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map6removeGsRP39stillfail5rules4lock9PersonWebE(self, key) {
  _M0MPB3Map18remove__with__hashGsRP39stillfail5rules4lock9PersonWebE(self, key, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPB5EntryGsRP39stillfail5rules4lock12PersonDeviceEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(() => {
    _L: {
      if (remaining.val > 0) {
        const _bind = curr_entry.val;
        if (_bind === undefined) {
          break _L;
        } else {
          const _Some = _bind;
          const _x = _Some;
          const _key = _x.key;
          const _value = _x.value;
          const _next = _x.next;
          curr_entry.val = _next;
          remaining.val = remaining.val - 1 | 0;
          return { _0: _key, _1: _value };
        }
      } else {
        break _L;
      }
    }
    return undefined;
  }, len);
}
function _M0MPB3Map4iterGsuE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPB5EntryGsuEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(() => {
    _L: {
      if (remaining.val > 0) {
        const _bind = curr_entry.val;
        if (_bind === undefined) {
          break _L;
        } else {
          const _Some = _bind;
          const _x = _Some;
          const _key = _x.key;
          const _value = _x.value;
          const _next = _x.next;
          curr_entry.val = _next;
          remaining.val = remaining.val - 1 | 0;
          return { _0: _key, _1: _value };
        }
      } else {
        break _L;
      }
    }
    return undefined;
  }, len);
}
function _M0MPB3Map5iter2GssE(self) {
  return _M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(self);
}
function _M0MPB3Map5iter2GsuE(self) {
  return _M0MPB3Map4iterGsuE(self);
}
function _M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPB5EntryGsRP39stillfail5rules4lock12PersonDeviceEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(() => {
    _L: {
      if (remaining.val > 0) {
        const _bind = curr_entry.val;
        if (_bind === undefined) {
          break _L;
        } else {
          const _Some = _bind;
          const _x = _Some;
          const _key = _x.key;
          const _next = _x.next;
          curr_entry.val = _next;
          remaining.val = remaining.val - 1 | 0;
          return _key;
        }
      } else {
        break _L;
      }
    }
    return undefined;
  }, len);
}
function _M0MPB3Map4keysGsuE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPB5EntryGsuEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(() => {
    _L: {
      if (remaining.val > 0) {
        const _bind = curr_entry.val;
        if (_bind === undefined) {
          break _L;
        } else {
          const _Some = _bind;
          const _x = _Some;
          const _key = _x.key;
          const _next = _x.next;
          curr_entry.val = _next;
          remaining.val = remaining.val - 1 | 0;
          return _key;
        }
      } else {
        break _L;
      }
    }
    return undefined;
  }, len);
}
function _M0MPB3Map6valuesGsRP39stillfail5rules4lock12PersonDeviceE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPB5EntryGsRP39stillfail5rules4lock12PersonDeviceEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(() => {
    _L: {
      if (remaining.val > 0) {
        const _bind = curr_entry.val;
        if (_bind === undefined) {
          break _L;
        } else {
          const _Some = _bind;
          const _x = _Some;
          const _value = _x.value;
          const _next = _x.next;
          curr_entry.val = _next;
          remaining.val = remaining.val - 1 | 0;
          return _value;
        }
      } else {
        break _L;
      }
    }
    return undefined;
  }, len);
}
function _M0IPB3MapPB2Eq5equalGsRPC14json4JsonE(self, that) {
  if (self.size === that.size) {
    const _it = _M0MPB3Map5iter2GssE(self);
    while (true) {
      const _bind = _M0MPB5Iter24nextGssE(_it);
      if (_bind === undefined) {
        return true;
      } else {
        const _Some = _bind;
        const _x = _Some;
        const _k = _x._0;
        const _v = _x._1;
        if (_M0MPB3Map12contains__kvGsRPC14json4JsonE(that, _k, _v)) {
        } else {
          return false;
        }
        continue;
      }
    }
  } else {
    return false;
  }
}
function _M0MPB4Iter6filterGsE(self, f) {
  return _M0MPB4Iter3newGUsRP39stillfail5rules4lock9PersonWebEE(() => {
    while (true) {
      const _bind = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(self);
      if (_bind === undefined) {
        return undefined;
      } else {
        const _Some = _bind;
        const _x = _Some;
        if (f(_x)) {
          return _x;
        }
        continue;
      }
    }
  }, undefined);
}
function _M0MPB5Iter24nextGssE(self) {
  return _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(self);
}
function _M0MPB5Iter24nextGsuE(self) {
  return _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(self);
}
function _M0IPC16string6StringPB4Hash4hash(self) {
  let acc = (_M0FPB4seed__drawn() >>> 0) + (374761393 >>> 0) | 0;
  const _bind = self.length;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      acc = (acc >>> 0) + (4 >>> 0) | 0;
      const v = self.charCodeAt(i);
      acc = _M0FPB13consume4__acc(acc, v);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0FPB13finalize__acc(acc);
}
function _M0IPC13int3IntPB4Hash4hash(self) {
  const acc = (((_M0FPB4seed__drawn() >>> 0) + (374761393 >>> 0) | 0) >>> 0) + (4 >>> 0) | 0;
  return _M0FPB13finalize__acc(_M0FPB13consume4__acc(acc, self));
}
function _M0MPC16double6Double7to__int(self) {
  return self !== self ? 0 : self >= 2147483647 ? 2147483647 : self <= -2147483648 ? -2147483648 : self | 0;
}
function _M0MPC16double6Double5floor(_tmp) {
  return Math.floor(_tmp);
}
function _M0MPC16string6String12view_2einner(self, start_offset, end_offset) {
  let end_offset$2;
  if (end_offset === undefined) {
    end_offset$2 = self.length;
  } else {
    const _Some = end_offset;
    end_offset$2 = _Some;
  }
  return start_offset >= 0 && (start_offset <= end_offset$2 && end_offset$2 <= self.length) ? new _M0TPC16string10StringView(self, start_offset, end_offset$2) : $panic("Invalid index for View");
}
function _M0MPC15array12MutArrayView4swapGUssEE(arr, i, j) {
  const temp = arr.buf[arr.start + i | 0];
  arr.buf[arr.start + i | 0] = arr.buf[arr.start + j | 0];
  arr.buf[arr.start + j | 0] = temp;
}
function _M0MPC15array12MutArrayView4swapGiE(arr, i, j) {
  const temp = arr.buf[arr.start + i | 0];
  arr.buf[arr.start + i | 0] = arr.buf[arr.start + j | 0];
  arr.buf[arr.start + j | 0] = temp;
}
function _M0MPC15array12MutArrayView5sliceGUssEE(arr, start, end) {
  const _bind = arr.end - arr.start | 0;
  if (start < 0 || (start > end || end > _bind)) {
    $panic();
  }
  return new _M0TPB12MutArrayViewGUssEE(arr.buf, start + arr.start | 0, end + arr.start | 0);
}
function _M0MPC15array12MutArrayView5sliceGiE(arr, start, end) {
  const _bind = arr.end - arr.start | 0;
  if (start < 0 || (start > end || end > _bind)) {
    $panic();
  }
  return new _M0TPB12MutArrayViewGiE(arr.buf, start + arr.start | 0, end + arr.start | 0);
}
function _M0MPC15array12MutArrayView14rev__in__placeGUssEE(arr) {
  const len = arr.end - arr.start | 0;
  const mid_len = len / 2 | 0;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < mid_len) {
      const j = (len - i | 0) - 1 | 0;
      const temp = arr.buf[arr.start + i | 0];
      arr.buf[arr.start + i | 0] = arr.buf[arr.start + j | 0];
      arr.buf[arr.start + j | 0] = temp;
      _tmp = i + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0MPC15array12MutArrayView14rev__in__placeGiE(arr) {
  const len = arr.end - arr.start | 0;
  const mid_len = len / 2 | 0;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < mid_len) {
      const j = (len - i | 0) - 1 | 0;
      const temp = arr.buf[arr.start + i | 0];
      arr.buf[arr.start + i | 0] = arr.buf[arr.start + j | 0];
      arr.buf[arr.start + j | 0] = temp;
      _tmp = i + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB17fixed__get__limit(len) {
  let _tmp = len;
  let _tmp$2 = 0;
  while (true) {
    const len$2 = _tmp;
    const limit = _tmp$2;
    if (len$2 > 0) {
      _tmp = len$2 / 2 | 0;
      _tmp$2 = limit + 1 | 0;
      continue;
    } else {
      return limit;
    }
  }
}
function _M0FPB19fixed__bubble__sortGsE(arr) {
  const _bind = arr.end - arr.start | 0;
  let _tmp = 1;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      let _tmp$2 = i;
      while (true) {
        const j = _tmp$2;
        if (j > 0 && _M0IP016_24default__implPB7Compare6op__gtGsE(arr.buf[arr.start + (j - 1 | 0) | 0], arr.buf[arr.start + j | 0])) {
          _M0MPC15array12MutArrayView4swapGUssEE(arr, j, j - 1 | 0);
          _tmp$2 = j - 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB20fixed__choose__pivotN7sort__2S4174GsE(_env, a, b) {
  const arr = _env._1;
  const swaps = _env._0;
  if (_M0IP016_24default__implPB7Compare6op__gtGsE(arr.buf[arr.start + a | 0], arr.buf[arr.start + b | 0])) {
    _M0MPC15array12MutArrayView4swapGUssEE(arr, a, b);
    swaps.val = swaps.val + 1 | 0;
    return;
  } else {
    return;
  }
}
function _M0FPB20fixed__choose__pivotN7sort__3S4175GsE(_env, a, b, c) {
  _M0FPB20fixed__choose__pivotN7sort__2S4174GsE(_env, a, b);
  _M0FPB20fixed__choose__pivotN7sort__2S4174GsE(_env, b, c);
  _M0FPB20fixed__choose__pivotN7sort__2S4174GsE(_env, a, b);
}
function _M0FPB20fixed__choose__pivotGsE(arr) {
  const len = arr.end - arr.start | 0;
  const swaps = new _M0TPB8MutLocalGiE(0);
  const b = Math.imul(len / 4 | 0, 2) | 0;
  if (len >= 8) {
    const a = Math.imul(len / 4 | 0, 1) | 0;
    const c = Math.imul(len / 4 | 0, 3) | 0;
    const _env = { _0: swaps, _1: arr };
    if (len > 50) {
      _M0FPB20fixed__choose__pivotN7sort__3S4175GsE(_env, a - 1 | 0, a, a + 1 | 0);
      _M0FPB20fixed__choose__pivotN7sort__3S4175GsE(_env, b - 1 | 0, b, b + 1 | 0);
      _M0FPB20fixed__choose__pivotN7sort__3S4175GsE(_env, c - 1 | 0, c, c + 1 | 0);
    }
    _M0FPB20fixed__choose__pivotN7sort__3S4175GsE(_env, a, b, c);
  }
  if (swaps.val === 12) {
    _M0MPC15array12MutArrayView14rev__in__placeGUssEE(arr);
    return { _0: (len - b | 0) - 1 | 0, _1: true };
  } else {
    return { _0: b, _1: swaps.val === 0 };
  }
}
function _M0FPB17fixed__sift__downGsE(arr, index) {
  const len = arr.end - arr.start | 0;
  let _tmp = index;
  let _tmp$2 = (Math.imul(index, 2) | 0) + 1 | 0;
  while (true) {
    const index$2 = _tmp;
    const child = _tmp$2;
    if (child < len) {
      const child$2 = (child + 1 | 0) < len && _M0IP016_24default__implPB7Compare6op__ltGsE(arr.buf[arr.start + child | 0], arr.buf[arr.start + (child + 1 | 0) | 0]) ? child + 1 | 0 : child;
      if (_M0IP016_24default__implPB7Compare6op__geGsE(arr.buf[arr.start + index$2 | 0], arr.buf[arr.start + child$2 | 0])) {
        return undefined;
      }
      _M0MPC15array12MutArrayView4swapGUssEE(arr, index$2, child$2);
      _tmp = child$2;
      _tmp$2 = (Math.imul(child$2, 2) | 0) + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB17fixed__heap__sortGsE(arr) {
  const len = arr.end - arr.start | 0;
  const _bind = len / 2 | 0;
  let _tmp = _bind - 1 | 0;
  let _tmp$2 = _bind > 0;
  while (true) {
    const i = _tmp;
    const _more = _tmp$2;
    if (_more) {
      _M0FPB17fixed__sift__downGsE(arr, i);
      _tmp = i - 1 | 0;
      _tmp$2 = i > 0;
      continue;
    } else {
      break;
    }
  }
  let _tmp$3 = len - 1 | 0;
  let _tmp$4 = len > 1;
  while (true) {
    const i = _tmp$3;
    const _more = _tmp$4;
    if (_more) {
      _M0MPC15array12MutArrayView4swapGUssEE(arr, 0, i);
      _M0FPB17fixed__sift__downGsE(_M0MPC15array12MutArrayView5sliceGUssEE(arr, 0, i), 0);
      _tmp$3 = i - 1 | 0;
      _tmp$4 = i > 1;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB16fixed__partitionGsE(arr, pivot_index) {
  _M0MPC15array12MutArrayView4swapGUssEE(arr, pivot_index, (arr.end - arr.start | 0) - 1 | 0);
  const pivot = arr.buf[arr.start + ((arr.end - arr.start | 0) - 1 | 0) | 0];
  const _bind = (arr.end - arr.start | 0) - 1 | 0;
  let _tmp = 0;
  let _tmp$2 = 0;
  let _tmp$3 = true;
  while (true) {
    const j = _tmp;
    const i = _tmp$2;
    const partitioned = _tmp$3;
    if (j < _bind) {
      if (_M0IP016_24default__implPB7Compare6op__ltGsE(arr.buf[arr.start + j | 0], pivot)) {
        if (i !== j) {
          _M0MPC15array12MutArrayView4swapGUssEE(arr, i, j);
          _tmp = j + 1 | 0;
          _tmp$2 = i + 1 | 0;
          _tmp$3 = false;
          continue;
        } else {
          _tmp = j + 1 | 0;
          _tmp$2 = i + 1 | 0;
          continue;
        }
      } else {
        _tmp = j + 1 | 0;
        continue;
      }
    } else {
      _M0MPC15array12MutArrayView4swapGUssEE(arr, i, (arr.end - arr.start | 0) - 1 | 0);
      return { _0: i, _1: partitioned };
    }
  }
}
function _M0FPB24fixed__try__bubble__sortGsE(arr) {
  const _bind = arr.end - arr.start | 0;
  let _tmp = 1;
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp;
    const tries = _tmp$2;
    if (i < _bind) {
      let sorted;
      let _tmp$3 = i;
      let _tmp$4 = true;
      while (true) {
        const j = _tmp$3;
        const sorted$2 = _tmp$4;
        if (j > 0 && _M0IP016_24default__implPB7Compare6op__gtGsE(arr.buf[arr.start + (j - 1 | 0) | 0], arr.buf[arr.start + j | 0])) {
          _M0MPC15array12MutArrayView4swapGUssEE(arr, j, j - 1 | 0);
          _tmp$3 = j - 1 | 0;
          _tmp$4 = false;
          continue;
        } else {
          sorted = sorted$2;
          break;
        }
      }
      if (!sorted) {
        const tries$2 = tries + 1 | 0;
        if (tries$2 > 8) {
          return false;
        }
        _tmp = i + 1 | 0;
        _tmp$2 = tries$2;
        continue;
      } else {
        _tmp = i + 1 | 0;
        continue;
      }
    } else {
      return true;
    }
  }
}
function _M0FPB18fixed__quick__sortGsE(arr, pred, limit) {
  let _tmp = limit;
  let _tmp$2 = arr;
  let _tmp$3 = pred;
  let _tmp$4 = true;
  let _tmp$5 = true;
  while (true) {
    const limit$2 = _tmp;
    const arr$2 = _tmp$2;
    const pred$2 = _tmp$3;
    const was_partitioned = _tmp$4;
    const balanced = _tmp$5;
    const len = arr$2.end - arr$2.start | 0;
    if (len <= 16) {
      if (len >= 2) {
        _M0FPB19fixed__bubble__sortGsE(arr$2);
      }
      return undefined;
    }
    if (limit$2 === 0) {
      _M0FPB17fixed__heap__sortGsE(arr$2);
      return undefined;
    }
    const _bind = _M0FPB20fixed__choose__pivotGsE(arr$2);
    const _pivot_index = _bind._0;
    const _likely_sorted = _bind._1;
    if (was_partitioned && (balanced && _likely_sorted)) {
      if (_M0FPB24fixed__try__bubble__sortGsE(arr$2)) {
        return undefined;
      }
    }
    const _bind$2 = _M0FPB16fixed__partitionGsE(arr$2, _pivot_index);
    const _pivot = _bind$2._0;
    const _partitioned = _bind$2._1;
    const _p = len - _pivot | 0;
    const balanced$2 = (_pivot > _p ? _p : _pivot) >= (len / 8 | 0);
    const limit$3 = !balanced$2 ? limit$2 - 1 | 0 : limit$2;
    if (pred$2 === undefined) {
    } else {
      const _Some = pred$2;
      const _p$2 = _Some;
      if (_p$2 === arr$2.buf[arr$2.start + _pivot | 0]) {
        let i;
        let _tmp$6 = _pivot;
        while (true) {
          const i$2 = _tmp$6;
          if (i$2 < len && _p$2 === arr$2.buf[arr$2.start + i$2 | 0]) {
            _tmp$6 = i$2 + 1 | 0;
            continue;
          } else {
            i = i$2;
            break;
          }
        }
        _tmp = limit$3;
        _tmp$2 = _M0MPC15array12MutArrayView5sliceGUssEE(arr$2, i, len);
        _tmp$4 = _partitioned;
        _tmp$5 = balanced$2;
        continue;
      }
    }
    const left = _M0MPC15array12MutArrayView5sliceGUssEE(arr$2, 0, _pivot);
    const right = _M0MPC15array12MutArrayView5sliceGUssEE(arr$2, _pivot + 1 | 0, len);
    if ((left.end - left.start | 0) < (right.end - right.start | 0)) {
      _M0FPB18fixed__quick__sortGsE(left, pred$2, limit$3);
      _tmp = limit$3;
      _tmp$2 = right;
      _tmp$3 = arr$2.buf[arr$2.start + _pivot | 0];
      _tmp$4 = _partitioned;
      _tmp$5 = balanced$2;
      continue;
    } else {
      _M0FPB18fixed__quick__sortGsE(right, arr$2.buf[arr$2.start + _pivot | 0], limit$3);
      _tmp = limit$3;
      _tmp$2 = left;
      _tmp$4 = _partitioned;
      _tmp$5 = balanced$2;
      continue;
    }
  }
}
function _M0MPC15array12MutArrayView4sortGsE(self) {
  _M0FPB18fixed__quick__sortGsE(self, undefined, _M0FPB17fixed__get__limit(self.end - self.start | 0));
}
function _M0FPB23fixed__bubble__sort__byGUssEE(arr, cmp) {
  const _bind = arr.end - arr.start | 0;
  let _tmp = 1;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      let _tmp$2 = i;
      while (true) {
        const j = _tmp$2;
        if (j > 0 && cmp(arr.buf[arr.start + (j - 1 | 0) | 0], arr.buf[arr.start + j | 0]) > 0) {
          _M0MPC15array12MutArrayView4swapGUssEE(arr, j, j - 1 | 0);
          _tmp$2 = j - 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB23fixed__bubble__sort__byGiE(arr, cmp) {
  const _bind = arr.end - arr.start | 0;
  let _tmp = 1;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      let _tmp$2 = i;
      while (true) {
        const j = _tmp$2;
        if (j > 0 && cmp(arr.buf[arr.start + (j - 1 | 0) | 0], arr.buf[arr.start + j | 0]) > 0) {
          _M0MPC15array12MutArrayView4swapGiE(arr, j, j - 1 | 0);
          _tmp$2 = j - 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB24fixed__choose__pivot__byN7sort__2S4287GUssEE(_env, a, b) {
  const swaps = _env._2;
  const cmp = _env._1;
  const arr = _env._0;
  if (cmp(arr.buf[arr.start + a | 0], arr.buf[arr.start + b | 0]) > 0) {
    _M0MPC15array12MutArrayView4swapGUssEE(arr, a, b);
    swaps.val = swaps.val + 1 | 0;
    return;
  } else {
    return;
  }
}
function _M0FPB24fixed__choose__pivot__byN7sort__3S4288GUssEE(_env, a, b, c) {
  _M0FPB24fixed__choose__pivot__byN7sort__2S4287GUssEE(_env, a, b);
  _M0FPB24fixed__choose__pivot__byN7sort__2S4287GUssEE(_env, b, c);
  _M0FPB24fixed__choose__pivot__byN7sort__2S4287GUssEE(_env, a, b);
}
function _M0FPB24fixed__choose__pivot__byN7sort__2S4327GiE(_env, a, b) {
  const swaps = _env._2;
  const cmp = _env._1;
  const arr = _env._0;
  if (cmp(arr.buf[arr.start + a | 0], arr.buf[arr.start + b | 0]) > 0) {
    _M0MPC15array12MutArrayView4swapGiE(arr, a, b);
    swaps.val = swaps.val + 1 | 0;
    return;
  } else {
    return;
  }
}
function _M0FPB24fixed__choose__pivot__byN7sort__3S4328GiE(_env, a, b, c) {
  _M0FPB24fixed__choose__pivot__byN7sort__2S4327GiE(_env, a, b);
  _M0FPB24fixed__choose__pivot__byN7sort__2S4327GiE(_env, b, c);
  _M0FPB24fixed__choose__pivot__byN7sort__2S4327GiE(_env, a, b);
}
function _M0FPB24fixed__choose__pivot__byGUssEE(arr, cmp) {
  const len = arr.end - arr.start | 0;
  const swaps = new _M0TPB8MutLocalGiE(0);
  const b = Math.imul(len / 4 | 0, 2) | 0;
  if (len >= 8) {
    const a = Math.imul(len / 4 | 0, 1) | 0;
    const c = Math.imul(len / 4 | 0, 3) | 0;
    const _env = { _0: arr, _1: cmp, _2: swaps };
    if (len > 50) {
      _M0FPB24fixed__choose__pivot__byN7sort__3S4288GUssEE(_env, a - 1 | 0, a, a + 1 | 0);
      _M0FPB24fixed__choose__pivot__byN7sort__3S4288GUssEE(_env, b - 1 | 0, b, b + 1 | 0);
      _M0FPB24fixed__choose__pivot__byN7sort__3S4288GUssEE(_env, c - 1 | 0, c, c + 1 | 0);
    }
    _M0FPB24fixed__choose__pivot__byN7sort__3S4288GUssEE(_env, a, b, c);
  }
  if (swaps.val === 12) {
    _M0MPC15array12MutArrayView14rev__in__placeGUssEE(arr);
    return { _0: (len - b | 0) - 1 | 0, _1: true };
  } else {
    return { _0: b, _1: swaps.val === 0 };
  }
}
function _M0FPB24fixed__choose__pivot__byGiE(arr, cmp) {
  const len = arr.end - arr.start | 0;
  const swaps = new _M0TPB8MutLocalGiE(0);
  const b = Math.imul(len / 4 | 0, 2) | 0;
  if (len >= 8) {
    const a = Math.imul(len / 4 | 0, 1) | 0;
    const c = Math.imul(len / 4 | 0, 3) | 0;
    const _env = { _0: arr, _1: cmp, _2: swaps };
    if (len > 50) {
      _M0FPB24fixed__choose__pivot__byN7sort__3S4328GiE(_env, a - 1 | 0, a, a + 1 | 0);
      _M0FPB24fixed__choose__pivot__byN7sort__3S4328GiE(_env, b - 1 | 0, b, b + 1 | 0);
      _M0FPB24fixed__choose__pivot__byN7sort__3S4328GiE(_env, c - 1 | 0, c, c + 1 | 0);
    }
    _M0FPB24fixed__choose__pivot__byN7sort__3S4328GiE(_env, a, b, c);
  }
  if (swaps.val === 12) {
    _M0MPC15array12MutArrayView14rev__in__placeGiE(arr);
    return { _0: (len - b | 0) - 1 | 0, _1: true };
  } else {
    return { _0: b, _1: swaps.val === 0 };
  }
}
function _M0FPB21fixed__sift__down__byGUssEE(arr, index, cmp) {
  const len = arr.end - arr.start | 0;
  let _tmp = index;
  let _tmp$2 = (Math.imul(index, 2) | 0) + 1 | 0;
  while (true) {
    const index$2 = _tmp;
    const child = _tmp$2;
    if (child < len) {
      const child$2 = (child + 1 | 0) < len && cmp(arr.buf[arr.start + child | 0], arr.buf[arr.start + (child + 1 | 0) | 0]) < 0 ? child + 1 | 0 : child;
      if (cmp(arr.buf[arr.start + index$2 | 0], arr.buf[arr.start + child$2 | 0]) >= 0) {
        return undefined;
      }
      _M0MPC15array12MutArrayView4swapGUssEE(arr, index$2, child$2);
      _tmp = child$2;
      _tmp$2 = (Math.imul(child$2, 2) | 0) + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB21fixed__sift__down__byGiE(arr, index, cmp) {
  const len = arr.end - arr.start | 0;
  let _tmp = index;
  let _tmp$2 = (Math.imul(index, 2) | 0) + 1 | 0;
  while (true) {
    const index$2 = _tmp;
    const child = _tmp$2;
    if (child < len) {
      const child$2 = (child + 1 | 0) < len && cmp(arr.buf[arr.start + child | 0], arr.buf[arr.start + (child + 1 | 0) | 0]) < 0 ? child + 1 | 0 : child;
      if (cmp(arr.buf[arr.start + index$2 | 0], arr.buf[arr.start + child$2 | 0]) >= 0) {
        return undefined;
      }
      _M0MPC15array12MutArrayView4swapGiE(arr, index$2, child$2);
      _tmp = child$2;
      _tmp$2 = (Math.imul(child$2, 2) | 0) + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB21fixed__heap__sort__byGUssEE(arr, cmp) {
  const len = arr.end - arr.start | 0;
  const _bind = len / 2 | 0;
  let _tmp = _bind - 1 | 0;
  let _tmp$2 = _bind > 0;
  while (true) {
    const i = _tmp;
    const _more = _tmp$2;
    if (_more) {
      _M0FPB21fixed__sift__down__byGUssEE(arr, i, cmp);
      _tmp = i - 1 | 0;
      _tmp$2 = i > 0;
      continue;
    } else {
      break;
    }
  }
  let _tmp$3 = len - 1 | 0;
  let _tmp$4 = len > 1;
  while (true) {
    const i = _tmp$3;
    const _more = _tmp$4;
    if (_more) {
      _M0MPC15array12MutArrayView4swapGUssEE(arr, 0, i);
      _M0FPB21fixed__sift__down__byGUssEE(_M0MPC15array12MutArrayView5sliceGUssEE(arr, 0, i), 0, cmp);
      _tmp$3 = i - 1 | 0;
      _tmp$4 = i > 1;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB21fixed__heap__sort__byGiE(arr, cmp) {
  const len = arr.end - arr.start | 0;
  const _bind = len / 2 | 0;
  let _tmp = _bind - 1 | 0;
  let _tmp$2 = _bind > 0;
  while (true) {
    const i = _tmp;
    const _more = _tmp$2;
    if (_more) {
      _M0FPB21fixed__sift__down__byGiE(arr, i, cmp);
      _tmp = i - 1 | 0;
      _tmp$2 = i > 0;
      continue;
    } else {
      break;
    }
  }
  let _tmp$3 = len - 1 | 0;
  let _tmp$4 = len > 1;
  while (true) {
    const i = _tmp$3;
    const _more = _tmp$4;
    if (_more) {
      _M0MPC15array12MutArrayView4swapGiE(arr, 0, i);
      _M0FPB21fixed__sift__down__byGiE(_M0MPC15array12MutArrayView5sliceGiE(arr, 0, i), 0, cmp);
      _tmp$3 = i - 1 | 0;
      _tmp$4 = i > 1;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB20fixed__partition__byGUssEE(arr, cmp, pivot_index) {
  _M0MPC15array12MutArrayView4swapGUssEE(arr, pivot_index, (arr.end - arr.start | 0) - 1 | 0);
  const pivot = arr.buf[arr.start + ((arr.end - arr.start | 0) - 1 | 0) | 0];
  const _bind = (arr.end - arr.start | 0) - 1 | 0;
  let _tmp = 0;
  let _tmp$2 = 0;
  let _tmp$3 = true;
  while (true) {
    const j = _tmp;
    const i = _tmp$2;
    const partitioned = _tmp$3;
    if (j < _bind) {
      if (cmp(arr.buf[arr.start + j | 0], pivot) < 0) {
        if (i !== j) {
          _M0MPC15array12MutArrayView4swapGUssEE(arr, i, j);
          _tmp = j + 1 | 0;
          _tmp$2 = i + 1 | 0;
          _tmp$3 = false;
          continue;
        } else {
          _tmp = j + 1 | 0;
          _tmp$2 = i + 1 | 0;
          continue;
        }
      } else {
        _tmp = j + 1 | 0;
        continue;
      }
    } else {
      _M0MPC15array12MutArrayView4swapGUssEE(arr, i, (arr.end - arr.start | 0) - 1 | 0);
      return { _0: i, _1: partitioned };
    }
  }
}
function _M0FPB20fixed__partition__byGiE(arr, cmp, pivot_index) {
  _M0MPC15array12MutArrayView4swapGiE(arr, pivot_index, (arr.end - arr.start | 0) - 1 | 0);
  const pivot = arr.buf[arr.start + ((arr.end - arr.start | 0) - 1 | 0) | 0];
  const _bind = (arr.end - arr.start | 0) - 1 | 0;
  let _tmp = 0;
  let _tmp$2 = 0;
  let _tmp$3 = true;
  while (true) {
    const j = _tmp;
    const i = _tmp$2;
    const partitioned = _tmp$3;
    if (j < _bind) {
      if (cmp(arr.buf[arr.start + j | 0], pivot) < 0) {
        if (i !== j) {
          _M0MPC15array12MutArrayView4swapGiE(arr, i, j);
          _tmp = j + 1 | 0;
          _tmp$2 = i + 1 | 0;
          _tmp$3 = false;
          continue;
        } else {
          _tmp = j + 1 | 0;
          _tmp$2 = i + 1 | 0;
          continue;
        }
      } else {
        _tmp = j + 1 | 0;
        continue;
      }
    } else {
      _M0MPC15array12MutArrayView4swapGiE(arr, i, (arr.end - arr.start | 0) - 1 | 0);
      return { _0: i, _1: partitioned };
    }
  }
}
function _M0FPB28fixed__try__bubble__sort__byGUssEE(arr, cmp) {
  const _bind = arr.end - arr.start | 0;
  let _tmp = 1;
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp;
    const tries = _tmp$2;
    if (i < _bind) {
      let sorted;
      let _tmp$3 = i;
      let _tmp$4 = true;
      while (true) {
        const j = _tmp$3;
        const sorted$2 = _tmp$4;
        if (j > 0 && cmp(arr.buf[arr.start + (j - 1 | 0) | 0], arr.buf[arr.start + j | 0]) > 0) {
          _M0MPC15array12MutArrayView4swapGUssEE(arr, j, j - 1 | 0);
          _tmp$3 = j - 1 | 0;
          _tmp$4 = false;
          continue;
        } else {
          sorted = sorted$2;
          break;
        }
      }
      if (!sorted) {
        const tries$2 = tries + 1 | 0;
        if (tries$2 > 8) {
          return false;
        }
        _tmp = i + 1 | 0;
        _tmp$2 = tries$2;
        continue;
      } else {
        _tmp = i + 1 | 0;
        continue;
      }
    } else {
      return true;
    }
  }
}
function _M0FPB28fixed__try__bubble__sort__byGiE(arr, cmp) {
  const _bind = arr.end - arr.start | 0;
  let _tmp = 1;
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp;
    const tries = _tmp$2;
    if (i < _bind) {
      let sorted;
      let _tmp$3 = i;
      let _tmp$4 = true;
      while (true) {
        const j = _tmp$3;
        const sorted$2 = _tmp$4;
        if (j > 0 && cmp(arr.buf[arr.start + (j - 1 | 0) | 0], arr.buf[arr.start + j | 0]) > 0) {
          _M0MPC15array12MutArrayView4swapGiE(arr, j, j - 1 | 0);
          _tmp$3 = j - 1 | 0;
          _tmp$4 = false;
          continue;
        } else {
          sorted = sorted$2;
          break;
        }
      }
      if (!sorted) {
        const tries$2 = tries + 1 | 0;
        if (tries$2 > 8) {
          return false;
        }
        _tmp = i + 1 | 0;
        _tmp$2 = tries$2;
        continue;
      } else {
        _tmp = i + 1 | 0;
        continue;
      }
    } else {
      return true;
    }
  }
}
function _M0FPB22fixed__quick__sort__byGUssEE(arr, cmp, pred, limit) {
  let _tmp = limit;
  let _tmp$2 = arr;
  let _tmp$3 = pred;
  let _tmp$4 = true;
  let _tmp$5 = true;
  while (true) {
    const limit$2 = _tmp;
    const arr$2 = _tmp$2;
    const pred$2 = _tmp$3;
    const was_partitioned = _tmp$4;
    const balanced = _tmp$5;
    const len = arr$2.end - arr$2.start | 0;
    if (len <= 16) {
      if (len >= 2) {
        _M0FPB23fixed__bubble__sort__byGUssEE(arr$2, cmp);
      }
      return undefined;
    }
    if (limit$2 === 0) {
      _M0FPB21fixed__heap__sort__byGUssEE(arr$2, cmp);
      return undefined;
    }
    const _bind = _M0FPB24fixed__choose__pivot__byGUssEE(arr$2, cmp);
    const _pivot_index = _bind._0;
    const _likely_sorted = _bind._1;
    if (was_partitioned && (balanced && _likely_sorted)) {
      if (_M0FPB28fixed__try__bubble__sort__byGUssEE(arr$2, cmp)) {
        return undefined;
      }
    }
    const _bind$2 = _M0FPB20fixed__partition__byGUssEE(arr$2, cmp, _pivot_index);
    const _pivot = _bind$2._0;
    const _partitioned = _bind$2._1;
    const _p = len - _pivot | 0;
    const balanced$2 = (_pivot > _p ? _p : _pivot) >= (len / 8 | 0);
    const limit$3 = !balanced$2 ? limit$2 - 1 | 0 : limit$2;
    if (pred$2 === undefined) {
    } else {
      const _Some = pred$2;
      const _p$2 = _Some;
      if (cmp(_p$2, arr$2.buf[arr$2.start + _pivot | 0]) === 0) {
        let i;
        let _tmp$6 = _pivot;
        while (true) {
          const i$2 = _tmp$6;
          if (i$2 < len && cmp(_p$2, arr$2.buf[arr$2.start + i$2 | 0]) === 0) {
            _tmp$6 = i$2 + 1 | 0;
            continue;
          } else {
            i = i$2;
            break;
          }
        }
        _tmp = limit$3;
        _tmp$2 = _M0MPC15array12MutArrayView5sliceGUssEE(arr$2, i, len);
        _tmp$4 = _partitioned;
        _tmp$5 = balanced$2;
        continue;
      }
    }
    const left = _M0MPC15array12MutArrayView5sliceGUssEE(arr$2, 0, _pivot);
    const right = _M0MPC15array12MutArrayView5sliceGUssEE(arr$2, _pivot + 1 | 0, len);
    if ((left.end - left.start | 0) < (right.end - right.start | 0)) {
      _M0FPB22fixed__quick__sort__byGUssEE(left, cmp, pred$2, limit$3);
      _tmp = limit$3;
      _tmp$2 = right;
      _tmp$3 = arr$2.buf[arr$2.start + _pivot | 0];
      _tmp$4 = _partitioned;
      _tmp$5 = balanced$2;
      continue;
    } else {
      _M0FPB22fixed__quick__sort__byGUssEE(right, cmp, arr$2.buf[arr$2.start + _pivot | 0], limit$3);
      _tmp = limit$3;
      _tmp$2 = left;
      _tmp$4 = _partitioned;
      _tmp$5 = balanced$2;
      continue;
    }
  }
}
function _M0FPB22fixed__quick__sort__byGiE(arr, cmp, pred, limit) {
  let _tmp = limit;
  let _tmp$2 = arr;
  let _tmp$3 = pred;
  let _tmp$4 = true;
  let _tmp$5 = true;
  while (true) {
    const limit$2 = _tmp;
    const arr$2 = _tmp$2;
    const pred$2 = _tmp$3;
    const was_partitioned = _tmp$4;
    const balanced = _tmp$5;
    const len = arr$2.end - arr$2.start | 0;
    if (len <= 16) {
      if (len >= 2) {
        _M0FPB23fixed__bubble__sort__byGiE(arr$2, cmp);
      }
      return undefined;
    }
    if (limit$2 === 0) {
      _M0FPB21fixed__heap__sort__byGiE(arr$2, cmp);
      return undefined;
    }
    const _bind = _M0FPB24fixed__choose__pivot__byGiE(arr$2, cmp);
    const _pivot_index = _bind._0;
    const _likely_sorted = _bind._1;
    if (was_partitioned && (balanced && _likely_sorted)) {
      if (_M0FPB28fixed__try__bubble__sort__byGiE(arr$2, cmp)) {
        return undefined;
      }
    }
    const _bind$2 = _M0FPB20fixed__partition__byGiE(arr$2, cmp, _pivot_index);
    const _pivot = _bind$2._0;
    const _partitioned = _bind$2._1;
    const _p = len - _pivot | 0;
    const balanced$2 = (_pivot > _p ? _p : _pivot) >= (len / 8 | 0);
    const limit$3 = !balanced$2 ? limit$2 - 1 | 0 : limit$2;
    if (pred$2 === undefined) {
    } else {
      const _Some = pred$2;
      const _p$2 = _Some;
      if (cmp(_p$2, arr$2.buf[arr$2.start + _pivot | 0]) === 0) {
        let i;
        let _tmp$6 = _pivot;
        while (true) {
          const i$2 = _tmp$6;
          if (i$2 < len && cmp(_p$2, arr$2.buf[arr$2.start + i$2 | 0]) === 0) {
            _tmp$6 = i$2 + 1 | 0;
            continue;
          } else {
            i = i$2;
            break;
          }
        }
        _tmp = limit$3;
        _tmp$2 = _M0MPC15array12MutArrayView5sliceGiE(arr$2, i, len);
        _tmp$4 = _partitioned;
        _tmp$5 = balanced$2;
        continue;
      }
    }
    const left = _M0MPC15array12MutArrayView5sliceGiE(arr$2, 0, _pivot);
    const right = _M0MPC15array12MutArrayView5sliceGiE(arr$2, _pivot + 1 | 0, len);
    if ((left.end - left.start | 0) < (right.end - right.start | 0)) {
      _M0FPB22fixed__quick__sort__byGiE(left, cmp, pred$2, limit$3);
      _tmp = limit$3;
      _tmp$2 = right;
      _tmp$3 = arr$2.buf[arr$2.start + _pivot | 0];
      _tmp$4 = _partitioned;
      _tmp$5 = balanced$2;
      continue;
    } else {
      _M0FPB22fixed__quick__sort__byGiE(right, cmp, arr$2.buf[arr$2.start + _pivot | 0], limit$3);
      _tmp = limit$3;
      _tmp$2 = left;
      _tmp$4 = _partitioned;
      _tmp$5 = balanced$2;
      continue;
    }
  }
}
function _M0MPC15array12MutArrayView8sort__byGUssEE(self, cmp) {
  _M0FPB22fixed__quick__sort__byGUssEE(self, cmp, undefined, _M0FPB17fixed__get__limit(self.end - self.start | 0));
}
function _M0MPC15array12MutArrayView8sort__byGiE(self, cmp) {
  _M0FPB22fixed__quick__sort__byGiE(self, cmp, undefined, _M0FPB17fixed__get__limit(self.end - self.start | 0));
}
function _M0MPC15array5Array4sortGsE(self) {
  const _bind = self.len;
  _M0MPC15array12MutArrayView4sortGsE(new _M0TPB12MutArrayViewGsE(self.buf, 0, _bind));
}
function _M0MPC15array5Array8sort__byGUssEE(self, cmp) {
  const _bind = self.len;
  _M0MPC15array12MutArrayView8sort__byGUssEE(new _M0TPB12MutArrayViewGUssEE(self.buf, 0, _bind), cmp);
}
function _M0MPC15array5Array8sort__byGiE(self, cmp) {
  const _bind = self.len;
  _M0MPC15array12MutArrayView8sort__byGiE(new _M0TPB12MutArrayViewGiE(self.buf, 0, _bind), cmp);
}
function _M0MPC15array5Array12unsafe__blitGsE(dst, dst_offset, src, src_offset, len) {
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGRPC16string10StringViewEE(dst.buf, dst_offset, src.buf, src_offset, len);
}
function _M0MPC15array5Array17reserve__capacityGsE(self, capacity) {
  if (_M0MPC15array5Array8capacityGRP39stillfail5rules4lock4StmtE(self) >= capacity) {
    return undefined;
  }
  _M0MPC15array5Array14resize__bufferGRP39stillfail5rules4lock4StmtE(self, capacity);
}
function _M0MPC15array5Array3popGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(self) {
  const len = self.len;
  if (len === 0) {
    return undefined;
  } else {
    const index = len - 1 | 0;
    const v = self.buf[index];
    self.len = index;
    return v;
  }
}
function _M0MPC15array5Array4copyGsE(self) {
  const len = self.len;
  if (len === 0) {
    return new _M0TPB5ArrayGsE([], 0);
  }
  const arr = _M0MPC15array5Array20unsafe__make__uninitGUssEE(len);
  _M0MPC15array5Array12unsafe__blitGsE(arr, 0, self, 0, len);
  return arr;
}
function _M0IPC15array5ArrayPB2Eq5equalGRPC14json4JsonE(self, other) {
  const self_len = self.len;
  const other_len = other.len;
  if (self_len === other_len) {
    let _tmp = 0;
    while (true) {
      const i = _tmp;
      if (i < self_len) {
        if (_M0IPC14json4JsonPB2Eq5equal(self.buf[i], other.buf[i])) {
        } else {
          return false;
        }
        _tmp = i + 1 | 0;
        continue;
      } else {
        return true;
      }
    }
  } else {
    return false;
  }
}
function _M0MPC15array5Array8containsGsE(self, value) {
  const _bind = self.len;
  const _bind$2 = self.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const v = _bind$2[_];
      if (v === value) {
        return true;
      }
      _tmp = _ + 1 | 0;
      continue;
    } else {
      return false;
    }
  }
}
function _M0MPC15array5Array10push__iterGsE(self, iter) {
  const _bind = iter.size_hint;
  if (_bind === undefined) {
  } else {
    const _Some = _bind;
    const _n = _Some;
    _M0MPC15array5Array17reserve__capacityGsE(self, self.len + _n | 0);
  }
  while (true) {
    const _bind$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(iter);
    if (_bind$2 === undefined) {
      return;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(self, _x);
      continue;
    }
  }
}
function _M0IPC14json4JsonPB2Eq5equal(a, b) {
  switch (a.$tag) {
    case 0: {
      if (b.$tag === 0) {
        return true;
      } else {
        return false;
      }
    }
    case 1: {
      if (b.$tag === 1) {
        return true;
      } else {
        return false;
      }
    }
    case 2: {
      if (b.$tag === 2) {
        return true;
      } else {
        return false;
      }
    }
    case 3: {
      const _Number = a;
      const _a_num = _Number._0;
      if (b.$tag === 3) {
        const _Number$2 = b;
        const _b_num = _Number$2._0;
        return _a_num === _b_num;
      } else {
        return false;
      }
    }
    case 4: {
      const _String = a;
      const _a_str = _String._0;
      if (b.$tag === 4) {
        const _String$2 = b;
        const _b_str = _String$2._0;
        return _a_str === _b_str;
      } else {
        return false;
      }
    }
    case 5: {
      const _Array = a;
      const _a_arr = _Array._0;
      if (b.$tag === 5) {
        const _Array$2 = b;
        const _b_arr = _Array$2._0;
        return _M0IPC15array5ArrayPB2Eq5equalGRPC14json4JsonE(_a_arr, _b_arr);
      } else {
        return false;
      }
    }
    default: {
      const _Object = a;
      const _a_obj = _Object._0;
      if (b.$tag === 6) {
        const _Object$2 = b;
        const _b_obj = _Object$2._0;
        return _M0IPB3MapPB2Eq5equalGsRPC14json4JsonE(_a_obj, _b_obj);
      } else {
        return false;
      }
    }
  }
}
function _M0FP39stillfail5rules4fork5ahead(wa, ra, ta, ha, wb, rb, tb, hb) {
  return wa > wb ? true : wa < wb ? false : ra && !rb ? true : rb && !ra ? false : ta < tb ? true : ta > tb ? false : ha < hb;
}
function _M0FP39stillfail5rules4fork4step(wa, ra, ta, ha, wb, rb, tb, hb) {
  return !_M0FP39stillfail5rules4fork5ahead(wa, ra, ta, ha, wb, rb, tb, hb) ? undefined : wa !== wb ? _M0FP39stillfail5rules4fork4stepN6constrS5020 : !(ra === rb) ? _M0FP39stillfail5rules4fork4stepN6constrS5021 : ta !== tb ? _M0FP39stillfail5rules4fork4stepN6constrS5022 : _M0FP39stillfail5rules4fork4stepN6constrS5023;
}
function _M0FP39stillfail5rules4fork4best(ws, rs, ts, hs) {
  let b = 0;
  let _tmp = 1;
  while (true) {
    const i = _tmp;
    if (i < ws.length) {
      const _tmp$2 = i >>> 0 < ws.length ? ws[i] : $oob();
      const _tmp$3 = i >>> 0 < rs.length ? rs[i] : $oob();
      const _tmp$4 = i >>> 0 < ts.length ? ts[i] : $oob();
      const _tmp$5 = i >>> 0 < hs.length ? hs[i] : $oob();
      const _tmp$6 = b;
      const _tmp$7 = _tmp$6 >>> 0 < ws.length ? ws[_tmp$6] : $oob();
      const _tmp$8 = b;
      const _tmp$9 = _tmp$8 >>> 0 < rs.length ? rs[_tmp$8] : $oob();
      const _tmp$10 = b;
      const _tmp$11 = _tmp$10 >>> 0 < ts.length ? ts[_tmp$10] : $oob();
      const _tmp$12 = b;
      if (_M0FP39stillfail5rules4fork5ahead(_tmp$2, _tmp$3, _tmp$4, _tmp$5, _tmp$7, _tmp$9, _tmp$11, _tmp$12 >>> 0 < hs.length ? hs[_tmp$12] : $oob())) {
        b = i;
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return b;
}
function _M0FP39stillfail5rules4form11code__units(a, b) {
  const n = a.length < b.length ? a.length : b.length;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < n) {
      const x = i >>> 0 < a.length ? a.charCodeAt(i) : $oob();
      const y = i >>> 0 < b.length ? b.charCodeAt(i) : $oob();
      if (x !== y) {
        return x - y | 0;
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return a.length - b.length | 0;
}
function _M0FP39stillfail5rules4form15unicode__escape(b, c) {
  _M0IPB13StringBuilderPB6Logger13write__string(b, "\\u");
  let _bind_buf = [12, 8, 4, 0];
  let _bind_len = 4;
  const _bind = _bind_len;
  const _bind$2 = _bind_buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const shift = _bind$2[_];
      const _tmp$2 = c >> shift & 15;
      _M0IPB13StringBuilderPB6Logger11write__char(b, _tmp$2 >>> 0 < _M0FP39stillfail5rules4form11hex__digits.length ? _M0FP39stillfail5rules4form11hex__digits.charCodeAt(_tmp$2) : $oob());
      _tmp = _ + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FP39stillfail5rules4form5quote(b, s) {
  _M0IPB13StringBuilderPB6Logger11write__char(b, 34);
  const n = s.length;
  let i = 0;
  while (true) {
    if (i < n) {
      const _tmp = i;
      const c = _tmp >>> 0 < s.length ? s.charCodeAt(_tmp) : $oob();
      if (c === 34) {
        _M0IPB13StringBuilderPB6Logger13write__string(b, "\\\"");
      } else {
        if (c === 92) {
          _M0IPB13StringBuilderPB6Logger13write__string(b, "\\\\");
        } else {
          if (c === 8) {
            _M0IPB13StringBuilderPB6Logger13write__string(b, "\\b");
          } else {
            if (c === 12) {
              _M0IPB13StringBuilderPB6Logger13write__string(b, "\\f");
            } else {
              if (c === 10) {
                _M0IPB13StringBuilderPB6Logger13write__string(b, "\\n");
              } else {
                if (c === 13) {
                  _M0IPB13StringBuilderPB6Logger13write__string(b, "\\r");
                } else {
                  if (c === 9) {
                    _M0IPB13StringBuilderPB6Logger13write__string(b, "\\t");
                  } else {
                    if (c < 32) {
                      _M0FP39stillfail5rules4form15unicode__escape(b, c);
                    } else {
                      if (c >= 55296 && c <= 56319) {
                        let _tmp$2;
                        if ((i + 1 | 0) < n) {
                          let _tmp$3;
                          const _tmp$4 = i + 1 | 0;
                          if ((_tmp$4 >>> 0 < s.length ? s.charCodeAt(_tmp$4) : $oob()) >= 56320) {
                            const _tmp$5 = i + 1 | 0;
                            _tmp$3 = (_tmp$5 >>> 0 < s.length ? s.charCodeAt(_tmp$5) : $oob()) <= 57343;
                          } else {
                            _tmp$3 = false;
                          }
                          _tmp$2 = _tmp$3;
                        } else {
                          _tmp$2 = false;
                        }
                        if (_tmp$2) {
                          const _tmp$3 = 65536 + (c - 55296 << 10) | 0;
                          const _tmp$4 = i + 1 | 0;
                          _M0IPB13StringBuilderPB6Logger11write__char(b, _tmp$3 + ((_tmp$4 >>> 0 < s.length ? s.charCodeAt(_tmp$4) : $oob()) - 56320 | 0) | 0);
                          i = i + 1 | 0;
                        } else {
                          _M0FP39stillfail5rules4form15unicode__escape(b, c);
                        }
                      } else {
                        if (c >= 56320 && c <= 57343) {
                          _M0FP39stillfail5rules4form15unicode__escape(b, c);
                        } else {
                          _M0IPB13StringBuilderPB6Logger11write__char(b, c);
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      i = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  _M0IPB13StringBuilderPB6Logger11write__char(b, 34);
}
function _M0FP39stillfail5rules4form5write(b, v) {
  switch (v.$tag) {
    case 0: {
      return new _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok(_M0IPB13StringBuilderPB6Logger13write__string(b, "null"));
    }
    case 1: {
      return new _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok(_M0IPB13StringBuilderPB6Logger13write__string(b, "true"));
    }
    case 2: {
      return new _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok(_M0IPB13StringBuilderPB6Logger13write__string(b, "false"));
    }
    case 3: {
      const _Number = v;
      const _n = _Number._0;
      if (!(_n === _M0MPC16double6Double5floor(_n) && Math.abs(_n) <= 9007199254740991)) {
        return new _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE3Err(new _M0DTPC15error5Error44stillfail_2frules_2fform_2eInvalid_2eInvalid("lock entries hold integers only"));
      }
      return new _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok(_M0IPB13StringBuilderPB6Logger13write__string(b, _M0MPC15int645Int6418to__string_2einner($i64_trunc_f64(_n), 10)));
    }
    case 4: {
      const _String = v;
      const _s = _String._0;
      return new _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok(_M0FP39stillfail5rules4form5quote(b, _s));
    }
    case 5: {
      const _Array = v;
      const _xs = _Array._0;
      _M0IPB13StringBuilderPB6Logger11write__char(b, 91);
      const _bind = _xs.len;
      const _bind$2 = _xs.buf;
      let _tmp = 0;
      while (true) {
        const i = _tmp;
        if (i < _bind) {
          const x = _bind$2[i];
          if (i > 0) {
            _M0IPB13StringBuilderPB6Logger11write__char(b, 44);
          }
          const _bind$3 = _M0FP39stillfail5rules4form5write(b, x);
          if (_bind$3.$tag === 1) {
            const _ok = _bind$3;
            _ok._0;
          } else {
            return _bind$3;
          }
          _tmp = i + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      return new _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok(_M0IPB13StringBuilderPB6Logger11write__char(b, 93));
    }
    default: {
      const _Object = v;
      const _m = _Object._0;
      const keys = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(_m));
      _M0MPC15array5Array8sort__byGUssEE(keys, _M0FP39stillfail5rules4form11code__units);
      _M0IPB13StringBuilderPB6Logger11write__char(b, 123);
      const _bind$3 = keys.len;
      const _bind$4 = keys.buf;
      let _tmp$2 = 0;
      while (true) {
        const i = _tmp$2;
        if (i < _bind$3) {
          const k = _bind$4[i];
          if (i > 0) {
            _M0IPB13StringBuilderPB6Logger11write__char(b, 44);
          }
          _M0FP39stillfail5rules4form5quote(b, k);
          _M0IPB13StringBuilderPB6Logger11write__char(b, 58);
          const _p = _M0MPB3Map3getGsRPC14json4JsonE(_m, k);
          let _tmp$3;
          if (_p === undefined) {
            _tmp$3 = $panic();
          } else {
            const _p$2 = _p;
            _tmp$3 = _p$2;
          }
          const _bind$5 = _M0FP39stillfail5rules4form5write(b, _tmp$3);
          if (_bind$5.$tag === 1) {
            const _ok = _bind$5;
            _ok._0;
          } else {
            return _bind$5;
          }
          _tmp$2 = i + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      return new _M0DTPC16result6ResultGuRP39stillfail5rules4form7InvalidE2Ok(_M0IPB13StringBuilderPB6Logger11write__char(b, 125));
    }
  }
}
function _M0FP39stillfail5rules4form9canonical(v) {
  const b = _M0MPB13StringBuilder21StringBuilder_2einner(8);
  const _bind = _M0FP39stillfail5rules4form5write(b, v);
  if (_bind.$tag === 1) {
    const _ok = _bind;
    _ok._0;
  } else {
    return _bind;
  }
  return new _M0DTPC16result6ResultGsRP39stillfail5rules4form7InvalidE2Ok(b.val);
}
function _M0FP39stillfail5rules4form11entry__text(e) {
  if (e.$tag === 6) {
    const _Object = e;
    const _m = _Object._0;
    const _bind = [];
    const hashed = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 0), undefined);
    let _bind_buf = ["v", "ws", "seq", "prev", "at", "kind", "body"];
    let _bind_len = 7;
    const _bind$2 = _bind_len;
    const _bind$3 = _bind_buf;
    let _tmp = 0;
    while (true) {
      const _ = _tmp;
      if (_ < _bind$2) {
        const k = _bind$3[_];
        const _bind$4 = _M0MPB3Map3getGsRPC14json4JsonE(_m, k);
        if (_bind$4 === undefined) {
        } else {
          const _Some = _bind$4;
          const _x = _Some;
          _M0MPB3Map3setGsRPC14json4JsonE(hashed, k, _x);
        }
        _tmp = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _bind$4 = _M0FP39stillfail5rules4form9canonical(new _M0DTPC14json4Json6Object(hashed));
    let _tmp$2;
    if (_bind$4.$tag === 1) {
      const _ok = _bind$4;
      _tmp$2 = _ok._0;
    } else {
      return _bind$4;
    }
    return new _M0DTPC16result6ResultGsRP39stillfail5rules4form7InvalidE2Ok(`stillfail-lock/1\n${_tmp$2}`);
  } else {
    return new _M0DTPC16result6ResultGsRP39stillfail5rules4form7InvalidE3Err(new _M0DTPC15error5Error44stillfail_2frules_2fform_2eInvalid_2eInvalid("an entry is an object"));
  }
}
function _M0FP39stillfail5rules7history15item__epoch__ok(deleted, copy, epoch, vault) {
  return BigInt.asIntN(64, epoch) > BigInt.asIntN(64, vault) ? false : !(!deleted && (!copy && BigInt.asUintN(64, epoch) !== BigInt.asUintN(64, vault)));
}
function _M0FP39stillfail5rules7history10supersedes(seq_a, deleted_a, epoch_a, seq_b, deleted_b, epoch_b, text) {
  return BigInt.asIntN(64, seq_a) > BigInt.asIntN(64, seq_b) ? true : BigInt.asIntN(64, seq_a) < BigInt.asIntN(64, seq_b) ? false : deleted_a && !deleted_b ? true : deleted_b && !deleted_a ? false : BigInt.asIntN(64, epoch_a) > BigInt.asIntN(64, epoch_b) ? true : BigInt.asIntN(64, epoch_a) < BigInt.asIntN(64, epoch_b) ? false : text > 0;
}
function _M0FP39stillfail5rules4role4rank(r) {
  switch (r) {
    case 0: {
      return 0;
    }
    case 1: {
      return 1;
    }
    case 2: {
      return 2;
    }
    default: {
      return 3;
    }
  }
}
function _M0FP39stillfail5rules4role5lower(a, b) {
  return _M0FP39stillfail5rules4role4rank(a) <= _M0FP39stillfail5rules4role4rank(b) ? a : b;
}
function _M0FP39stillfail5rules4role3may(who, c) {
  const managing = _M0FP39stillfail5rules4role4rank(who) >= 2;
  const owning = _M0FP39stillfail5rules4role4rank(who) === 3;
  switch (c.$tag) {
    case 0: {
      const _MemberSet = c;
      const _was = _MemberSet._0;
      const _becomes = _MemberSet._1;
      return managing && (owning || !_was && !_becomes);
    }
    case 1: {
      const _MemberRemove = c;
      const _was$2 = _MemberRemove._0;
      return managing && (owning || !_was$2);
    }
    case 2: {
      const _Own = c;
      const _mine = _Own._0;
      return managing || _mine;
    }
    case 3: {
      return managing;
    }
    case 4: {
      return owning;
    }
    default: {
      return owning;
    }
  }
}
function _M0FP39stillfail5rules4role11own__device(by_them, kept, who, had_own) {
  return by_them ? true : kept ? true : had_own ? false : _M0FP39stillfail5rules4role4rank(who) >= 2;
}
function _M0FP39stillfail5rules4role9admission(found, theirs, live, member) {
  return !found ? 1 : !theirs ? 2 : !live ? 3 : !member ? 4 : 0;
}
function _M0FP39stillfail5rules4role13device__signs(app, holds, own, member) {
  return !app ? false : !holds ? false : !own ? false : member;
}
function _M0FP39stillfail5rules4lock3arr(v) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 5) {
        const _Array = _x;
        return _Array._0;
      } else {
        break _L;
      }
    }
  }
  return new _M0TPB5ArrayGRPC14json4JsonE([], 0);
}
function _M0FP39stillfail5rules4lock10body__hash(b, c) {
  let text;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules4form9canonical(b);
      if (_bind.$tag === 1) {
        const _ok = _bind;
        text = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      break _L;
    }
    const _Invalid = _try_err;
    const _why = _Invalid._0;
    return new _M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(_why));
  }
  return new _M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok(c.method_table.method_0(c.self, text));
}
function _M0FP39stillfail5rules4lock5field(v, k) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 6) {
        const _Object = _x;
        const _m = _Object._0;
        return _M0MPB3Map3getGsRPC14json4JsonE(_m, k);
      } else {
        break _L;
      }
    }
  }
  return undefined;
}
function _M0FP39stillfail5rules4lock9is__hex32(s) {
  if (s.length !== 64) {
    return false;
  }
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < 64) {
      const c = i >>> 0 < s.length ? s.charCodeAt(i) : $oob();
      if (!(c >= 48 && c <= 57 || c >= 97 && c <= 102)) {
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
function _M0FP39stillfail5rules4lock6is__id(v) {
  if (v === undefined) {
    return false;
  } else {
    const _Some = v;
    const _x = _Some;
    if (_x.$tag === 4) {
      const _String = _x;
      const _s = _String._0;
      return _M0FP39stillfail5rules4lock9is__hex32(_s);
    } else {
      return false;
    }
  }
}
function _M0FP39stillfail5rules4lock8is__role(v) {
  if (v === undefined) {
    return false;
  } else {
    const _Some = v;
    const _x = _Some;
    if (_x.$tag === 4) {
      const _String = _x;
      const _x$2 = _String._0;
      switch (_x$2) {
        case "owner": {
          return true;
        }
        case "admin": {
          return true;
        }
        case "member": {
          return true;
        }
        case "viewer": {
          return true;
        }
        default: {
          return false;
        }
      }
    } else {
      return false;
    }
  }
}
function _M0FP39stillfail5rules4lock8is__salt(v) {
  if (v === undefined) {
    return false;
  } else {
    const _Some = v;
    const _x = _Some;
    if (_x.$tag === 4) {
      const _String = _x;
      const _s = _String._0;
      if (_s.length === 32) {
        let _tmp = 0;
        while (true) {
          const i = _tmp;
          if (i < 32) {
            const c = i >>> 0 < _s.length ? _s.charCodeAt(i) : $oob();
            if (!(c >= 48 && c <= 57 || c >= 97 && c <= 102)) {
              return false;
            }
            _tmp = i + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        return true;
      } else {
        return false;
      }
    } else {
      return false;
    }
  }
}
function _M0FP39stillfail5rules4lock8text__of(v) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 4) {
        const _String = _x;
        const _s = _String._0;
        return _s;
      } else {
        break _L;
      }
    }
  }
  return undefined;
}
function _M0FP39stillfail5rules4lock9body__whyN4onlyS5219(keys, want) {
  if (keys.len === want.len) {
    const _p = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(want);
    let _tmp;
    while (true) {
      const _p$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p);
      if (_p$2 === undefined) {
        _tmp = true;
        break;
      } else {
        const _p$3 = _p$2;
        const _p$4 = _p$3;
        if (_M0MPC15array5Array8containsGsE(keys, _p$4)) {
        } else {
          _tmp = false;
          break;
        }
        continue;
      }
    }
    return _tmp;
  } else {
    return false;
  }
}
function _M0FP39stillfail5rules4lock9body__whyN5hexesS5220(x) {
  if (x === undefined) {
    return false;
  } else {
    const _Some = x;
    const _x = _Some;
    if (_x.$tag === 5) {
      const _Array = _x;
      const _xs = _Array._0;
      const _p = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_xs);
      while (true) {
        const _p$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p);
        if (_p$2 === undefined) {
          return true;
        } else {
          const _p$3 = _p$2;
          const _p$4 = _p$3;
          if (_M0FP39stillfail5rules4lock6is__id(_p$4)) {
          } else {
            return false;
          }
          continue;
        }
      }
    } else {
      return false;
    }
  }
}
function _M0FP39stillfail5rules4lock9body__whyN5namedS5221(v, k) {
  const _bind = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, k));
  return !(_bind === undefined);
}
function _M0FP39stillfail5rules4lock9body__why(b) {
  const v = b;
  let m;
  if (b.$tag === 6) {
    const _Object = b;
    m = _Object._0;
  } else {
    return _M0FP39stillfail5rules4lock9body__whyN6constrS5222;
  }
  _L: {
    const _bind = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "ws"));
    if (_bind === undefined) {
      break _L;
    } else {
      if (_M0FP39stillfail5rules4lock8is__salt(_M0FP39stillfail5rules4lock5field(v, "salt"))) {
        _L$2: {
          _L$3: {
            const _bind$2 = _M0MPB3Map3getGsRPC14json4JsonE(m, "prev");
            if (_bind$2 === undefined) {
              break _L$3;
            } else {
              const _Some = _bind$2;
              const _x = _Some;
              switch (_x.$tag) {
                case 0: {
                  break;
                }
                case 4: {
                  const _String = _x;
                  const _s = _String._0;
                  if (_M0FP39stillfail5rules4lock9is__hex32(_s)) {
                  } else {
                    break _L$3;
                  }
                  break;
                }
                default: {
                  break _L$3;
                }
              }
            }
            break _L$2;
          }
          return _M0FP39stillfail5rules4lock9body__whyN6constrS5224;
        }
        const keys = _M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter6filterGsE(_M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(m), (k) => {
          const _p = "prev";
          return !(k === _p);
        }));
        _L$3: {
          const _bind$2 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "kind"));
          if (_bind$2 === undefined) {
            break _L$3;
          } else {
            const _Some = _bind$2;
            const _x = _Some;
            switch (_x) {
              case "member": {
                return _M0FP39stillfail5rules4lock9body__whyN4onlyS5219(keys, new _M0TPB5ArrayGsE(["email", "kind", "lock", "role", "salt", "sub", "ws"], 7)) && (_M0FP39stillfail5rules4lock9body__whyN5namedS5221(v, "sub") && (_M0FP39stillfail5rules4lock9body__whyN5namedS5221(v, "email") && (_M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(v, "lock")) && _M0FP39stillfail5rules4lock8is__role(_M0FP39stillfail5rules4lock5field(v, "role"))))) ? undefined : _M0FP39stillfail5rules4lock9body__whyN6constrS5226;
              }
              case "member.remove": {
                return _M0FP39stillfail5rules4lock9body__whyN4onlyS5219(keys, new _M0TPB5ArrayGsE(["cancels", "kind", "salt", "sub", "ws"], 5)) && (_M0FP39stillfail5rules4lock9body__whyN5namedS5221(v, "sub") && _M0FP39stillfail5rules4lock9body__whyN5hexesS5220(_M0FP39stillfail5rules4lock5field(v, "cancels"))) ? undefined : _M0FP39stillfail5rules4lock9body__whyN6constrS5227;
              }
              case "station": {
                return _M0FP39stillfail5rules4lock9body__whyN4onlyS5219(keys, new _M0TPB5ArrayGsE(["key", "kind", "salt", "ws"], 4)) && _M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(v, "key")) ? undefined : _M0FP39stillfail5rules4lock9body__whyN6constrS5228;
              }
              case "station.remove": {
                return _M0FP39stillfail5rules4lock9body__whyN4onlyS5219(keys, new _M0TPB5ArrayGsE(["cancels", "key", "kind", "salt", "ws"], 5)) && (_M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(v, "key")) && _M0FP39stillfail5rules4lock9body__whyN5hexesS5220(_M0FP39stillfail5rules4lock5field(v, "cancels"))) ? undefined : _M0FP39stillfail5rules4lock9body__whyN6constrS5229;
              }
              case "open": {
                const _bind$3 = _M0FP39stillfail5rules4lock5field(v, "origins");
                let origins;
                if (_bind$3 === undefined) {
                  origins = false;
                } else {
                  const _Some$2 = _bind$3;
                  const _x$2 = _Some$2;
                  if (_x$2.$tag === 5) {
                    const _Array = _x$2;
                    const _xs = _Array._0;
                    const _p = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_xs);
                    while (true) {
                      const _p$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p);
                      if (_p$2 === undefined) {
                        origins = true;
                        break;
                      } else {
                        const _p$3 = _p$2;
                        const _p$4 = _p$3;
                        let _tmp;
                        if (_p$4.$tag === 4) {
                          _tmp = true;
                        } else {
                          _tmp = false;
                        }
                        if (_tmp) {
                        } else {
                          origins = false;
                          break;
                        }
                        continue;
                      }
                    }
                  } else {
                    origins = false;
                  }
                }
                return _M0FP39stillfail5rules4lock9body__whyN4onlyS5219(keys, new _M0TPB5ArrayGsE(["cloud_keys", "email", "kind", "origins", "rp_id", "salt", "ws"], 7)) && (_M0FP39stillfail5rules4lock9body__whyN5namedS5221(v, "email") && (origins && _M0FP39stillfail5rules4lock9body__whyN5namedS5221(v, "rp_id"))) ? undefined : _M0FP39stillfail5rules4lock9body__whyN6constrS5230;
              }
              case "off": {
                return _M0FP39stillfail5rules4lock9body__whyN4onlyS5219(keys, new _M0TPB5ArrayGsE(["kind", "salt", "ws"], 3)) ? undefined : _M0FP39stillfail5rules4lock9body__whyN6constrS5231;
              }
              default: {
                break _L$3;
              }
            }
          }
        }
        return _M0FP39stillfail5rules4lock9body__whyN6constrS5225;
      } else {
        break _L;
      }
    }
  }
  return _M0FP39stillfail5rules4lock9body__whyN6constrS5223;
}
function _M0FP39stillfail5rules4lock11entry__hash(e, c) {
  let text;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules4form11entry__text(e);
      if (_bind.$tag === 1) {
        const _ok = _bind;
        text = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      break _L;
    }
    const _Invalid = _try_err;
    const _why = _Invalid._0;
    return new _M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(_why));
  }
  return new _M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok(c.method_table.method_0(c.self, text));
}
function _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock12PersonDeviceE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsRP39stillfail5rules4lock12PersonDeviceE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock12PersonDeviceEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GssE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGsRP39stillfail5rules4lock12PersonDeviceE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock4copyGssE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGssE(new _M0TPB9ArrayViewGUssEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GssE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGssE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock6DeviceE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsRP39stillfail5rules4lock6DeviceE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6DeviceEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GssE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGsRP39stillfail5rules4lock6DeviceE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock4copyGsuE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsuE(new _M0TPB9ArrayViewGUsuEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GsuE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGsuE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGsuE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock4copyGsRPB5ArrayGsEE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsRPB5ArrayGsEE(new _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GssE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGsRPB5ArrayGsEE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock6MemberE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsRP39stillfail5rules4lock6MemberE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6MemberEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GssE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGsRP39stillfail5rules4lock6MemberE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock7StationE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsRP39stillfail5rules4lock7StationE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock7StationEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GssE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGsRP39stillfail5rules4lock7StationE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock7PasskeyE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsRP39stillfail5rules4lock7PasskeyE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock7PasskeyEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GssE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGsRP39stillfail5rules4lock7PasskeyE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock9PersonWebE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsRP39stillfail5rules4lock9PersonWebE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock9PersonWebEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GssE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      const _k = _x._0;
      const _v = _x._1;
      _M0MPB3Map3setGsRP39stillfail5rules4lock9PersonWebE(out, _k, _v);
      continue;
    }
  }
  return out;
}
function _M0FP39stillfail5rules4lock14person__device(v, c) {
  _L: {
    const _bind = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "key"));
    if (_bind === undefined) {
      break _L;
    } else {
      const _Some = _bind;
      const _key = _Some;
      const _bind$2 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "id"));
      if (_bind$2 === undefined) {
        break _L;
      } else {
        const _Some$2 = _bind$2;
        const _id = _Some$2;
        const _bind$3 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "label"));
        if (_bind$3 === undefined) {
          break _L;
        } else {
          const _Some$3 = _bind$3;
          const _label = _Some$3;
          if (_M0MPC16string6String11has__prefix(_key, _M0FP39stillfail5rules4lock14person__deviceN6recordS5366) && (c.method_table.method_2(c.self, _key) && _M0FP39stillfail5rules4lock9is__hex32(_id))) {
            return new _M0DTPC16result6ResultGRP39stillfail5rules4lock12PersonDeviceRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock12PersonDevice(_key, _id, _label));
          } else {
            return new _M0DTPC16result6ResultGRP39stillfail5rules4lock12PersonDeviceRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a person's device signs with an ed25519 key, and goes by its base key"));
          }
        }
      }
    }
  }
  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock12PersonDeviceRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a person's device is {key, id, label}"));
}
function _M0FP39stillfail5rules4lock9safe__int(v) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 3) {
        const _Number = _x;
        const _n = _Number._0;
        if (_n === _M0MPC16double6Double5floor(_n) && Math.abs(_n) <= 9007199254740991) {
          return new _M0DTPC16option6OptionGdE4Some(_n);
        } else {
          break _L;
        }
      } else {
        break _L;
      }
    }
  }
  return _M0DTPC16option6OptionGdE4None__;
}
function _M0FP39stillfail5rules4lock9safe__num(v) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 3) {
        const _Number = _x;
        const _n = _Number._0;
        return new _M0DTPC16option6OptionGdE4Some(_n);
      } else {
        break _L;
      }
    }
  }
  return _M0DTPC16option6OptionGdE4None__;
}
function _M0FP39stillfail5rules4lock8sig__key(e) {
  return _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(e, "sig"), "key")), "");
}
function _M0FP39stillfail5rules4lock7sig__of(e) {
  return _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock5field(e, "sig"), _M0DTPC14json4Json4Null__);
}
function _M0FP39stillfail5rules4lock12person__stepN4onlyS5394(keys, want) {
  if (keys.len === want.len) {
    const _p = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(want);
    let _tmp;
    while (true) {
      const _p$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p);
      if (_p$2 === undefined) {
        _tmp = true;
        break;
      } else {
        const _p$3 = _p$2;
        const _p$4 = _p$3;
        if (_M0MPC15array5Array8containsGsE(keys, _p$4)) {
        } else {
          _tmp = false;
          break;
        }
        continue;
      }
    }
    return _tmp;
  } else {
    return false;
  }
}
function _M0FP39stillfail5rules4lock12person__step(was, e, sub, c) {
  const v = e;
  if (_M0IPC16option6OptionPB2Eq5equalGdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "v")), _M0FP39stillfail5rules4lock12person__stepN6constrS5395) && _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "ws")), `person:${sub}`)) {
    const _bind = _M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(v, "at"));
    if (_bind.$tag === 1) {
      const _bind$2 = _M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(v, "seq"));
      let follows;
      if (_bind$2.$tag === 1) {
        const _Some = _bind$2;
        const _seq = _Some._0;
        if (was === undefined) {
          follows = BigInt.asUintN(64, $i64_trunc_f64(_seq)) === BigInt.asUintN(64, 0n);
        } else {
          const _Some$2 = was;
          const _w = _Some$2;
          const _p = $i64_trunc_f64(_w.seq);
          const _p$2 = $i64_trunc_f64(_seq);
          follows = BigInt.asUintN(64, _p$2) === BigInt.asUintN(64, BigInt.asUintN(64, _p + 1n));
        }
      } else {
        follows = false;
      }
      let kept_on;
      if (was === undefined) {
        const _bind$3 = _M0FP39stillfail5rules4lock5field(v, "prev");
        if (_bind$3 === undefined) {
          kept_on = false;
        } else {
          const _Some = _bind$3;
          const _x = _Some;
          if (_x.$tag === 0) {
            kept_on = true;
          } else {
            kept_on = false;
          }
        }
      } else {
        const _Some = was;
        const _w = _Some;
        kept_on = _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "prev")), _w.head);
      }
      if (follows && kept_on) {
        const key = _M0FP39stillfail5rules4lock8sig__key(e);
        const b = _M0FP39stillfail5rules4lock5field(v, "body");
        const kind = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "kind")), "");
        const _bind$3 = _M0FP39stillfail5rules4lock11entry__hash(e, c);
        let hash;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          hash = _ok._0;
        } else {
          return _bind$3;
        }
        let devices;
        if (was === undefined) {
          const _bind$4 = [];
          devices = _M0MPB3Map3MapGsRP39stillfail5rules4lock12PersonDeviceE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock12PersonDeviceEE(_bind$4, 0, 0), undefined);
        } else {
          const _Some = was;
          const _w = _Some;
          devices = _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock12PersonDeviceE(_w.devices);
        }
        let webs;
        if (was === undefined) {
          const _bind$4 = [];
          webs = _M0MPB3Map3MapGsRP39stillfail5rules4lock9PersonWebE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock9PersonWebEE(_bind$4, 0, 0), undefined);
        } else {
          const _Some = was;
          const _w = _Some;
          webs = _w.webs;
        }
        if (was === undefined) {
          if (kind === "genesis" && _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "sub")), sub)) {
            const _bind$4 = _M0FP39stillfail5rules4lock14person__device(_M0FP39stillfail5rules4lock5field(b, "device"), c);
            let first;
            if (_bind$4.$tag === 1) {
              const _ok = _bind$4;
              first = _ok._0;
            } else {
              return _bind$4;
            }
            if (first.key === key) {
              _M0MPB3Map3setGsRP39stillfail5rules4lock12PersonDeviceE(devices, first.key, first);
            } else {
              return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("the genesis is signed by the device it names"));
            }
          } else {
            return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a lock starts with its genesis"));
          }
        } else {
          _L: {
            _L$2: {
              switch (kind) {
                case "device": {
                  const _p = _M0MPB3Map8containsGsRP39stillfail5rules4lock12PersonDeviceE(devices, key);
                  if (!!_p) {
                    const _bind$4 = _M0FP39stillfail5rules4lock14person__device(b, c);
                    let d;
                    if (_bind$4.$tag === 1) {
                      const _ok = _bind$4;
                      d = _ok._0;
                    } else {
                      return _bind$4;
                    }
                    _M0MPB3Map3setGsRP39stillfail5rules4lock12PersonDeviceE(devices, d.key, d);
                  } else {
                    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("not signed by a device on the lock"));
                  }
                  break;
                }
                case "device.remove": {
                  _L$3: {
                    _L$4: {
                      const _bind$4 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
                      if (_bind$4 === undefined) {
                        break _L$4;
                      } else {
                        const _Some = _bind$4;
                        const _gone = _Some;
                        if (_M0MPB3Map8containsGsRP39stillfail5rules4lock12PersonDeviceE(devices, _gone)) {
                          const _p$2 = _M0MPB3Map8containsGsRP39stillfail5rules4lock12PersonDeviceE(devices, key);
                          const _p$3 = devices.size === 1;
                          if (!_p$2 ? false : !_p$3) {
                            _M0MPB3Map6removeGsRP39stillfail5rules4lock12PersonDeviceE(devices, _gone);
                          } else {
                            return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("not signed by a device on the lock, or its last"));
                          }
                        } else {
                          break _L$4;
                        }
                      }
                      break _L$3;
                    }
                    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no such device"));
                  }
                  break;
                }
                case "ws": {
                  break _L$2;
                }
                case "web": {
                  break _L$2;
                }
                case "web.remove": {
                  break _L$2;
                }
                default: {
                  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(`unknown entry kind ${kind}`));
                }
              }
              break _L;
            }
            if (_M0MPB3Map8containsGsRP39stillfail5rules4lock12PersonDeviceE(devices, key)) {
              let keys;
              _L$3: {
                _L$4: {
                  if (b === undefined) {
                    break _L$4;
                  } else {
                    const _Some = b;
                    const _x = _Some;
                    if (_x.$tag === 6) {
                      const _Object = _x;
                      const _m = _Object._0;
                      keys = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(_m));
                    } else {
                      break _L$4;
                    }
                  }
                  break _L$3;
                }
                keys = new _M0TPB5ArrayGsE([], 0);
              }
              if (kind === "ws") {
                if (_M0FP39stillfail5rules4lock12person__stepN4onlyS5394(keys, new _M0TPB5ArrayGsE(["t", "h"], 2)) && (_M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(b, "t")) && _M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(b, "h")))) {
                } else {
                  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a statement is {t, h}"));
                }
              } else {
                if (kind === "web") {
                  _L$4: {
                    _L$5: {
                      if (_M0FP39stillfail5rules4lock12person__stepN4onlyS5394(keys, new _M0TPB5ArrayGsE(["id", "label", "exp"], 3))) {
                        if (_M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(b, "id"))) {
                          const _bind$4 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "label"));
                          if (_bind$4 === undefined) {
                            break _L$5;
                          } else {
                            const _Some = _bind$4;
                            const _label = _Some;
                            const _bind$5 = _M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(b, "exp"));
                            if (_bind$5.$tag === 1) {
                              const _Some$2 = _bind$5;
                              const _exp = _Some$2._0;
                              const at = _M0MPC16option6Option6unwrapGdE(_M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(v, "at")));
                              if (_exp <= at + 2678400) {
                                webs = _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock9PersonWebE(webs);
                                const _p = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "id"));
                                let id;
                                if (_p === undefined) {
                                  id = $panic();
                                } else {
                                  const _p$2 = _p;
                                  id = _p$2;
                                }
                                _M0MPB3Map3setGsRP39stillfail5rules4lock9PersonWebE(webs, id, new _M0TP39stillfail5rules4lock9PersonWeb(id, _label, at, _exp));
                              } else {
                                return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a web device lasts 31 days at most"));
                              }
                            } else {
                              break _L$5;
                            }
                          }
                        } else {
                          break _L$5;
                        }
                      } else {
                        break _L$5;
                      }
                      break _L$4;
                    }
                    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a web device is {id, label, exp}"));
                  }
                } else {
                  if (_M0FP39stillfail5rules4lock12person__stepN4onlyS5394(keys, new _M0TPB5ArrayGsE(["id"], 1)) && _M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(b, "id"))) {
                    webs = _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock9PersonWebE(webs);
                    const _tmp = webs;
                    const _p = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "id"));
                    let _tmp$2;
                    if (_p === undefined) {
                      _tmp$2 = $panic();
                    } else {
                      const _p$2 = _p;
                      _tmp$2 = _p$2;
                    }
                    _M0MPB3Map6removeGsRP39stillfail5rules4lock9PersonWebE(_tmp, _tmp$2);
                  } else {
                    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a web device is taken off by its id"));
                  }
                }
              }
            } else {
              return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("not signed by a device on the lock"));
            }
          }
        }
        if (!c.method_table.method_1(c.self, _M0FP39stillfail5rules4lock7sig__of(e), hash, new _M0TPB5ArrayGsE([], 0), "", false)) {
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("signature invalid"));
        }
        if (was === undefined) {
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock6Person(sub, hash, hash, 0, devices, webs));
        } else {
          const _Some = was;
          const _w = _Some;
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock6Person(sub, _w.genesis, hash, _w.seq + 1, devices, webs));
        }
      } else {
        return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("the entry does not follow this lock's head"));
      }
    } else {
      return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("at is unix seconds"));
    }
  } else {
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("an entry of another lock"));
  }
}
function _M0FP39stillfail5rules4lock12fold__person(entries, sub, c) {
  if (entries.len === 0) {
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no lock"));
  }
  let p = undefined;
  const _bind = entries.len;
  const _bind$2 = entries.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const e = _bind$2[_];
      const _bind$3 = _M0FP39stillfail5rules4lock12person__step(p, e, sub, c);
      let _tmp$2;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _tmp$2 = _ok._0;
      } else {
        return _bind$3;
      }
      p = _tmp$2;
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p = p;
  let _tmp$2;
  if (_p === undefined) {
    _tmp$2 = $panic();
  } else {
    const _p$2 = _p;
    _tmp$2 = _p$2;
  }
  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE2Ok(_tmp$2);
}
function _M0FP39stillfail5rules4lock3mgr(role) {
  return _M0IPC16option6OptionPB2Eq5equalGsE(role, _M0FP39stillfail5rules4lock3mgrN6constrS5462) || _M0IPC16option6OptionPB2Eq5equalGsE(role, _M0FP39stillfail5rules4lock3mgrN6constrS5463);
}
function _M0FP39stillfail5rules4lock11role__named(s) {
  switch (s) {
    case "owner": {
      return 3;
    }
    case "admin": {
      return 2;
    }
    case "member": {
      return 1;
    }
    default: {
      return 0;
    }
  }
}
function _M0FP39stillfail5rules4lock8rank__of(role) {
  return _M0FP39stillfail5rules4role4rank(_M0FP39stillfail5rules4lock11role__named(role));
}
function _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(s, k) {
  return _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(s.body, k)), "");
}
function _M0FP39stillfail5rules4lock10roster__ofN3argS5472(attackers, id) {
  const _bind = _M0MPB3Map3getGsRPB5ArrayGsEE(attackers, id);
  if (_bind === undefined) {
    const xs = new _M0TPB5ArrayGsE([], 0);
    _M0MPB3Map3setGsRPB5ArrayGsEE(attackers, id, xs);
    return xs;
  } else {
    const _Some = _bind;
    return _Some;
  }
}
function _M0FP39stillfail5rules4lock10roster__ofN4lackS5473(_env, s, role) {
  const attackers = _env._1;
  const lacks = _env._0;
  const need = role === "owner" ? "owner" : "admin";
  const id = `n:${s.by}|${s.log}|${need}`;
  _M0FP39stillfail5rules4lock10roster__ofN3argS5472(attackers, id);
  _M0MPB3Map3setGsUssEE(lacks, id, { _0: `${s.by}|${s.log}`, _1: need });
  return id;
}
function _M0FP39stillfail5rules4lock10roster__ofN6countsS5474(label, r, a) {
  return _M0IPC16option6OptionPB2Eq5equalGsE(_M0MPB3Map3getGssE(label, `c:${r.hash}|${a.hash}`), _M0FP39stillfail5rules4lock10roster__ofN6constrS5483);
}
function _M0FP39stillfail5rules4lock10roster__ofN14role__of__pairS5475(pairs, s) {
  return _M0MPC16option6Option3mapGUsssEsE(_M0MPB3Map3getGsUsssEE(pairs, `${s.by}|${s.log}`), (p) => p._2);
}
function _M0FP39stillfail5rules4lock10roster__ofN15undecided__pairS5476(undecided, s) {
  return _M0MPB3Map8containsGsUssEE(undecided, `${s.by}|${s.log}`);
}
function _M0FP39stillfail5rules4lock10roster__ofN7not__inS5477(undecided, s) {
  return _M0FP39stillfail5rules4lock10roster__ofN15undecided__pairS5476(undecided, s) ? "its signer is undecided (a circle of removals)" : "its signer is not in the list";
}
function _M0FP39stillfail5rules4lock10roster__of(ws, root, chains, bodies, c) {
  const refused = new _M0TPB5ArrayGUssEE([], 0);
  const _bind = [];
  const logs = _M0MPB3Map3MapGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(new _M0TPB9ArrayViewGUsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEEE(_bind, 0, 0), undefined);
  const _bind$2 = chains.len;
  const _bind$3 = chains.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind$2) {
      const chain = _bind$3[_];
      _L: {
        let g;
        if (chain.len > 0) {
          let _try_err;
          _L$2: {
            _L$3: {
              if (0 >= chain.len) {
                $panic();
              }
              const _bind$4 = _M0FP39stillfail5rules4lock11entry__hash(chain.buf[0], c);
              if (_bind$4.$tag === 1) {
                const _ok = _bind$4;
                g = _ok._0;
              } else {
                const _err = _bind$4;
                _try_err = _err._0;
                break _L$3;
              }
              break _L$2;
            }
            g = "";
          }
        } else {
          g = "";
        }
        let sub;
        if (chain.len > 0) {
          if (0 >= chain.len) {
            $panic();
          }
          sub = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(chain.buf[0], "body"), "sub")), "");
        } else {
          sub = "";
        }
        let p;
        let why;
        _L$2: {
          _L$3: {
            let _bind$4;
            let _try_err;
            _L$4: {
              _L$5: {
                const _bind$5 = _M0FP39stillfail5rules4lock12fold__person(chain, sub, c);
                let _tmp$2;
                if (_bind$5.$tag === 1) {
                  const _ok = _bind$5;
                  _tmp$2 = _ok._0;
                } else {
                  const _err = _bind$5;
                  _try_err = _err._0;
                  break _L$5;
                }
                _bind$4 = new _M0DTPB6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE2Ok(_tmp$2);
                break _L$4;
              }
              _bind$4 = new _M0DTPB6ResultGRP39stillfail5rules4lock6PersonRP39stillfail5rules4lock9LockErrorE3Err(_try_err);
            }
            if (_bind$4.$tag === 1) {
              const _Ok = _bind$4;
              p = _Ok._0;
            } else {
              const _Err = _bind$4;
              const _x = _Err._0;
              if (_x.$tag === 2) {
                const _Refused = _x;
                const _why = _Refused._0;
                why = _why;
                break _L$3;
              } else {
                const _Refusal = _x;
                const _why = _Refusal._0;
                why = _why;
                break _L$3;
              }
            }
            break _L$2;
          }
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(refused, { _0: g, _1: why });
          break _L;
        }
        const _bind$4 = _M0MPB3Map3getGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(logs, p.genesis);
        if (_bind$4 === undefined) {
          _M0MPB3Map3setGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(logs, p.genesis, { _0: p, _1: chain });
        } else {
          const _Some = _bind$4;
          const _x = _Some;
          const _q = _x._0;
          if (_q.seq > p.seq || _q.seq === p.seq && _M0IP016_24default__implPB7Compare6op__leGsE(_q.head, p.head)) {
            _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(refused, { _0: p.genesis, _1: "another chain of the same log was taken" });
          } else {
            _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(refused, { _0: p.genesis, _1: "another chain of the same log was taken" });
            _M0MPB3Map3setGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(logs, p.genesis, { _0: p, _1: chain });
          }
        }
        break _L;
      }
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  _M0MPC15array5Array8sort__byGUssEE(refused, (a, b) => _M0IPC15tuple6Tuple2PB7Compare7compareGssE(a, b));
  const _bind$4 = [];
  const kept = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$4, 0, 0), undefined);
  const _bind$5 = bodies.len;
  const _bind$6 = bodies.buf;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$5) {
      const b = _bind$6[_];
      const _bind$7 = _M0FP39stillfail5rules4lock9body__why(b);
      if (_bind$7 === undefined) {
        let _bind$8;
        let _try_err;
        _L: {
          _L$2: {
            const _bind$9 = _M0FP39stillfail5rules4lock10body__hash(b, c);
            let _tmp$3;
            if (_bind$9.$tag === 1) {
              const _ok = _bind$9;
              _tmp$3 = _ok._0;
            } else {
              const _err = _bind$9;
              _try_err = _err._0;
              break _L$2;
            }
            _bind$8 = new _M0DTPB6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok(_tmp$3);
            break _L;
          }
          _bind$8 = new _M0DTPB6ResultGsRP39stillfail5rules4lock9LockErrorE3Err(_try_err);
        }
        if (_bind$8.$tag === 1) {
          const _Ok = _bind$8;
          const _h = _Ok._0;
          _M0MPB3Map3setGsRPC14json4JsonE(kept, _h, b);
        }
      }
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const gs = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(logs));
  _M0MPC15array5Array4sortGsE(gs);
  const in_force = new _M0TPB5ArrayGUssRPC14json4JsonsEE([], 0);
  const lacking = new _M0TPB5ArrayGsE([], 0);
  const _bind$7 = gs.len;
  const _bind$8 = gs.buf;
  let _tmp$3 = 0;
  while (true) {
    const _ = _tmp$3;
    if (_ < _bind$7) {
      const g = _bind$8[_];
      const _p = _M0MPB3Map3getGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(logs, g);
      let _bind$9;
      if (_p === undefined) {
        _bind$9 = $panic();
      } else {
        const _p$2 = _p;
        _bind$9 = _p$2;
      }
      const _chain = _bind$9._1;
      const t = c.method_table.method_0(c.self, `stillfail/ws-tag/1\n${ws}\n${g}`);
      const _bind$10 = _chain.len;
      let _tmp$4 = 1;
      while (true) {
        const i = _tmp$4;
        if (i < _bind$10) {
          _L: {
            if (i < 0 || i >= _chain.len) {
              $panic();
            }
            const e = _chain.buf[i];
            if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(e, "kind")), _M0FP39stillfail5rules4lock10roster__ofN6constrS5478) && _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(e, "body"), "t")), t)) {
              let x;
              let _try_err;
              _L$2: {
                _L$3: {
                  if (i < 0 || i >= _chain.len) {
                    $panic();
                  }
                  const _bind$11 = _M0FP39stillfail5rules4lock11entry__hash(_chain.buf[i], c);
                  if (_bind$11.$tag === 1) {
                    const _ok = _bind$11;
                    x = _ok._0;
                  } else {
                    const _err = _bind$11;
                    _try_err = _err._0;
                    break _L$3;
                  }
                  break _L$2;
                }
                break _L;
              }
              const hb = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(e, "body"), "h")), "");
              _L$3: {
                _L$4: {
                  const _bind$11 = _M0MPB3Map3getGsRPC14json4JsonE(kept, hb);
                  if (_bind$11 === undefined) {
                    break _L$4;
                  } else {
                    const _Some = _bind$11;
                    const _b = _Some;
                    if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_b, "ws")), ws)) {
                      let _tmp$5;
                      let _return_value;
                      _L$5: {
                        _L$6: {
                          let p = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_b, "prev"));
                          let n = 0;
                          while (true) {
                            const _bind$12 = p;
                            if (_bind$12 === undefined) {
                              break;
                            } else {
                              const _Some$2 = _bind$12;
                              const _x = _Some$2;
                              if (n < 10000) {
                                const _bind$13 = _M0MPB3Map3getGsRPC14json4JsonE(kept, _x);
                                if (_bind$13 === undefined) {
                                  _return_value = false;
                                  break _L$6;
                                } else {
                                  const _Some$3 = _bind$13;
                                  const _q = _Some$3;
                                  p = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_q, "prev"));
                                }
                                n = n + 1 | 0;
                                continue;
                              } else {
                                break;
                              }
                            }
                          }
                          _tmp$5 = true;
                          break _L$5;
                        }
                        _tmp$5 = _return_value;
                      }
                      if (_tmp$5) {
                        _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(in_force, { _0: x, _1: hb, _2: _b, _3: g });
                      }
                    } else {
                      break _L$4;
                    }
                  }
                  break _L$3;
                }
                _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(lacking, x);
              }
            } else {
              break _L;
            }
            break _L;
          }
          _tmp$4 = i + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp$3 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  _M0MPC15array5Array4sortGsE(lacking);
  const _p = _M0MPC15array5Array20unsafe__make__uninitGUssEE(in_force.len);
  const _p$2 = in_force.len;
  const _p$3 = in_force.buf;
  let _tmp$4 = 0;
  while (true) {
    const _p$4 = _tmp$4;
    if (_p$4 < _p$2) {
      const _p$5 = _p$3[_p$4];
      const _p$6 = { _0: _p$5._0, _1: _p$5._1 };
      _p.buf[_p$4] = _p$6;
      _tmp$4 = _p$4 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const forced = _p;
  _M0MPC15array5Array8sort__byGUssEE(forced, (a, b) => _M0IPC15tuple6Tuple2PB7Compare7compareGssE(a, b));
  let newest = undefined;
  let settings = undefined;
  const _bind$9 = in_force.len;
  const _bind$10 = in_force.buf;
  let _tmp$5 = 0;
  while (true) {
    const _ = _tmp$5;
    if (_ < _bind$9) {
      const f = _bind$10[_];
      if (f._3 === root) {
        const _bind$11 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(f._2, "kind"));
        if (_bind$11 === undefined) {
        } else {
          const _Some = _bind$11;
          const _x = _Some;
          switch (_x) {
            case "open": {
              newest = _M0FP39stillfail5rules4lock10roster__ofN6constrS5479;
              settings = f._2;
              break;
            }
            case "off": {
              newest = _M0FP39stillfail5rules4lock10roster__ofN6constrS5480;
              break;
            }
          }
        }
      }
      _tmp$5 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const empty = new _M0TP39stillfail5rules4lock6Roster(false, new _M0TPB5ArrayGRP39stillfail5rules4lock5BoundE([], 0), new _M0TPB5ArrayGsE([], 0), new _M0TPB5ArrayGUsssEE([], 0), new _M0TPB5ArrayGUssEE([], 0), new _M0TPB5ArrayGsE([], 0), new _M0TPB5ArrayGRP39stillfail5rules4lock4SaidE([], 0), new _M0TPB5ArrayGUssEE([], 0), refused, forced, lacking, newest, settings);
  const _bind$11 = _M0MPB3Map3getGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(logs, root);
  if (_bind$11 === undefined) {
    return { _0: empty, _1: logs };
  } else {
    const _Some = _bind$11;
    const _x = _Some;
    const _root_person = _x._0;
    const root_sub = _root_person.sub;
    const root_pair = `${root_sub}|${root}`;
    const _bind$12 = [];
    const by_body = _M0MPB3Map3MapGsRPB5ArrayGsEE(new _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(_bind$12, 0, 0), undefined);
    const _bind$13 = in_force.len;
    const _bind$14 = in_force.buf;
    let _tmp$6 = 0;
    while (true) {
      const _ = _tmp$6;
      if (_ < _bind$13) {
        const f = _bind$14[_];
        const _bind$15 = _M0MPB3Map3getGsRPB5ArrayGsEE(by_body, f._1);
        if (_bind$15 === undefined) {
          _M0MPB3Map3setGsRPB5ArrayGsEE(by_body, f._1, new _M0TPB5ArrayGsE([f._0], 1));
        } else {
          const _Some$2 = _bind$15;
          const _xs = _Some$2;
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_xs, f._0);
        }
        _tmp$6 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const stmts = new _M0TPB5ArrayGRP39stillfail5rules4lock4StmtE([], 0);
    const _bind$15 = in_force.len;
    const _bind$16 = in_force.buf;
    let _tmp$7 = 0;
    while (true) {
      const _ = _tmp$7;
      if (_ < _bind$15) {
        const f = _bind$16[_];
        _L: {
          const _x$2 = f._0;
          const _b = f._2;
          const _g = f._3;
          const kind = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_b, "kind")), "");
          if (kind === "member" || (kind === "member.remove" || (kind === "station" || kind === "station.remove"))) {
            let body;
            if (_b.$tag === 6) {
              const _Object = _b;
              const _m = _Object._0;
              const _bind$17 = [];
              const out = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$17, 0, 0), undefined);
              const _it = _M0MPB3Map5iter2GssE(_m);
              while (true) {
                const _bind$18 = _M0MPB5Iter24nextGssE(_it);
                if (_bind$18 === undefined) {
                  break;
                } else {
                  const _Some$2 = _bind$18;
                  const _x$3 = _Some$2;
                  const _k = _x$3._0;
                  const _v = _x$3._1;
                  _M0MPB3Map3setGsRPC14json4JsonE(out, _k, _v);
                  continue;
                }
              }
              const _bind$18 = _M0MPB3Map3getGsRPC14json4JsonE(_m, "cancels");
              if (_bind$18 === undefined) {
              } else {
                const _Some$2 = _bind$18;
                const _x$3 = _Some$2;
                if (_x$3.$tag === 5) {
                  const _Array = _x$3;
                  const _cs = _Array._0;
                  const named = new _M0TPB5ArrayGRPC14json4JsonE([], 0);
                  const _bind$19 = _cs.len;
                  const _bind$20 = _cs.buf;
                  let _tmp$8 = 0;
                  while (true) {
                    const _$2 = _tmp$8;
                    if (_$2 < _bind$19) {
                      const y = _bind$20[_$2];
                      const _bind$21 = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0MPB3Map3getGsRPB5ArrayGsEE(by_body, _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(y), "")), new _M0TPB5ArrayGsE([], 0));
                      const _bind$22 = _bind$21.len;
                      const _bind$23 = _bind$21.buf;
                      let _tmp$9 = 0;
                      while (true) {
                        const _$3 = _tmp$9;
                        if (_$3 < _bind$22) {
                          const z = _bind$23[_$3];
                          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(named, new _M0DTPC14json4Json6String(z));
                          _tmp$9 = _$3 + 1 | 0;
                          continue;
                        } else {
                          break;
                        }
                      }
                      _tmp$8 = _$2 + 1 | 0;
                      continue;
                    } else {
                      break;
                    }
                  }
                  _M0MPB3Map3setGsRPC14json4JsonE(out, "cancels", new _M0DTPC14json4Json5Array(named));
                }
              }
              body = new _M0DTPC14json4Json6Object(out);
            } else {
              body = _b;
            }
            const _tmp$8 = `ws.${kind}`;
            const _p$4 = _M0MPB3Map3getGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(logs, _g);
            let _tmp$9;
            if (_p$4 === undefined) {
              _tmp$9 = $panic();
            } else {
              const _p$5 = _p$4;
              _tmp$9 = _p$5;
            }
            _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(stmts, new _M0TP39stillfail5rules4lock4Stmt(_x$2, _tmp$8, body, _g, _tmp$9._0.sub));
          } else {
            break _L;
          }
          break _L;
        }
        _tmp$7 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _p$4 = new _M0TPB5ArrayGRP39stillfail5rules4lock4StmtE([], 0);
    const _p$5 = stmts.len;
    const _p$6 = stmts.buf;
    let admits;
    let _tmp$8 = 0;
    while (true) {
      const _p$7 = _tmp$8;
      if (_p$7 < _p$5) {
        const _p$8 = _p$6[_p$7];
        if (_p$8.kind === "ws.member") {
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_p$4, _p$8);
        }
        _tmp$8 = _p$7 + 1 | 0;
        continue;
      } else {
        admits = _p$4;
        break;
      }
    }
    const _p$7 = new _M0TPB5ArrayGRP39stillfail5rules4lock4StmtE([], 0);
    const _p$8 = stmts.len;
    const _p$9 = stmts.buf;
    let removes;
    let _tmp$9 = 0;
    while (true) {
      const _p$10 = _tmp$9;
      if (_p$10 < _p$8) {
        const _p$11 = _p$9[_p$10];
        if (_p$11.kind === "ws.member.remove") {
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_p$7, _p$11);
        }
        _tmp$9 = _p$10 + 1 | 0;
        continue;
      } else {
        removes = _p$7;
        break;
      }
    }
    const _bind$17 = [];
    const admit_at = _M0MPB3Map3MapGsRP39stillfail5rules4lock4StmtE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock4StmtEE(_bind$17, 0, 0), undefined);
    const _bind$18 = admits.len;
    const _bind$19 = admits.buf;
    let _tmp$10 = 0;
    while (true) {
      const _ = _tmp$10;
      if (_ < _bind$18) {
        const a = _bind$19[_];
        _M0MPB3Map3setGsRP39stillfail5rules4lock4StmtE(admit_at, a.hash, a);
        _tmp$10 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _bind$20 = [];
    const attackers = _M0MPB3Map3MapGsRPB5ArrayGsEE(new _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(_bind$20, 0, 0), undefined);
    const _bind$21 = [];
    const lacks = _M0MPB3Map3MapGsUssEE(new _M0TPB9ArrayViewGUsUssEEE(_bind$21, 0, 0), undefined);
    const _env = { _0: lacks, _1: attackers };
    const _bind$22 = admits.len;
    const _bind$23 = admits.buf;
    let _tmp$11 = 0;
    while (true) {
      const _ = _tmp$11;
      if (_ < _bind$22) {
        const a = _bind$23[_];
        const id = `a:${a.hash}`;
        const xs = _M0FP39stillfail5rules4lock10roster__ofN3argS5472(attackers, id);
        const _p$10 = `${a.by}|${a.log}`;
        if (!(_p$10 === root_pair)) {
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(xs, _M0FP39stillfail5rules4lock10roster__ofN4lackS5473(_env, a, _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "role")));
        }
        _tmp$11 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _bind$24 = [];
    const cancels_of = _M0MPB3Map3MapGsRPB5ArrayGsEE(new _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(_bind$24, 0, 0), undefined);
    const _bind$25 = removes.len;
    const _bind$26 = removes.buf;
    let _tmp$12 = 0;
    while (true) {
      const _ = _tmp$12;
      if (_ < _bind$25) {
        const r = _bind$26[_];
        const ids = new _M0TPB5ArrayGsE([], 0);
        const _bind$27 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(r.body, "cancels"));
        const _bind$28 = _bind$27.len;
        const _bind$29 = _bind$27.buf;
        let _tmp$13 = 0;
        while (true) {
          const _$2 = _tmp$13;
          if (_$2 < _bind$28) {
            const x = _bind$29[_$2];
            _L: {
              const _bind$30 = _M0FP39stillfail5rules4lock8text__of(x);
              if (_bind$30 === undefined) {
                break _L;
              } else {
                const _Some$2 = _bind$30;
                const _h = _Some$2;
                const _bind$31 = _M0MPB3Map3getGsRP39stillfail5rules4lock4StmtE(admit_at, _h);
                if (_bind$31 === undefined) {
                  break _L;
                } else {
                  const _Some$3 = _bind$31;
                  const _a = _Some$3;
                  if (_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(_a, "sub") === _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(r, "sub")) {
                    const id = `c:${r.hash}|${_a.hash}`;
                    const xs = _M0FP39stillfail5rules4lock10roster__ofN3argS5472(attackers, id);
                    const _p$10 = `${r.by}|${r.log}`;
                    if (!(_p$10 === root_pair)) {
                      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(xs, _M0FP39stillfail5rules4lock10roster__ofN4lackS5473(_env, r, _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(_a, "role")));
                    }
                    _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_M0FP39stillfail5rules4lock10roster__ofN3argS5472(attackers, `a:${_a.hash}`), id);
                    _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(ids, id);
                  } else {
                    break _L;
                  }
                }
              }
              break _L;
            }
            _tmp$13 = _$2 + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        _M0MPB3Map3setGsRPB5ArrayGsEE(cancels_of, r.hash, ids);
        _tmp$12 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _it = _M0MPB3Map5iter2GssE(lacks);
    while (true) {
      const _bind$27 = _M0MPB5Iter24nextGssE(_it);
      if (_bind$27 === undefined) {
        break;
      } else {
        const _Some$2 = _bind$27;
        const _x$2 = _Some$2;
        const _id = _x$2._0;
        const _x$3 = _x$2._1;
        const _pair = _x$3._0;
        const _role = _x$3._1;
        const _bind$28 = admits.len;
        const _bind$29 = admits.buf;
        let _tmp$13 = 0;
        while (true) {
          const _ = _tmp$13;
          if (_ < _bind$28) {
            const a = _bind$29[_];
            if (`${_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "sub")}|${_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "lock")}` === _pair && _M0FP39stillfail5rules4lock8rank__of(_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "role")) >= _M0FP39stillfail5rules4lock8rank__of(_role)) {
              const _p$10 = _M0MPB3Map3getGsRPB5ArrayGsEE(attackers, _id);
              let _tmp$14;
              if (_p$10 === undefined) {
                _tmp$14 = $panic();
              } else {
                const _p$11 = _p$10;
                _tmp$14 = _p$11;
              }
              _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_tmp$14, `a:${a.hash}`);
            }
            _tmp$13 = _ + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        continue;
      }
    }
    const _bind$27 = [];
    const label = _M0MPB3Map3MapGssE(new _M0TPB9ArrayViewGUssEE(_bind$27, 0, 0), undefined);
    let changed = true;
    while (true) {
      if (changed) {
        changed = false;
        const _it$2 = _M0MPB3Map5iter2GssE(attackers);
        while (true) {
          const _bind$28 = _M0MPB5Iter24nextGssE(_it$2);
          if (_bind$28 === undefined) {
            break;
          } else {
            const _Some$2 = _bind$28;
            const _x$2 = _Some$2;
            const _id = _x$2._0;
            const _by = _x$2._1;
            if (_M0MPB3Map8containsGssE(label, _id)) {
              continue;
            }
            const _p$10 = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_by);
            let _tmp$13;
            while (true) {
              const _p$11 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p$10);
              if (_p$11 === undefined) {
                _tmp$13 = false;
                break;
              } else {
                const _p$12 = _p$11;
                const _p$13 = _p$12;
                if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0MPB3Map3getGssE(label, _p$13), _M0FP39stillfail5rules4lock10roster__ofN6constrS5481)) {
                  _tmp$13 = true;
                  break;
                }
                continue;
              }
            }
            if (_tmp$13) {
              _M0MPB3Map3setGssE(label, _id, "out");
              changed = true;
            } else {
              const _p$11 = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_by);
              let _tmp$14;
              while (true) {
                const _p$12 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p$11);
                if (_p$12 === undefined) {
                  _tmp$14 = true;
                  break;
                } else {
                  const _p$13 = _p$12;
                  const _p$14 = _p$13;
                  if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0MPB3Map3getGssE(label, _p$14), _M0FP39stillfail5rules4lock10roster__ofN6constrS5482)) {
                  } else {
                    _tmp$14 = false;
                    break;
                  }
                  continue;
                }
              }
              if (_tmp$14) {
                _M0MPB3Map3setGssE(label, _id, "in");
                changed = true;
              }
            }
            continue;
          }
        }
        continue;
      } else {
        break;
      }
    }
    const _it$2 = _M0MPB3Map5iter2GssE(attackers);
    while (true) {
      const _bind$28 = _M0MPB5Iter24nextGssE(_it$2);
      if (_bind$28 === undefined) {
        break;
      } else {
        const _Some$2 = _bind$28;
        const _x$2 = _Some$2;
        const _id = _x$2._0;
        if (!_M0MPB3Map8containsGssE(label, _id)) {
          _M0MPB3Map3setGssE(label, _id, "undec");
        }
        continue;
      }
    }
    const _bind$28 = [];
    const pairs = _M0MPB3Map3MapGsUsssEE(new _M0TPB9ArrayViewGUsUsssEEE(_bind$28, 0, 0), undefined);
    const _bind$29 = [];
    const undecided = _M0MPB3Map3MapGsUssEE(new _M0TPB9ArrayViewGUsUssEEE(_bind$29, 0, 0), undefined);
    const cancelled = new _M0TPB5ArrayGsE([], 0);
    const _bind$30 = admits.len;
    const _bind$31 = admits.buf;
    let _tmp$13 = 0;
    while (true) {
      const _ = _tmp$13;
      if (_ < _bind$30) {
        const a = _bind$31[_];
        const _p$10 = _M0MPB3Map3getGssE(label, `a:${a.hash}`);
        let l;
        if (_p$10 === undefined) {
          l = $panic();
        } else {
          const _p$11 = _p$10;
          l = _p$11;
        }
        const k = `${_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "sub")}|${_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "lock")}`;
        if (l === "in") {
          _L: {
            _L$2: {
              const _bind$32 = _M0MPB3Map3getGsUsssEE(pairs, k);
              if (_bind$32 === undefined) {
                break _L$2;
              } else {
                const _Some$2 = _bind$32;
                const _x$2 = _Some$2;
                const _was = _x$2._2;
                if (_M0FP39stillfail5rules4lock8rank__of(_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "role")) <= _M0FP39stillfail5rules4lock8rank__of(_was)) {
                } else {
                  break _L$2;
                }
              }
              break _L;
            }
            _M0MPB3Map3setGsUsssEE(pairs, k, { _0: _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "sub"), _1: _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "lock"), _2: _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "role") });
          }
        } else {
          if (l === "undec" && _M0FP39stillfail5rules4lock3mgr(_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "role"))) {
            _M0MPB3Map3setGsUssEE(undecided, k, { _0: _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "sub"), _1: _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "lock") });
          }
        }
        let _tmp$14;
        if (l === "out") {
          const _p$11 = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(removes);
          let _tmp$15;
          while (true) {
            const _p$12 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p$11);
            if (_p$12 === undefined) {
              _tmp$15 = false;
              break;
            } else {
              const _p$13 = _p$12;
              const _p$14 = _p$13;
              if (_M0FP39stillfail5rules4lock10roster__ofN6countsS5474(label, _p$14, a)) {
                _tmp$15 = true;
                break;
              }
              continue;
            }
          }
          _tmp$14 = _tmp$15;
        } else {
          _tmp$14 = false;
        }
        if (_tmp$14) {
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(cancelled, a.hash);
        }
        _tmp$13 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    _M0MPB3Map3setGsUsssEE(pairs, root_pair, { _0: root_sub, _1: root, _2: "owner" });
    const _it$3 = _M0MPB3Map5iter2GssE(pairs);
    while (true) {
      const _bind$32 = _M0MPB5Iter24nextGssE(_it$3);
      if (_bind$32 === undefined) {
        break;
      } else {
        const _Some$2 = _bind$32;
        const _x$2 = _Some$2;
        const _k = _x$2._0;
        _M0MPB3Map6removeGsUssEE(undecided, _k);
        continue;
      }
    }
    const _bind$32 = [{ _0: root_sub, _1: { _0: "owner", _1: root, _2: undefined } }];
    const best = _M0MPB3Map3MapGsUssOsEE(new _M0TPB9ArrayViewGUsUssOsEEE(_bind$32, 0, 1), undefined);
    const _bind$33 = admits.len;
    const _bind$34 = admits.buf;
    let _tmp$14 = 0;
    while (true) {
      const _ = _tmp$14;
      if (_ < _bind$33) {
        const a = _bind$34[_];
        _L: {
          if (_M0IP016_24default__implPB2Eq10not__equalGOsE(_M0MPB3Map3getGssE(label, `a:${a.hash}`), _M0FP39stillfail5rules4lock10roster__ofN6constrS5484) || _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "sub") === root_sub) {
            break _L;
          }
          const role = _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "role");
          const _bind$35 = _M0MPB3Map3getGsUssOsEE(best, _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "sub"));
          let takes;
          if (_bind$35 === undefined) {
            takes = true;
          } else {
            const _Some$2 = _bind$35;
            const _x$2 = _Some$2;
            const _was = _x$2._0;
            const _admit = _x$2._2;
            if (_M0FP39stillfail5rules4lock8rank__of(role) > _M0FP39stillfail5rules4lock8rank__of(_was)) {
              takes = true;
            } else {
              let _tmp$15;
              if (role === _was) {
                let _tmp$16;
                if (_admit === undefined) {
                  _tmp$16 = false;
                } else {
                  const _Some$3 = _admit;
                  const _x$3 = _Some$3;
                  _tmp$16 = _M0IP016_24default__implPB7Compare6op__ltGsE(a.hash, _x$3);
                }
                _tmp$15 = _tmp$16;
              } else {
                _tmp$15 = false;
              }
              takes = _tmp$15;
            }
          }
          if (takes) {
            _M0MPB3Map3setGsUssOsEE(best, _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "sub"), { _0: role, _1: _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(a, "lock"), _2: a.hash });
          }
          break _L;
        }
        _tmp$14 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _bind$35 = [];
    const st_cancelled = _M0MPB3Map3MapGssE(new _M0TPB9ArrayViewGUssEE(_bind$35, 0, 0), undefined);
    const _bind$36 = stmts.len;
    const _bind$37 = stmts.buf;
    let _tmp$15 = 0;
    while (true) {
      const _ = _tmp$15;
      if (_ < _bind$36) {
        const r = _bind$37[_];
        if (r.kind === "ws.station.remove" && _M0FP39stillfail5rules4lock3mgr(_M0FP39stillfail5rules4lock10roster__ofN14role__of__pairS5475(pairs, r))) {
          const _bind$38 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(r.body, "cancels"));
          const _bind$39 = _bind$38.len;
          const _bind$40 = _bind$38.buf;
          let _tmp$16 = 0;
          while (true) {
            const _$2 = _tmp$16;
            if (_$2 < _bind$39) {
              const x = _bind$40[_$2];
              const _bind$41 = _M0FP39stillfail5rules4lock8text__of(x);
              if (_bind$41 === undefined) {
              } else {
                const _Some$2 = _bind$41;
                const _h = _Some$2;
                const k = `${_h}|${_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(r, "key")}`;
                _L: {
                  _L$2: {
                    const _bind$42 = _M0MPB3Map3getGssE(st_cancelled, k);
                    if (_bind$42 === undefined) {
                      break _L$2;
                    } else {
                      const _Some$3 = _bind$42;
                      const _was = _Some$3;
                      if (_M0IP016_24default__implPB7Compare6op__leGsE(_was, r.hash)) {
                      } else {
                        break _L$2;
                      }
                    }
                    break _L;
                  }
                  _M0MPB3Map3setGssE(st_cancelled, k, r.hash);
                }
              }
              _tmp$16 = _$2 + 1 | 0;
              continue;
            } else {
              break;
            }
          }
        }
        _tmp$15 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _bind$38 = [];
    const stations = _M0MPB3Map3MapGsuE(new _M0TPB9ArrayViewGUsuEE(_bind$38, 0, 0), undefined);
    const _bind$39 = stmts.len;
    const _bind$40 = stmts.buf;
    let _tmp$16 = 0;
    while (true) {
      const _ = _tmp$16;
      if (_ < _bind$39) {
        const s = _bind$40[_];
        if (s.kind === "ws.station" && (_M0FP39stillfail5rules4lock3mgr(_M0FP39stillfail5rules4lock10roster__ofN14role__of__pairS5475(pairs, s)) && !_M0MPB3Map8containsGssE(st_cancelled, `${s.hash}|${_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(s, "key")}`))) {
          _M0MPB3Map3setGsuE(stations, _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(s, "key"), undefined);
        }
        _tmp$16 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const said = new _M0TPB5ArrayGRP39stillfail5rules4lock4SaidE([], 0);
    const _bind$41 = stmts.len;
    const _bind$42 = stmts.buf;
    let _tmp$17 = 0;
    while (true) {
      const _ = _tmp$17;
      if (_ < _bind$41) {
        const s = _bind$42[_];
        let l = "in";
        let why = undefined;
        let decided = undefined;
        const _bind$43 = s.kind;
        switch (_bind$43) {
          case "ws.member": {
            const _p$10 = _M0MPB3Map3getGssE(label, `a:${s.hash}`);
            let _tmp$18;
            if (_p$10 === undefined) {
              _tmp$18 = $panic();
            } else {
              const _p$11 = _p$10;
              _tmp$18 = _p$11;
            }
            l = _tmp$18;
            if (l === "undec") {
              why = _M0FP39stillfail5rules4lock10roster__ofN15undecided__pairS5476(undecided, s) ? "its signer is undecided (a circle of removals)" : "the admit is undecided (named by an undecided removal)";
            } else {
              if (l === "out") {
                const _p$11 = new _M0TPB5ArrayGRP39stillfail5rules4lock4StmtE([], 0);
                const _p$12 = removes.len;
                const _p$13 = removes.buf;
                let _p$14;
                let _tmp$19 = 0;
                while (true) {
                  const _p$15 = _tmp$19;
                  if (_p$15 < _p$12) {
                    const _p$16 = _p$13[_p$15];
                    if (_M0FP39stillfail5rules4lock10roster__ofN6countsS5474(label, _p$16, s)) {
                      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_p$11, _p$16);
                    }
                    _tmp$19 = _p$15 + 1 | 0;
                    continue;
                  } else {
                    _p$14 = _p$11;
                    break;
                  }
                }
                const _p$15 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$14.len);
                const _p$16 = _p$14.len;
                const _p$17 = _p$14.buf;
                let _tmp$20 = 0;
                while (true) {
                  const _p$18 = _tmp$20;
                  if (_p$18 < _p$16) {
                    const _p$19 = _p$17[_p$18];
                    const _p$20 = _p$19.hash;
                    _p$15.buf[_p$18] = _p$20;
                    _tmp$20 = _p$18 + 1 | 0;
                    continue;
                  } else {
                    break;
                  }
                }
                const by = _p$15;
                _M0MPC15array5Array4sortGsE(by);
                if (by.len > 0) {
                  why = _M0FP39stillfail5rules4lock10roster__ofN6constrS5485;
                  if (0 >= by.len) {
                    $panic();
                  }
                  decided = by.buf[0];
                } else {
                  if (!_M0FP39stillfail5rules4lock3mgr(_M0FP39stillfail5rules4lock10roster__ofN14role__of__pairS5475(pairs, s))) {
                    why = _M0FP39stillfail5rules4lock10roster__ofN7not__inS5477(undecided, s);
                  } else {
                    why = _M0FP39stillfail5rules4lock10roster__ofN6constrS5486;
                  }
                }
              } else {
                const _bind$44 = _M0MPB3Map3getGsUssOsEE(best, _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(s, "sub"));
                if (_bind$44 === undefined) {
                } else {
                  const _Some$2 = _bind$44;
                  const _x$2 = _Some$2;
                  const _role = _x$2._0;
                  const _lock = _x$2._1;
                  const _admit = _x$2._2;
                  _L: {
                    _L$2: {
                      const _p$11 = _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(s, "role");
                      if (!(_role === _p$11)) {
                        break _L$2;
                      } else {
                        const _p$12 = _M0FP39stillfail5rules4lock10roster__ofN3txtS5470(s, "lock");
                        if (!(_lock === _p$12)) {
                          break _L$2;
                        }
                      }
                      break _L;
                    }
                    why = _M0FP39stillfail5rules4lock10roster__ofN6constrS5487;
                    decided = _admit;
                  }
                }
              }
            }
            break;
          }
          case "ws.member.remove": {
            const _p$11 = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0MPB3Map3getGsRPB5ArrayGsEE(cancels_of, s.hash), new _M0TPB5ArrayGsE([], 0));
            const _p$12 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$11.len);
            const _p$13 = _p$11.len;
            const _p$14 = _p$11.buf;
            let _tmp$19 = 0;
            while (true) {
              const _p$15 = _tmp$19;
              if (_p$15 < _p$13) {
                const _p$16 = _p$14[_p$15];
                const _p$17 = _M0MPB3Map3getGssE(label, _p$16);
                let _p$18;
                if (_p$17 === undefined) {
                  _p$18 = $panic();
                } else {
                  const _p$19 = _p$17;
                  _p$18 = _p$19;
                }
                _p$12.buf[_p$15] = _p$18;
                _tmp$19 = _p$15 + 1 | 0;
                continue;
              } else {
                break;
              }
            }
            const cs = _p$12;
            if (_M0MPC15array5Array8containsGsE(cs, "in")) {
            } else {
              if (_M0MPC15array5Array8containsGsE(cs, "undec")) {
                l = "undec";
                why = _M0FP39stillfail5rules4lock10roster__ofN6constrS5488;
              } else {
                if (cs.len > 0) {
                  l = "out";
                  why = _M0FP39stillfail5rules4lock3mgr(_M0FP39stillfail5rules4lock10roster__ofN14role__of__pairS5475(pairs, s)) ? "it may cancel none of what it names" : _M0FP39stillfail5rules4lock10roster__ofN7not__inS5477(undecided, s);
                }
              }
            }
            break;
          }
          case "ws.station": {
            if (!_M0FP39stillfail5rules4lock3mgr(_M0FP39stillfail5rules4lock10roster__ofN14role__of__pairS5475(pairs, s))) {
              l = "out";
              why = _M0FP39stillfail5rules4lock10roster__ofN7not__inS5477(undecided, s);
            } else {
              const _bind$44 = _M0MPB3Map3getGssE(st_cancelled, `${s.hash}|${_M0FP39stillfail5rules4lock10roster__ofN3txtS5470(s, "key")}`);
              if (_bind$44 === undefined) {
              } else {
                const _Some$2 = _bind$44;
                const _r = _Some$2;
                l = "out";
                why = _M0FP39stillfail5rules4lock10roster__ofN6constrS5489;
                decided = _r;
              }
            }
            break;
          }
          default: {
            if (!_M0FP39stillfail5rules4lock3mgr(_M0FP39stillfail5rules4lock10roster__ofN14role__of__pairS5475(pairs, s))) {
              l = "out";
              why = _M0FP39stillfail5rules4lock10roster__ofN7not__inS5477(undecided, s);
            }
          }
        }
        _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(said, new _M0TP39stillfail5rules4lock4Said(s.hash, s.kind, s.log, s.by, l, why, decided));
        _tmp$17 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    _M0MPC15array5Array8sort__byGUssEE(said, (a, b) => _M0IPC16string6StringPB7Compare7compare(a.hash, b.hash));
    const members = new _M0TPB5ArrayGRP39stillfail5rules4lock5BoundE([], 0);
    const subs = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(best));
    _M0MPC15array5Array4sortGsE(subs);
    const _bind$43 = subs.len;
    const _bind$44 = subs.buf;
    let _tmp$18 = 0;
    while (true) {
      const _ = _tmp$18;
      if (_ < _bind$43) {
        const sub = _bind$44[_];
        const _p$10 = _M0MPB3Map3getGsUssOsEE(best, sub);
        let _bind$45;
        if (_p$10 === undefined) {
          _bind$45 = $panic();
        } else {
          const _p$11 = _p$10;
          _bind$45 = _p$11;
        }
        const _role = _bind$45._0;
        const _lock = _bind$45._1;
        const _admit = _bind$45._2;
        let keys;
        _L: {
          _L$2: {
            const _bind$46 = _M0MPB3Map3getGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(logs, _lock);
            if (_bind$46 === undefined) {
              break _L$2;
            } else {
              const _Some$2 = _bind$46;
              const _x$2 = _Some$2;
              const _p$11 = _x$2._0;
              if (_p$11.sub === sub) {
                const ks = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(_p$11.devices));
                _M0MPC15array5Array4sortGsE(ks);
                keys = ks;
              } else {
                break _L$2;
              }
            }
            break _L;
          }
          keys = undefined;
        }
        _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(members, new _M0TP39stillfail5rules4lock5Bound(sub, _role, _lock, _admit, keys));
        _tmp$18 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const sts = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4keysGsuE(stations));
    _M0MPC15array5Array4sortGsE(sts);
    const ps = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map6valuesGsRP39stillfail5rules4lock12PersonDeviceE(pairs));
    _M0MPC15array5Array8sort__byGUssEE(ps, (a, b) => _M0IPC15tuple6Tuple3PB7Compare7compareGsssE(a, b));
    const us = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map6valuesGsRP39stillfail5rules4lock12PersonDeviceE(undecided));
    _M0MPC15array5Array8sort__byGUssEE(us, (a, b) => _M0IPC15tuple6Tuple2PB7Compare7compareGssE(a, b));
    _M0MPC15array5Array4sortGsE(cancelled);
    const ls = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(label));
    _M0MPC15array5Array8sort__byGUssEE(ls, (a, b) => _M0IPC16string6StringPB7Compare7compare(a._0, b._0));
    return { _0: new _M0TP39stillfail5rules4lock6Roster(true, members, sts, ps, us, cancelled, said, ls, refused, forced, lacking, newest, settings), _1: logs };
  }
}
function _M0FP39stillfail5rules4lock6state4(ws, root, chains, bodies, now, c) {
  const _bind = _M0FP39stillfail5rules4lock10roster__of(ws, root, chains, bodies, c);
  const _r = _bind._0;
  const _logs = _bind._1;
  const _tmp = new _M0TPB5ArrayGsE([], 0);
  const _bind$2 = [];
  const _tmp$2 = _M0MPB3Map3MapGsRP39stillfail5rules4lock6MemberE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6MemberEE(_bind$2, 0, 0), undefined);
  const _bind$3 = [];
  const _tmp$3 = _M0MPB3Map3MapGsRP39stillfail5rules4lock6DeviceE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6DeviceEE(_bind$3, 0, 0), undefined);
  const _bind$4 = [];
  const _tmp$4 = _M0MPB3Map3MapGsRPB5ArrayGsEE(new _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(_bind$4, 0, 0), undefined);
  const _bind$5 = [];
  const _tmp$5 = _M0MPB3Map3MapGsRP39stillfail5rules4lock7PasskeyE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock7PasskeyEE(_bind$5, 0, 0), undefined);
  const _bind$6 = [];
  const _tmp$6 = _M0MPB3Map3MapGsuE(new _M0TPB9ArrayViewGUsuEE(_bind$6, 0, 0), undefined);
  const _bind$7 = [];
  const _tmp$7 = _M0MPB3Map3MapGsRP39stillfail5rules4lock7StationE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock7StationEE(_bind$7, 0, 0), undefined);
  const _bind$8 = [];
  const _tmp$8 = _M0MPB3Map3MapGsuE(new _M0TPB9ArrayViewGUsuEE(_bind$8, 0, 0), undefined);
  const _bind$9 = [];
  const s = new _M0TP39stillfail5rules4lock9LockState(ws, 0, root, root, _tmp, "", _M0DTPC14json4Json4Null__, _tmp$2, _tmp$3, _tmp$4, _tmp$5, _tmp$6, _tmp$7, _tmp$8, _M0MPB3Map3MapGssE(new _M0TPB9ArrayViewGUssEE(_bind$9, 0, 0), undefined), false, undefined);
  _L: {
    if (_r.rooted) {
      const _bind$10 = _M0MPB3Map3getGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(_logs, root);
      if (_bind$10 === undefined) {
        break _L;
      } else {
        const _Some = _bind$10;
        const _x = _Some;
        const _rp = _x._0;
        const set = _r.settings;
        const _tmp$9 = _rp.seq;
        const _tmp$10 = _rp.head;
        const _p = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(set, "origins"));
        const _p$2 = new _M0TPB5ArrayGsE([], 0);
        const _p$3 = _p.len;
        const _p$4 = _p.buf;
        let _tmp$11;
        let _tmp$12 = 0;
        while (true) {
          const _p$5 = _tmp$12;
          if (_p$5 < _p$3) {
            const _p$6 = _p$4[_p$5];
            const _p$7 = _M0FP39stillfail5rules4lock8text__of(_p$6);
            if (_p$7 === undefined) {
            } else {
              const _p$8 = _p$7;
              const _p$9 = _p$8;
              _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_p$2, _p$9);
            }
            _tmp$12 = _p$5 + 1 | 0;
            continue;
          } else {
            _tmp$11 = _p$2;
            break;
          }
        }
        const s$2 = new _M0TP39stillfail5rules4lock9LockState(s.ws, _tmp$9, _tmp$10, s.genesis, _tmp$11, _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(set, "rp_id")), ""), _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock5field(set, "cloud_keys"), _M0DTPC14json4Json4Null__), s.members, s.devices, s.sign_keys, s.passkeys, s.signed, s.stations, s.gateways, s.persons, _M0IPC16option6OptionPB2Eq5equalGsE(_r.newest, _M0FP39stillfail5rules4lock6state4N6constrS5874), s.moved);
        const _bind$11 = [];
        const forced = _M0MPB3Map3MapGssE(new _M0TPB9ArrayViewGUssEE(_bind$11, 0, 0), undefined);
        const _bind$12 = _r.in_force;
        const _bind$13 = _bind$12.len;
        const _bind$14 = _bind$12.buf;
        let _tmp$13 = 0;
        while (true) {
          const _ = _tmp$13;
          if (_ < _bind$13) {
            const f = _bind$14[_];
            _M0MPB3Map3setGssE(forced, f._0, f._1);
            _tmp$13 = _ + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        const _bind$15 = [];
        const bodies_by = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$15, 0, 0), undefined);
        const _bind$16 = bodies.len;
        const _bind$17 = bodies.buf;
        let _tmp$14 = 0;
        while (true) {
          const _ = _tmp$14;
          if (_ < _bind$16) {
            const b = _bind$17[_];
            let _bind$18;
            let _try_err;
            _L$2: {
              _L$3: {
                const _bind$19 = _M0FP39stillfail5rules4lock10body__hash(b, c);
                let _tmp$15;
                if (_bind$19.$tag === 1) {
                  const _ok = _bind$19;
                  _tmp$15 = _ok._0;
                } else {
                  const _err = _bind$19;
                  _try_err = _err._0;
                  break _L$3;
                }
                _bind$18 = new _M0DTPB6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok(_tmp$15);
                break _L$2;
              }
              _bind$18 = new _M0DTPB6ResultGsRP39stillfail5rules4lock9LockErrorE3Err(_try_err);
            }
            if (_bind$18.$tag === 1) {
              const _Ok = _bind$18;
              const _h = _Ok._0;
              _M0MPB3Map3setGsRPC14json4JsonE(bodies_by, _h, b);
            }
            _tmp$14 = _ + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        const _bind$18 = _r.members;
        const _bind$19 = _bind$18.len;
        const _bind$20 = _bind$18.buf;
        let _tmp$15 = 0;
        while (true) {
          const _ = _tmp$15;
          if (_ < _bind$19) {
            const m = _bind$20[_];
            _L$2: {
              const _bind$21 = m.admit;
              let email;
              if (_bind$21 === undefined) {
                email = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(set, "email"));
              } else {
                const _Some$2 = _bind$21;
                const _x$2 = _Some$2;
                const _bind$22 = _M0MPB3Map3getGssE(forced, _x$2);
                if (_bind$22 === undefined) {
                  email = undefined;
                } else {
                  const _Some$3 = _bind$22;
                  const _h = _Some$3;
                  email = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0MPB3Map3getGsRPC14json4JsonE(bodies_by, _h), "email"));
                }
              }
              _M0MPB3Map3setGsRP39stillfail5rules4lock6MemberE(s$2.members, m.sub, new _M0TP39stillfail5rules4lock6Member(m.sub, _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(email, ""), m.role));
              _M0MPB3Map3setGssE(s$2.persons, m.sub, m.lock);
              const _bind$22 = _M0MPB3Map3getGsURP39stillfail5rules4lock6PersonRPB5ArrayGRPC14json4JsonEEE(_logs, m.lock);
              if (_bind$22 === undefined) {
                break _L$2;
              } else {
                const _Some$2 = _bind$22;
                const _x$2 = _Some$2;
                const _p$5 = _x$2._0;
                if (_p$5.sub === m.sub) {
                  const _p$6 = _p$5.devices;
                  if (_p$6.size > 0) {
                    const _it = _M0MPB3Map5iter2GssE(_p$5.devices);
                    while (true) {
                      const _bind$23 = _M0MPB5Iter24nextGssE(_it);
                      if (_bind$23 === undefined) {
                        break;
                      } else {
                        const _Some$3 = _bind$23;
                        const _x$3 = _Some$3;
                        const _d = _x$3._1;
                        _M0MPB3Map3setGsRP39stillfail5rules4lock6DeviceE(s$2.devices, _d.id, new _M0TP39stillfail5rules4lock6Device(_d.id, m.sub, "app", _d.label, _d.key, undefined, _M0DTPC16option6OptionGdE4None__, undefined, true));
                        _M0MPB3Map3setGsRPB5ArrayGsEE(s$2.sign_keys, _d.id, new _M0TPB5ArrayGsE([_d.key], 1));
                        continue;
                      }
                    }
                    _M0MPB3Map3setGsuE(s$2.signed, m.sub, undefined);
                    const _it$2 = _M0MPB3Map5iter2GssE(_p$5.webs);
                    while (true) {
                      const _bind$23 = _M0MPB5Iter24nextGssE(_it$2);
                      if (_bind$23 === undefined) {
                        break;
                      } else {
                        const _Some$3 = _bind$23;
                        const _x$3 = _Some$3;
                        const _w = _x$3._1;
                        if (_w.at <= now + 600 && now < _w.exp) {
                          _M0MPB3Map3setGsRP39stillfail5rules4lock6DeviceE(s$2.devices, _w.id, new _M0TP39stillfail5rules4lock6Device(_w.id, m.sub, "web", _w.label, undefined, undefined, new _M0DTPC16option6OptionGdE4Some(_w.exp), undefined, true));
                        }
                        continue;
                      }
                    }
                  } else {
                    break _L$2;
                  }
                } else {
                  break _L$2;
                }
              }
              break _L$2;
            }
            _tmp$15 = _ + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        const _bind$21 = _r.stations;
        const _bind$22 = _bind$21.len;
        const _bind$23 = _bind$21.buf;
        let _tmp$16 = 0;
        while (true) {
          const _ = _tmp$16;
          if (_ < _bind$22) {
            const k = _bind$23[_];
            _M0MPB3Map3setGsRP39stillfail5rules4lock7StationE(s$2.stations, k, new _M0TP39stillfail5rules4lock7Station(k, ""));
            _tmp$16 = _ + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        const _bind$24 = _r.newest;
        let on;
        if (_bind$24 === undefined) {
          on = "not on";
        } else {
          const _Some$2 = _bind$24;
          const _x$2 = _Some$2;
          switch (_x$2) {
            case "off": {
              on = "off";
              break;
            }
            case "open": {
              on = "on";
              break;
            }
            default: {
              on = "not on";
            }
          }
        }
        return new _M0TP39stillfail5rules4lock6State4(on, s$2);
      }
    } else {
      break _L;
    }
  }
  return new _M0TP39stillfail5rules4lock6State4("no root", s);
}
function _M0FP39stillfail5rules4lock13admit__person(s, sub, endpoint, base, proof, entries, c) {
  const _bind = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(s.members, sub);
  if (_bind === undefined) {
    return new _M0DTPC16result6ResultGURP39stillfail5rules4lock12PersonDevicesRP39stillfail5rules4lock6PersonERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("not a member in the workspace's lock"));
  } else {
    const _Some = _bind;
    const _member = _Some;
    let person;
    let _try_err;
    _L: {
      _L$2: {
        const _bind$2 = _M0FP39stillfail5rules4lock12fold__person(entries, sub, c);
        if (_bind$2.$tag === 1) {
          const _ok = _bind$2;
          person = _ok._0;
        } else {
          const _err = _bind$2;
          _try_err = _err._0;
          break _L$2;
        }
        break _L;
      }
      let why;
      _L$3: {
        if (_try_err.$tag === 2) {
          const _Refused = _try_err;
          const _why = _Refused._0;
          why = _why;
          break _L$3;
        } else {
          const _Refusal = _try_err;
          const _why = _Refusal._0;
          why = _why;
          break _L$3;
        }
      }
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock12PersonDevicesRP39stillfail5rules4lock6PersonERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal(why));
    }
    const pinned = _M0IPC16option6OptionPB2Eq5equalGsE(_M0MPB3Map3getGssE(s.persons, sub), person.genesis);
    const base$2 = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(base, "");
    let proved;
    const _p = "";
    if (!(base$2 === _p)) {
      let _tmp;
      if (proof === undefined) {
        _tmp = false;
      } else {
        const _Some$2 = proof;
        const _p$2 = _Some$2;
        const _p$3 = "";
        if (!(_p$2 === _p$3)) {
          _tmp = _M0FP39stillfail5rules4lock9is__hex32(base$2) && c.method_table.method_3(c.self, s.ws, base$2, endpoint, _p$2);
        } else {
          _tmp = false;
        }
      }
      proved = _tmp;
    } else {
      proved = false;
    }
    let on = undefined;
    const _it = _M0MPB3Map5iter2GssE(person.devices);
    while (true) {
      const _bind$2 = _M0MPB5Iter24nextGssE(_it);
      if (_bind$2 === undefined) {
        break;
      } else {
        const _Some$2 = _bind$2;
        const _x = _Some$2;
        const _d = _x._1;
        if (_d.id === base$2) {
          on = _d;
        }
        continue;
      }
    }
    const _bind$2 = on;
    const _p$2 = !(_bind$2 === undefined);
    if (!pinned ? false : !proved ? false : _p$2) {
      const _p$3 = on;
      let _tmp;
      if (_p$3 === undefined) {
        _tmp = $panic();
      } else {
        const _p$4 = _p$3;
        _tmp = _p$4;
      }
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock12PersonDevicesRP39stillfail5rules4lock6PersonERP39stillfail5rules4lock9LockErrorE2Ok({ _0: _tmp, _1: _member.role, _2: person });
    } else {
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock12PersonDevicesRP39stillfail5rules4lock6PersonERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("this device is not on the lock its person bound in this workspace"));
    }
  }
}
function _M0FP39stillfail5rules4lock6refuse(why) {
  return new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(why));
}
function _M0FP39stillfail5rules4lock11str_2einner(v, max) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 4) {
        const _String = _x;
        const _s = _String._0;
        if (_s.length <= max) {
          return _s;
        } else {
          break _L;
        }
      } else {
        break _L;
      }
    }
  }
  return undefined;
}
function _M0FP39stillfail5rules4lock8role__of(v) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 4) {
        const _String = _x;
        const _x$2 = _String._0;
        switch (_x$2) {
          case "owner": {
            return _M0FP39stillfail5rules4lock8role__ofN6constrS6006;
          }
          case "admin": {
            return _M0FP39stillfail5rules4lock8role__ofN6constrS6007;
          }
          case "member": {
            return _M0FP39stillfail5rules4lock8role__ofN6constrS6008;
          }
          case "viewer": {
            return _M0FP39stillfail5rules4lock8role__ofN6constrS6009;
          }
          default: {
            break _L;
          }
        }
      } else {
        break _L;
      }
    }
  }
  return undefined;
}
function _M0FP39stillfail5rules4lock6member(v) {
  const sub = _M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "sub"), 200);
  const email = _M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "email"), 320);
  const role = _M0FP39stillfail5rules4lock5field(v, "role");
  _L: {
    const _bind = _M0FP39stillfail5rules4lock8role__of(role);
    if (sub === undefined) {
      break _L;
    } else {
      const _Some = sub;
      const _sub = _Some;
      if (email === undefined) {
        break _L;
      } else {
        const _Some$2 = email;
        const _email = _Some$2;
        if (_bind === undefined) {
          break _L;
        } else {
          const _p = "";
          if (!(_sub === _p)) {
            const _p$2 = _M0FP39stillfail5rules4lock8text__of(role);
            let _tmp;
            if (_p$2 === undefined) {
              _tmp = $panic();
            } else {
              const _p$3 = _p$2;
              _tmp = _p$3;
            }
            return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6MemberRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock6Member(_sub, _email, _tmp));
          } else {
            break _L;
          }
        }
      }
    }
  }
  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6MemberRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a member is {sub, email, role}"));
}
function _M0FP39stillfail5rules4lock6device(v, at, c) {
  const id = _M0FP39stillfail5rules4lock5field(v, "id");
  const sub = _M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "sub"), 200);
  const label = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "label"), 200), "");
  const kind = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "kind"));
  _L: {
    if (_M0FP39stillfail5rules4lock6is__id(id)) {
      if (sub === undefined) {
        break _L;
      } else {
        const _Some = sub;
        const _sub = _Some;
        const _p = "";
        if (!(_sub === _p)) {
          if (kind === undefined) {
            break _L;
          } else {
            const _Some$2 = kind;
            const _kind = _Some$2;
            _L$2: {
              if (_kind === "app") {
                break _L$2;
              } else {
                if (_kind === "web") {
                  break _L$2;
                } else {
                  break _L;
                }
              }
            }
            const _bind = _M0FP39stillfail5rules4lock5field(v, "sign_key");
            let sign_key;
            if (_bind === undefined) {
              sign_key = undefined;
            } else {
              const _Some$3 = _bind;
              const _k = _Some$3;
              _L$3: {
                _L$4: {
                  if (_k.$tag === 4) {
                    const _String = _k;
                    const _k$2 = _String._0;
                    if (_kind === "app" && (_k$2.length <= 200 && c.method_table.method_2(c.self, _k$2))) {
                      sign_key = _k$2;
                    } else {
                      break _L$4;
                    }
                  } else {
                    break _L$4;
                  }
                  break _L$3;
                }
                return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("only an app's device signs, with an ed25519 or p256 key"));
              }
            }
            let endpoints;
            _L$3: {
              _L$4: {
                const _bind$2 = _M0FP39stillfail5rules4lock5field(v, "endpoints");
                if (_bind$2 === undefined) {
                  endpoints = undefined;
                } else {
                  const _Some$3 = _bind$2;
                  const _x = _Some$3;
                  if (_x.$tag === 5) {
                    const _Array = _x;
                    const _xs = _Array._0;
                    let _tmp;
                    if (_xs.len <= 64) {
                      const _p$2 = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_xs);
                      let _tmp$2;
                      while (true) {
                        const _p$3 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p$2);
                        if (_p$3 === undefined) {
                          _tmp$2 = true;
                          break;
                        } else {
                          const _p$4 = _p$3;
                          const _p$5 = _p$4;
                          if (_M0FP39stillfail5rules4lock6is__id(_p$5)) {
                          } else {
                            _tmp$2 = false;
                            break;
                          }
                          continue;
                        }
                      }
                      _tmp = _tmp$2;
                    } else {
                      _tmp = false;
                    }
                    if (_tmp) {
                      const _p$2 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_xs.len);
                      const _p$3 = _xs.len;
                      const _p$4 = _xs.buf;
                      let _tmp$2 = 0;
                      while (true) {
                        const _p$5 = _tmp$2;
                        if (_p$5 < _p$3) {
                          const _p$6 = _p$4[_p$5];
                          const _p$7 = _M0FP39stillfail5rules4lock8text__of(_p$6);
                          let _p$8;
                          if (_p$7 === undefined) {
                            _p$8 = $panic();
                          } else {
                            const _p$9 = _p$7;
                            _p$8 = _p$9;
                          }
                          _p$2.buf[_p$5] = _p$8;
                          _tmp$2 = _p$5 + 1 | 0;
                          continue;
                        } else {
                          break;
                        }
                      }
                      endpoints = _p$2;
                    } else {
                      break _L$4;
                    }
                  } else {
                    break _L$4;
                  }
                }
                break _L$3;
              }
              return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("endpoints are iroh ids"));
            }
            const _bind$2 = _M0FP39stillfail5rules4lock5field(v, "exp");
            let exp;
            if (_bind$2 === undefined) {
              exp = _M0DTPC16option6OptionGdE4None__;
            } else {
              const _Some$3 = _bind$2;
              const _bind$3 = _M0FP39stillfail5rules4lock9safe__int(_Some$3);
              if (_bind$3.$tag === 1) {
                const _Some$4 = _bind$3;
                const _n = _Some$4._0;
                exp = new _M0DTPC16option6OptionGdE4Some(_n);
              } else {
                return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("exp is unix seconds"));
              }
            }
            if (_kind === "web") {
              if (at > 0) {
                _L$4: {
                  _L$5: {
                    if (exp.$tag === 0) {
                      break _L$5;
                    } else {
                      if (_M0MPC16option6Option6unwrapGdE(exp) > at + 2678400) {
                        break _L$5;
                      }
                    }
                    break _L$4;
                  }
                  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a web page's device lasts 30 days at most"));
                }
              }
            }
            const _p$2 = _M0FP39stillfail5rules4lock8text__of(id);
            let _tmp;
            if (_p$2 === undefined) {
              _tmp = $panic();
            } else {
              const _p$3 = _p$2;
              _tmp = _p$3;
            }
            return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock6Device(_tmp, _sub, _kind, label, sign_key, endpoints, exp, undefined, false));
          }
        } else {
          break _L;
        }
      }
    } else {
      break _L;
    }
  }
  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a device is {id, sub, kind, label}"));
}
function _M0FP39stillfail5rules4lock7passkey(v, c) {
  const id = _M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "id"), 1400);
  const sub = _M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "sub"), 200);
  const key = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "key"));
  const label = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "label"), 200), "");
  _L: {
    if (id === undefined) {
      break _L;
    } else {
      const _Some = id;
      const _id = _Some;
      if (sub === undefined) {
        break _L;
      } else {
        const _Some$2 = sub;
        const _sub = _Some$2;
        if (key === undefined) {
          break _L;
        } else {
          const _Some$3 = key;
          const _key = _Some$3;
          let _tmp;
          const _p = "";
          if (!(_id === _p)) {
            let _tmp$2;
            const _p$2 = "";
            if (!(_sub === _p$2)) {
              _tmp$2 = _M0MPC16string6String11has__prefix(_key, _M0FP39stillfail5rules4lock7passkeyN6recordS6062) && (_key.length <= 200 && c.method_table.method_2(c.self, _key));
            } else {
              _tmp$2 = false;
            }
            _tmp = _tmp$2;
          } else {
            _tmp = false;
          }
          if (_tmp) {
            return new _M0DTPC16result6ResultGRP39stillfail5rules4lock7PasskeyRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock7Passkey(_id, _sub, _key, label, false));
          } else {
            break _L;
          }
        }
      }
    }
  }
  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock7PasskeyRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a passkey is {id, sub, key: p256:…}"));
}
function _M0FP39stillfail5rules4lock7station(v) {
  if (_M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(v, "key"))) {
    const _p = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "key"));
    let _tmp;
    if (_p === undefined) {
      _tmp = $panic();
    } else {
      const _p$2 = _p;
      _tmp = _p$2;
    }
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock7StationRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock7Station(_tmp, _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "name"), 200), "")));
  } else {
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock7StationRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a station is {key, name}"));
  }
}
function _M0FP39stillfail5rules4lock10with__role(s, sub, passkey, own) {
  const _bind = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(s.members, sub);
  if (_bind === undefined) {
    return undefined;
  } else {
    const _Some = _bind;
    const _m = _Some;
    return new _M0TP39stillfail5rules4lock6Signer(sub, _m.role, passkey, own);
  }
}
function _M0FP39stillfail5rules4lock6signer(s, key, now) {
  let found = undefined;
  const _it = _M0MPB3Map5iter2GssE(s.passkeys);
  while (true) {
    const _bind = _M0MPB5Iter24nextGssE(_it);
    if (_bind === undefined) {
      break;
    } else {
      const _Some = _bind;
      const _x = _Some;
      const _p = _x._1;
      if (_p.key === key) {
        const _bind$2 = _M0FP39stillfail5rules4lock10with__role(s, _p.sub, true, _p.own);
        if (_bind$2 === undefined) {
        } else {
          const _Some$2 = _bind$2;
          const _w = _Some$2;
          found = _w;
        }
      }
      continue;
    }
  }
  const _it$2 = _M0MPB3Map5iter2GssE(s.devices);
  while (true) {
    const _bind = _M0MPB5Iter24nextGssE(_it$2);
    if (_bind === undefined) {
      break;
    } else {
      const _Some = _bind;
      const _x = _Some;
      const _d = _x._1;
      const _bind$2 = _d.exp;
      let live;
      if (_bind$2.$tag === 0) {
        live = true;
      } else {
        if (now.$tag === 0) {
          live = true;
        } else {
          const _Some$2 = _bind$2;
          const _exp = _Some$2._0;
          const _Some$3 = now;
          const _now = _Some$3._0;
          live = _exp > _now;
        }
      }
      const _bind$3 = found;
      let own_found;
      if (_bind$3 === undefined) {
        own_found = false;
      } else {
        const _Some$2 = _bind$3;
        const _f = _Some$2;
        own_found = _f.own;
      }
      const _p = _M0IPC16option6OptionPB2Eq5equalGsE(_d.sign_key, key) && _d.kind === "app";
      const _p$2 = _M0MPB3Map8containsGsRP39stillfail5rules4lock6MemberE(s.members, _d.sub);
      if (own_found ? false : !_p ? false : !live ? false : _p$2) {
        found = _M0FP39stillfail5rules4lock10with__role(s, _d.sub, false, _d.own);
      }
      continue;
    }
  }
  return found;
}
function _M0FP39stillfail5rules4lock7own__of(s, sub, by, was, key) {
  let kept;
  if (was === undefined) {
    kept = false;
  } else {
    const _Some = was;
    const _w = _Some;
    kept = _w.own && _M0IPC16option6OptionPB2Eq5equalGsE(_w.sign_key, key);
  }
  return _M0FP39stillfail5rules4role11own__device(by.sub === sub, kept, _M0FP39stillfail5rules4lock11role__named(by.role), _M0MPB3Map8containsGsuE(s.signed, sub));
}
function _M0FP39stillfail5rules4lock6owners(s) {
  let n = 0;
  const _it = _M0MPB3Map5iter2GssE(s.members);
  while (true) {
    const _bind = _M0MPB5Iter24nextGssE(_it);
    if (_bind === undefined) {
      break;
    } else {
      const _Some = _bind;
      const _x = _Some;
      const _m = _x._1;
      if (_m.role === "owner") {
        n = n + 1 | 0;
      }
      continue;
    }
  }
  return n;
}
function _M0FP39stillfail5rules4lock3add(s, d) {
  if (!_M0MPB3Map8containsGsRP39stillfail5rules4lock6MemberE(s.members, d.sub)) {
    const _bind = _M0FP39stillfail5rules4lock6refuse("a device is a member's");
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _ok._0;
    } else {
      return _bind;
    }
  }
  _M0MPB3Map3setGsRP39stillfail5rules4lock6DeviceE(s.devices, d.id, d);
  const _bind = d.sign_key;
  if (_bind === undefined) {
    return new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE2Ok(undefined);
  } else {
    const _Some = _bind;
    const _k = _Some;
    const had = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0MPB3Map3getGsRPB5ArrayGsEE(s.sign_keys, d.id), new _M0TPB5ArrayGsE([], 0));
    if (!_M0MPC15array5Array8containsGsE(had, _k)) {
      const _tmp = s.sign_keys;
      const _tmp$2 = d.id;
      const _self = new _M0TPB5ArrayGsE([], 0);
      _M0MPC15array5Array10push__iterGsE(_self, _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(had));
      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_self, _k);
      _M0MPB3Map3setGsRPB5ArrayGsEE(_tmp, _tmp$2, _self);
    }
    return d.own ? new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE2Ok(_M0MPB3Map3setGsuE(s.signed, d.sub, undefined)) : new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE2Ok(undefined);
  }
}
function _M0FP39stillfail5rules4lock12add__passkey(s, p) {
  _M0MPB3Map3setGsRP39stillfail5rules4lock7PasskeyE(s.passkeys, p.key, p);
  if (p.own) {
    _M0MPB3Map3setGsuE(s.signed, p.sub, undefined);
    return;
  } else {
    return;
  }
}
function _M0FP39stillfail5rules4lock7genesis(e, c) {
  const v = e;
  const ws = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "ws"));
  _L: {
    if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "kind")), _M0FP39stillfail5rules4lock7genesisN6constrS6138)) {
      if (_M0IPC16option6OptionPB2Eq5equalGdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "seq")), _M0FP39stillfail5rules4lock7genesisN6constrS6139)) {
        _L$2: {
          const _bind = _M0FP39stillfail5rules4lock5field(v, "prev");
          if (_bind === undefined) {
            break _L$2;
          } else {
            const _Some = _bind;
            const _x = _Some;
            if (_x.$tag === 0) {
              if (_M0IPC16option6OptionPB2Eq5equalGdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "v")), _M0FP39stillfail5rules4lock7genesisN6constrS6140)) {
                if (ws === undefined) {
                  break _L;
                } else {
                  const _Some$2 = ws;
                  const _ws = _Some$2;
                  const _p = "";
                  if (!(_ws === _p)) {
                    let b;
                    _L$3: {
                      _L$4: {
                        const _bind$2 = _M0FP39stillfail5rules4lock5field(v, "body");
                        if (_bind$2 === undefined) {
                          break _L$4;
                        } else {
                          const _Some$3 = _bind$2;
                          const _x$2 = _Some$3;
                          if (_x$2.$tag === 0) {
                            break _L$4;
                          } else {
                            b = _bind$2;
                          }
                        }
                        break _L$3;
                      }
                      const _bind$2 = [];
                      const _p$2 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$2, 0, 0), undefined);
                      b = new _M0DTPC14json4Json6Object(_p$2);
                    }
                    const _p$2 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "origins"));
                    const _p$3 = new _M0TPB5ArrayGsE([], 0);
                    const _p$4 = _p$2.len;
                    const _p$5 = _p$2.buf;
                    let origins;
                    let _tmp = 0;
                    while (true) {
                      const _p$6 = _tmp;
                      if (_p$6 < _p$4) {
                        const _p$7 = _p$5[_p$6];
                        const _p$8 = _M0FP39stillfail5rules4lock8text__of(_p$7);
                        if (_p$8 === undefined) {
                        } else {
                          const _p$9 = _p$8;
                          const _p$10 = _p$9;
                          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_p$3, _p$10);
                        }
                        _tmp = _p$6 + 1 | 0;
                        continue;
                      } else {
                        origins = _p$3;
                        break;
                      }
                    }
                    const _bind$2 = _M0FP39stillfail5rules4lock11entry__hash(e, c);
                    let hash;
                    if (_bind$2.$tag === 1) {
                      const _ok = _bind$2;
                      hash = _ok._0;
                    } else {
                      return _bind$2;
                    }
                    const _bind$3 = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(b, "rp_id"), 200), "");
                    const _bind$4 = _M0FP39stillfail5rules4lock5field(b, "cloud_keys");
                    let _bind$5;
                    if (_bind$4 === undefined) {
                      _bind$5 = _M0DTPC14json4Json4Null__;
                    } else {
                      const _Some$3 = _bind$4;
                      _bind$5 = _Some$3;
                    }
                    const _bind$6 = [];
                    const _bind$7 = _M0MPB3Map3MapGsRP39stillfail5rules4lock6MemberE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6MemberEE(_bind$6, 0, 0), undefined);
                    const _bind$8 = [];
                    const _bind$9 = _M0MPB3Map3MapGsRP39stillfail5rules4lock6DeviceE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6DeviceEE(_bind$8, 0, 0), undefined);
                    const _bind$10 = [];
                    const _bind$11 = _M0MPB3Map3MapGsRPB5ArrayGsEE(new _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(_bind$10, 0, 0), undefined);
                    const _bind$12 = [];
                    const _bind$13 = _M0MPB3Map3MapGsRP39stillfail5rules4lock7PasskeyE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock7PasskeyEE(_bind$12, 0, 0), undefined);
                    const _bind$14 = [];
                    const _bind$15 = _M0MPB3Map3MapGsuE(new _M0TPB9ArrayViewGUsuEE(_bind$14, 0, 0), undefined);
                    const _bind$16 = [];
                    const _bind$17 = _M0MPB3Map3MapGsRP39stillfail5rules4lock7StationE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock7StationEE(_bind$16, 0, 0), undefined);
                    const _bind$18 = [];
                    const _bind$19 = _M0MPB3Map3MapGsuE(new _M0TPB9ArrayViewGUsuEE(_bind$18, 0, 0), undefined);
                    const _bind$20 = [];
                    const _bind$21 = _M0MPB3Map3MapGssE(new _M0TPB9ArrayViewGUssEE(_bind$20, 0, 0), undefined);
                    const _bind$22 = undefined;
                    const s = new _M0TP39stillfail5rules4lock9LockState(_ws, 0, hash, hash, origins, _bind$3, _bind$5, _bind$7, _bind$9, _bind$11, _bind$13, _bind$15, _bind$17, _bind$19, _bind$21, false, _bind$22);
                    const _bind$23 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "members"));
                    const _bind$24 = _bind$23.len;
                    const _bind$25 = _bind$23.buf;
                    let _tmp$2 = 0;
                    while (true) {
                      const _ = _tmp$2;
                      if (_ < _bind$24) {
                        const m = _bind$25[_];
                        const _bind$26 = _M0FP39stillfail5rules4lock6member(m);
                        let m$2;
                        if (_bind$26.$tag === 1) {
                          const _ok = _bind$26;
                          m$2 = _ok._0;
                        } else {
                          return _bind$26;
                        }
                        _M0MPB3Map3setGsRP39stillfail5rules4lock6MemberE(_bind$7, m$2.sub, m$2);
                        _tmp$2 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const owner = _M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(b, "owner"), 200);
                    const _bind$26 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "devices"));
                    const _bind$27 = _bind$26.len;
                    const _bind$28 = _bind$26.buf;
                    let _tmp$3 = 0;
                    while (true) {
                      const _ = _tmp$3;
                      if (_ < _bind$27) {
                        const d = _bind$28[_];
                        const _bind$29 = _M0FP39stillfail5rules4lock6device(d, 0, c);
                        let _tmp$4;
                        if (_bind$29.$tag === 1) {
                          const _ok = _bind$29;
                          _tmp$4 = _ok._0;
                        } else {
                          return _bind$29;
                        }
                        const _tmp$5 = _tmp$4;
                        const _bind$30 = _M0FP39stillfail5rules4lock3add(s, new _M0TP39stillfail5rules4lock6Device(_tmp$5.id, _tmp$5.sub, _tmp$5.kind, _tmp$5.label, _tmp$5.sign_key, _tmp$5.endpoints, _tmp$5.exp, owner, true));
                        if (_bind$30.$tag === 1) {
                          const _ok = _bind$30;
                          _ok._0;
                        } else {
                          return _bind$30;
                        }
                        _tmp$3 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const _bind$29 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "passkeys"));
                    const _bind$30 = _bind$29.len;
                    const _bind$31 = _bind$29.buf;
                    let _tmp$4 = 0;
                    while (true) {
                      const _ = _tmp$4;
                      if (_ < _bind$30) {
                        const p = _bind$31[_];
                        const _bind$32 = _M0FP39stillfail5rules4lock7passkey(p, c);
                        let _bind$33;
                        if (_bind$32.$tag === 1) {
                          const _ok = _bind$32;
                          _bind$33 = _ok._0;
                        } else {
                          return _bind$32;
                        }
                        _M0FP39stillfail5rules4lock12add__passkey(s, new _M0TP39stillfail5rules4lock7Passkey(_bind$33.id, _bind$33.sub, _bind$33.key, _bind$33.label, true));
                        _tmp$4 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const _bind$32 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "stations"));
                    const _bind$33 = _bind$32.len;
                    const _bind$34 = _bind$32.buf;
                    let _tmp$5 = 0;
                    while (true) {
                      const _ = _tmp$5;
                      if (_ < _bind$33) {
                        const st = _bind$34[_];
                        const _bind$35 = _M0FP39stillfail5rules4lock7station(st);
                        let st$2;
                        if (_bind$35.$tag === 1) {
                          const _ok = _bind$35;
                          st$2 = _ok._0;
                        } else {
                          return _bind$35;
                        }
                        _M0MPB3Map3setGsRP39stillfail5rules4lock7StationE(_bind$17, st$2.key, st$2);
                        _tmp$5 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const _bind$35 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "gateways"));
                    const _bind$36 = _bind$35.len;
                    const _bind$37 = _bind$35.buf;
                    let _tmp$6 = 0;
                    while (true) {
                      const _ = _tmp$6;
                      if (_ < _bind$36) {
                        const g = _bind$37[_];
                        if (_M0FP39stillfail5rules4lock6is__id(g)) {
                          const _p$6 = _M0FP39stillfail5rules4lock8text__of(g);
                          let _tmp$7;
                          if (_p$6 === undefined) {
                            _tmp$7 = $panic();
                          } else {
                            const _p$7 = _p$6;
                            _tmp$7 = _p$7;
                          }
                          _M0MPB3Map3setGsuE(_bind$19, _tmp$7, undefined);
                        }
                        _tmp$6 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const _bind$38 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "owner"));
                    let owns;
                    if (_bind$38 === undefined) {
                      owns = false;
                    } else {
                      const _Some$3 = _bind$38;
                      const _o = _Some$3;
                      const _bind$39 = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(_bind$7, _o);
                      if (_bind$39 === undefined) {
                        owns = false;
                      } else {
                        const _Some$4 = _bind$39;
                        const _m = _Some$4;
                        owns = _m.role === "owner";
                      }
                    }
                    if (!owns) {
                      const _bind$39 = _M0FP39stillfail5rules4lock6refuse("the genesis names its owner among its members");
                      if (_bind$39.$tag === 1) {
                        const _ok = _bind$39;
                        _ok._0;
                      } else {
                        return _bind$39;
                      }
                    }
                    const by = _M0FP39stillfail5rules4lock6signer(s, _M0FP39stillfail5rules4lock8sig__key(e), new _M0DTPC16option6OptionGdE4Some(_M0MPC16option6Option10unwrap__orGdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "at")), 1 / 0)));
                    const _bind$39 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "owner"));
                    let signed_by_owner;
                    if (by === undefined) {
                      signed_by_owner = false;
                    } else {
                      const _Some$3 = by;
                      const _by = _Some$3;
                      if (_bind$39 === undefined) {
                        signed_by_owner = false;
                      } else {
                        const _Some$4 = _bind$39;
                        const _o = _Some$4;
                        signed_by_owner = _by.sub === _o && c.method_table.method_1(c.self, _M0FP39stillfail5rules4lock7sig__of(e), hash, origins, _bind$3, _by.passkey);
                      }
                    }
                    if (!signed_by_owner) {
                      const _bind$40 = _M0FP39stillfail5rules4lock6refuse("the genesis is not signed by its owner");
                      if (_bind$40.$tag === 1) {
                        const _ok = _bind$40;
                        _ok._0;
                      } else {
                        return _bind$40;
                      }
                    }
                    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(s);
                  } else {
                    break _L;
                  }
                }
              } else {
                break _L;
              }
            } else {
              break _L$2;
            }
          }
        }
        break _L;
      } else {
        break _L;
      }
    } else {
      break _L;
    }
  }
  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a lock starts with its genesis"));
}
function _M0FP39stillfail5rules4lock10kind__text(v) {
  if (v === undefined) {
    return "undefined";
  } else {
    const _Some = v;
    const _x = _Some;
    switch (_x.$tag) {
      case 4: {
        const _String = _x;
        return _String._0;
      }
      case 0: {
        return "null";
      }
      case 1: {
        return "true";
      }
      case 2: {
        return "false";
      }
      case 3: {
        let _try_err;
        _L: {
          const _p = _Some;
          let _tmp;
          if (_p === undefined) {
            _tmp = $panic();
          } else {
            const _p$2 = _p;
            _tmp = _p$2;
          }
          const _bind = _M0FP39stillfail5rules4form9canonical(_tmp);
          if (_bind.$tag === 1) {
            const _ok = _bind;
            return _ok._0;
          } else {
            const _err = _bind;
            _try_err = _err._0;
            break _L;
          }
        }
        return "NaN";
      }
      case 5: {
        return "";
      }
      default: {
        return "[object Object]";
      }
    }
  }
}
function _M0FP39stillfail5rules4lock5applyN4needS6237(ok, why) {
  if (!ok) {
    return new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(why));
  } else {
    return new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE2Ok(undefined);
  }
}
function _M0FP39stillfail5rules4lock5apply(prev, e, now, c) {
  const v = e;
  const _bind = prev.moved;
  if (_bind === undefined) {
  } else {
    const _bind$2 = _M0FP39stillfail5rules4lock6refuse("the lock moved to a person's own log: nothing follows it here");
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _ok._0;
    } else {
      return _bind$2;
    }
  }
  if (prev.disabled) {
    const _bind$2 = _M0FP39stillfail5rules4lock6refuse("the lock is turned off");
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _ok._0;
    } else {
      return _bind$2;
    }
  }
  if (_M0IP016_24default__implPB2Eq10not__equalGOdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "v")), _M0FP39stillfail5rules4lock5applyN6constrS6238) || _M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "ws")), prev.ws)) {
    const _bind$2 = _M0FP39stillfail5rules4lock6refuse("an entry of another lock");
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _ok._0;
    } else {
      return _bind$2;
    }
  }
  const _bind$2 = _M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(v, "seq"));
  let follows;
  if (_bind$2.$tag === 1) {
    const _Some = _bind$2;
    const _seq = _Some._0;
    const _p = $i64_trunc_f64(prev.seq);
    const _p$2 = $i64_trunc_f64(_seq);
    follows = BigInt.asUintN(64, _p$2) === BigInt.asUintN(64, BigInt.asUintN(64, _p + 1n));
  } else {
    follows = false;
  }
  if (!follows || _M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "prev")), prev.head)) {
    const _bind$3 = _M0FP39stillfail5rules4lock6refuse("the entry does not follow this lock's head");
    if (_bind$3.$tag === 1) {
      const _ok = _bind$3;
      _ok._0;
    } else {
      return _bind$3;
    }
  }
  const _bind$3 = _M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(v, "at"));
  if (_bind$3.$tag === 0) {
    const _bind$4 = _M0FP39stillfail5rules4lock6refuse("at is unix seconds");
    if (_bind$4.$tag === 1) {
      const _ok = _bind$4;
      _ok._0;
    } else {
      return _bind$4;
    }
  }
  const at = _M0MPC16option6Option6unwrapGdE(_M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(v, "at")));
  const _bind$4 = _M0FP39stillfail5rules4lock11entry__hash(e, c);
  let hash;
  if (_bind$4.$tag === 1) {
    const _ok = _bind$4;
    hash = _ok._0;
  } else {
    return _bind$4;
  }
  const _bind$5 = _M0FP39stillfail5rules4lock6signer(prev, _M0FP39stillfail5rules4lock8sig__key(e), now);
  if (_bind$5 === undefined) {
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("not signed by a device or passkey in the lock"));
  } else {
    const _Some = _bind$5;
    const _by = _Some;
    if (!c.method_table.method_1(c.self, _M0FP39stillfail5rules4lock7sig__of(e), hash, prev.origins, prev.rp_id, _by.passkey)) {
      const _bind$6 = _M0FP39stillfail5rules4lock6refuse("signature invalid");
      if (_bind$6.$tag === 1) {
        const _ok = _bind$6;
        _ok._0;
      } else {
        return _bind$6;
      }
    }
    const s = new _M0TP39stillfail5rules4lock9LockState(prev.ws, prev.seq + 1, hash, prev.genesis, prev.origins, prev.rp_id, prev.cloud_keys, _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock6MemberE(prev.members), _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock6DeviceE(prev.devices), _M0FP39stillfail5rules4lock4copyGsRPB5ArrayGsEE(prev.sign_keys), _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock7PasskeyE(prev.passkeys), _M0FP39stillfail5rules4lock4copyGsuE(prev.signed), _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock7StationE(prev.stations), _M0FP39stillfail5rules4lock4copyGsuE(prev.gateways), _M0FP39stillfail5rules4lock4copyGssE(prev.persons), prev.disabled, prev.moved);
    let b;
    _L: {
      _L$2: {
        const _bind$6 = _M0FP39stillfail5rules4lock5field(v, "body");
        if (_bind$6 === undefined) {
          break _L$2;
        } else {
          const _Some$2 = _bind$6;
          const _x = _Some$2;
          if (_x.$tag === 0) {
            break _L$2;
          } else {
            b = _bind$6;
          }
        }
        break _L;
      }
      const _bind$6 = [];
      const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$6, 0, 0), undefined);
      b = new _M0DTPC14json4Json6Object(_p);
    }
    const who = _M0FP39stillfail5rules4lock11role__named(_by.role);
    const kind = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "kind")), "");
    let out = s;
    switch (kind) {
      case "member": {
        const _bind$6 = _M0FP39stillfail5rules4lock6member(b);
        let m;
        if (_bind$6.$tag === 1) {
          const _ok = _bind$6;
          m = _ok._0;
        } else {
          return _bind$6;
        }
        const _bind$7 = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(s.members, m.sub);
        let was_owner;
        if (_bind$7 === undefined) {
          was_owner = false;
        } else {
          const _Some$2 = _bind$7;
          const _w = _Some$2;
          was_owner = _w.role === "owner";
        }
        const _bind$8 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change9MemberSet(was_owner, m.role === "owner")), _M0FP39stillfail5rules4role4rank(who) >= 2 ? "only owners make or change owners" : "only owners and admins change members");
        if (_bind$8.$tag === 1) {
          const _ok = _bind$8;
          _ok._0;
        } else {
          return _bind$8;
        }
        const _p = _M0FP39stillfail5rules4lock6owners(s);
        const _p$2 = m.role === "owner";
        const kept = _p$2 ? true : was_owner ? _p >= 2 : _p >= 1;
        _M0MPB3Map3setGsRP39stillfail5rules4lock6MemberE(s.members, m.sub, m);
        const _bind$9 = _M0FP39stillfail5rules4lock5applyN4needS6237(kept, "a lock keeps an owner");
        if (_bind$9.$tag === 1) {
          const _ok = _bind$9;
          _ok._0;
        } else {
          return _bind$9;
        }
        break;
      }
      case "member.remove": {
        const sub = _M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(b, "sub"), 200);
        _L$2: {
          _L$3: {
            if (sub === undefined) {
              break _L$3;
            } else {
              const _Some$2 = sub;
              const _sub = _Some$2;
              if (_M0MPB3Map8containsGsRP39stillfail5rules4lock6MemberE(s.members, _sub)) {
                const _p$3 = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(s.members, _sub);
                let _tmp;
                if (_p$3 === undefined) {
                  _tmp = $panic();
                } else {
                  const _p$4 = _p$3;
                  _tmp = _p$4;
                }
                const was_owner$2 = _tmp.role === "owner";
                const _bind$10 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change12MemberRemove(was_owner$2)), "only owners and admins remove members, owners owners");
                if (_bind$10.$tag === 1) {
                  const _ok = _bind$10;
                  _ok._0;
                } else {
                  return _bind$10;
                }
                const _p$4 = _M0FP39stillfail5rules4lock6owners(s);
                const _bind$11 = _M0FP39stillfail5rules4lock5applyN4needS6237(was_owner$2 ? _p$4 >= 2 : _p$4 >= 1, "a lock keeps an owner");
                if (_bind$11.$tag === 1) {
                  const _ok = _bind$11;
                  _ok._0;
                } else {
                  return _bind$11;
                }
                _M0MPB3Map6removeGsRP39stillfail5rules4lock6MemberE(s.members, _sub);
                const _bind$12 = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(s.devices));
                const _bind$13 = _bind$12.len;
                const _bind$14 = _bind$12.buf;
                let _tmp$2 = 0;
                while (true) {
                  const _ = _tmp$2;
                  if (_ < _bind$13) {
                    const k = _bind$14[_];
                    const _p$5 = _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(s.devices, k);
                    let _tmp$3;
                    if (_p$5 === undefined) {
                      _tmp$3 = $panic();
                    } else {
                      const _p$6 = _p$5;
                      _tmp$3 = _p$6;
                    }
                    if (_tmp$3.sub === _sub) {
                      _M0MPB3Map6removeGsRP39stillfail5rules4lock6DeviceE(s.devices, k);
                    }
                    _tmp$2 = _ + 1 | 0;
                    continue;
                  } else {
                    break;
                  }
                }
                const _bind$15 = _M0MPB4Iter9to__arrayGUssEE(_M0MPB3Map4keysGsRP39stillfail5rules4lock12PersonDeviceE(s.passkeys));
                const _bind$16 = _bind$15.len;
                const _bind$17 = _bind$15.buf;
                let _tmp$3 = 0;
                while (true) {
                  const _ = _tmp$3;
                  if (_ < _bind$16) {
                    const k = _bind$17[_];
                    const _p$5 = _M0MPB3Map3getGsRP39stillfail5rules4lock7PasskeyE(s.passkeys, k);
                    let _tmp$4;
                    if (_p$5 === undefined) {
                      _tmp$4 = $panic();
                    } else {
                      const _p$6 = _p$5;
                      _tmp$4 = _p$6;
                    }
                    if (_tmp$4.sub === _sub) {
                      _M0MPB3Map6removeGsRP39stillfail5rules4lock7PasskeyE(s.passkeys, k);
                    }
                    _tmp$3 = _ + 1 | 0;
                    continue;
                  } else {
                    break;
                  }
                }
                _M0MPB3Map6removeGsuE(s.signed, _sub);
                _M0MPB3Map6removeGssE(s.persons, _sub);
              } else {
                break _L$3;
              }
            }
            break _L$2;
          }
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no such member"));
        }
        break;
      }
      case "device": {
        const _bind$10 = _M0FP39stillfail5rules4lock6device(b, at, c);
        let d;
        if (_bind$10.$tag === 1) {
          const _ok = _bind$10;
          d = _ok._0;
        } else {
          return _bind$10;
        }
        const _bind$11 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change3Own(d.sub === _by.sub)), "members add only their own devices");
        if (_bind$11.$tag === 1) {
          const _ok = _bind$11;
          _ok._0;
        } else {
          return _bind$11;
        }
        const _bind$12 = _M0FP39stillfail5rules4lock3add(s, new _M0TP39stillfail5rules4lock6Device(d.id, d.sub, d.kind, d.label, d.sign_key, d.endpoints, d.exp, _by.sub, _M0FP39stillfail5rules4lock7own__of(prev, d.sub, _by, _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(prev.devices, d.id), d.sign_key)));
        if (_bind$12.$tag === 1) {
          const _ok = _bind$12;
          _ok._0;
        } else {
          return _bind$12;
        }
        break;
      }
      case "device.remove": {
        const _bind$13 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "id"));
        let d$2;
        if (_bind$13 === undefined) {
          d$2 = undefined;
        } else {
          const _Some$2 = _bind$13;
          const _id = _Some$2;
          d$2 = _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(s.devices, _id);
        }
        if (d$2 === undefined) {
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no such device"));
        } else {
          const _Some$2 = d$2;
          const _d = _Some$2;
          const _bind$14 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change3Own(_d.sub === _by.sub)), "members remove only their own devices");
          if (_bind$14.$tag === 1) {
            const _ok = _bind$14;
            _ok._0;
          } else {
            return _bind$14;
          }
          _M0MPB3Map6removeGsRP39stillfail5rules4lock6DeviceE(s.devices, _d.id);
        }
        break;
      }
      case "passkey": {
        const _bind$14 = _M0FP39stillfail5rules4lock7passkey(b, c);
        let p;
        if (_bind$14.$tag === 1) {
          const _ok = _bind$14;
          p = _ok._0;
        } else {
          return _bind$14;
        }
        const _bind$15 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0MPB3Map8containsGsRP39stillfail5rules4lock6MemberE(s.members, p.sub), "a passkey is a member's");
        if (_bind$15.$tag === 1) {
          const _ok = _bind$15;
          _ok._0;
        } else {
          return _bind$15;
        }
        const _bind$16 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change3Own(p.sub === _by.sub)), "members add only their own passkeys");
        if (_bind$16.$tag === 1) {
          const _ok = _bind$16;
          _ok._0;
        } else {
          return _bind$16;
        }
        _M0FP39stillfail5rules4lock12add__passkey(s, new _M0TP39stillfail5rules4lock7Passkey(p.id, p.sub, p.key, p.label, _M0FP39stillfail5rules4lock7own__of(prev, p.sub, _by, undefined, undefined)));
        break;
      }
      case "passkey.remove": {
        const _bind$17 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
        let p$2;
        if (_bind$17 === undefined) {
          p$2 = undefined;
        } else {
          const _Some$2 = _bind$17;
          const _k = _Some$2;
          p$2 = _M0MPB3Map3getGsRP39stillfail5rules4lock7PasskeyE(s.passkeys, _k);
        }
        if (p$2 === undefined) {
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no such passkey"));
        } else {
          const _Some$2 = p$2;
          const _p$3 = _Some$2;
          const _bind$18 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change3Own(_p$3.sub === _by.sub)), "members remove only their own passkeys");
          if (_bind$18.$tag === 1) {
            const _ok = _bind$18;
            _ok._0;
          } else {
            return _bind$18;
          }
          _M0MPB3Map6removeGsRP39stillfail5rules4lock7PasskeyE(s.passkeys, _p$3.key);
        }
        break;
      }
      case "person": {
        const sub$2 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "sub"));
        _L$3: {
          _L$4: {
            if (sub$2 === undefined) {
              break _L$4;
            } else {
              const _Some$2 = sub$2;
              const _sub = _Some$2;
              if (_M0MPB3Map8containsGsRP39stillfail5rules4lock6MemberE(s.members, _sub)) {
                _L$5: {
                  _L$6: {
                    const _bind$18 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "person"));
                    if (_bind$18 === undefined) {
                      break _L$6;
                    } else {
                      const _Some$3 = _bind$18;
                      const _person = _Some$3;
                      if (_M0FP39stillfail5rules4lock9is__hex32(_person)) {
                        const _p$3 = _sub === _by.sub;
                        const _p$4 = _by.own;
                        const _bind$19 = _M0FP39stillfail5rules4lock5applyN4needS6237(!_p$3 ? false : _p$4, "members bind only themselves to a lock of their own, from their own device");
                        if (_bind$19.$tag === 1) {
                          const _ok = _bind$19;
                          _ok._0;
                        } else {
                          return _bind$19;
                        }
                        _M0MPB3Map3setGssE(s.persons, _sub, _person);
                      } else {
                        break _L$6;
                      }
                    }
                    break _L$5;
                  }
                  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a person's lock is named by its genesis's hash"));
                }
              } else {
                break _L$4;
              }
            }
            break _L$3;
          }
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a person's lock is a member's"));
        }
        break;
      }
      case "station": {
        const _bind$18 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change6Roster__), "only owners and admins add stations");
        if (_bind$18.$tag === 1) {
          const _ok = _bind$18;
          _ok._0;
        } else {
          return _bind$18;
        }
        const _bind$19 = _M0FP39stillfail5rules4lock7station(b);
        let st;
        if (_bind$19.$tag === 1) {
          const _ok = _bind$19;
          st = _ok._0;
        } else {
          return _bind$19;
        }
        _M0MPB3Map3setGsRP39stillfail5rules4lock7StationE(s.stations, st.key, st);
        break;
      }
      case "station.remove": {
        const _bind$20 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change6Roster__), "only owners and admins remove stations");
        if (_bind$20.$tag === 1) {
          const _ok = _bind$20;
          _ok._0;
        } else {
          return _bind$20;
        }
        const _bind$21 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
        if (_bind$21 === undefined) {
        } else {
          const _Some$2 = _bind$21;
          const _k = _Some$2;
          _M0MPB3Map6removeGsRP39stillfail5rules4lock7StationE(s.stations, _k);
        }
        break;
      }
      case "gateway": {
        const _bind$22 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change6Roster__) && _M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(b, "key")), "only owners and admins add gateways, by iroh id");
        if (_bind$22.$tag === 1) {
          const _ok = _bind$22;
          _ok._0;
        } else {
          return _bind$22;
        }
        const _tmp = s.gateways;
        const _p$3 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
        let _tmp$2;
        if (_p$3 === undefined) {
          _tmp$2 = $panic();
        } else {
          const _p$4 = _p$3;
          _tmp$2 = _p$4;
        }
        _M0MPB3Map3setGsuE(_tmp, _tmp$2, undefined);
        break;
      }
      case "gateway.remove": {
        const _bind$23 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change6Roster__), "only owners and admins remove gateways");
        if (_bind$23.$tag === 1) {
          const _ok = _bind$23;
          _ok._0;
        } else {
          return _bind$23;
        }
        const _bind$24 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
        if (_bind$24 === undefined) {
        } else {
          const _Some$2 = _bind$24;
          const _k = _Some$2;
          _M0MPB3Map6removeGsuE(s.gateways, _k);
        }
        break;
      }
      case "cloud_keys": {
        let _tmp$3;
        if (_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change9CloudKeys__)) {
          const _bind$25 = _M0FP39stillfail5rules4lock5field(b, "keys");
          _tmp$3 = !(_bind$25 === undefined);
        } else {
          _tmp$3 = false;
        }
        const _bind$25 = _M0FP39stillfail5rules4lock5applyN4needS6237(_tmp$3, "only owners change the control plane's keys");
        if (_bind$25.$tag === 1) {
          const _ok = _bind$25;
          _ok._0;
        } else {
          return _bind$25;
        }
        const _p$4 = _M0FP39stillfail5rules4lock5field(b, "keys");
        let _tmp$4;
        if (_p$4 === undefined) {
          _tmp$4 = $panic();
        } else {
          const _p$5 = _p$4;
          _tmp$4 = _p$5;
        }
        out = new _M0TP39stillfail5rules4lock9LockState(s.ws, s.seq, s.head, s.genesis, s.origins, s.rp_id, _tmp$4, s.members, s.devices, s.sign_keys, s.passkeys, s.signed, s.stations, s.gateways, s.persons, s.disabled, s.moved);
        break;
      }
      case "disable": {
        const _bind$26 = _M0FP39stillfail5rules4lock5applyN4needS6237(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change7Disable__), "only owners turn the lock off");
        if (_bind$26.$tag === 1) {
          const _ok = _bind$26;
          _ok._0;
        } else {
          return _bind$26;
        }
        out = new _M0TP39stillfail5rules4lock9LockState(s.ws, s.seq, s.head, s.genesis, s.origins, s.rp_id, s.cloud_keys, s.members, s.devices, s.sign_keys, s.passkeys, s.signed, s.stations, s.gateways, s.persons, true, s.moved);
        break;
      }
      case "moved": {
        const _bind$27 = _M0FP39stillfail5rules4lock5applyN4needS6237(_by.role === "owner" && (_by.own && !_by.passkey), "only an owner's own app device hands the lock over");
        if (_bind$27.$tag === 1) {
          const _ok = _bind$27;
          _ok._0;
        } else {
          return _bind$27;
        }
        let one;
        if (b === undefined) {
          one = false;
        } else {
          const _Some$2 = b;
          const _x = _Some$2;
          if (_x.$tag === 6) {
            const _Object = _x;
            const _m = _Object._0;
            one = _m.size === 1;
          } else {
            one = false;
          }
        }
        _L$4: {
          _L$5: {
            if (one) {
              const _bind$28 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "root"));
              if (_bind$28 === undefined) {
                break _L$5;
              } else {
                const _Some$2 = _bind$28;
                const _root = _Some$2;
                if (_M0FP39stillfail5rules4lock9is__hex32(_root)) {
                  out = new _M0TP39stillfail5rules4lock9LockState(s.ws, s.seq, s.head, s.genesis, s.origins, s.rp_id, s.cloud_keys, s.members, s.devices, s.sign_keys, s.passkeys, s.signed, s.stations, s.gateways, s.persons, s.disabled, _root);
                } else {
                  break _L$5;
                }
              }
            } else {
              break _L$5;
            }
            break _L$4;
          }
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("a handover names the person log it goes to, by its genesis's hash"));
        }
        break;
      }
      default: {
        const _bind$28 = _M0FP39stillfail5rules4lock6refuse(`unknown entry kind ${_M0FP39stillfail5rules4lock10kind__text(_M0FP39stillfail5rules4lock5field(v, "kind"))}`);
        if (_bind$28.$tag === 1) {
          const _ok = _bind$28;
          _ok._0;
        } else {
          return _bind$28;
        }
      }
    }
    return _by.own ? new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(out) : new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock9LockState(prev.ws, prev.seq + 1, hash, prev.genesis, prev.origins, prev.rp_id, prev.cloud_keys, prev.members, prev.devices, prev.sign_keys, prev.passkeys, prev.signed, prev.stations, prev.gateways, prev.persons, prev.disabled, prev.moved));
  }
}
function _M0FP39stillfail5rules4lock4fold(entries, now, c) {
  if (entries.len === 0) {
    const _bind = _M0FP39stillfail5rules4lock6refuse("no lock");
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _ok._0;
    } else {
      return _bind;
    }
  }
  if (0 >= entries.len) {
    $panic();
  }
  const _bind = _M0FP39stillfail5rules4lock7genesis(entries.buf[0], c);
  let s;
  if (_bind.$tag === 1) {
    const _ok = _bind;
    s = _ok._0;
  } else {
    return _bind;
  }
  const _bind$2 = entries.len;
  let _tmp = 1;
  while (true) {
    const i = _tmp;
    if (i < _bind$2) {
      const _tmp$2 = s;
      if (i < 0 || i >= entries.len) {
        $panic();
      }
      const _bind$3 = _M0FP39stillfail5rules4lock5apply(_tmp$2, entries.buf[i], now, c);
      let _tmp$3;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _tmp$3 = _ok._0;
      } else {
        return _bind$3;
      }
      s = _tmp$3;
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(s);
}
function _M0FP39stillfail5rules4lock5admit(s, sub, endpoint, base, proof, now, c) {
  let d = undefined;
  if (base === undefined) {
  } else {
    const _Some = base;
    const _base = _Some;
    if (proof === undefined) {
    } else {
      const _Some$2 = proof;
      const _proof = _Some$2;
      let _tmp;
      const _p = "";
      if (!(_base === _p)) {
        let _tmp$2;
        const _p$2 = "";
        if (!(_proof === _p$2)) {
          _tmp$2 = _M0FP39stillfail5rules4lock9is__hex32(_base) && c.method_table.method_3(c.self, s.ws, _base, endpoint, _proof);
        } else {
          _tmp$2 = false;
        }
        _tmp = _tmp$2;
      } else {
        _tmp = false;
      }
      if (_tmp) {
        d = _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(s.devices, _base);
      }
    }
  }
  const _bind = d;
  if (_bind === undefined) {
    d = _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(s.devices, endpoint);
  }
  const _bind$2 = d;
  if (_bind$2 === undefined) {
    const _it = _M0MPB3Map5iter2GssE(s.devices);
    while (true) {
      const _bind$3 = _M0MPB5Iter24nextGssE(_it);
      if (_bind$3 === undefined) {
        break;
      } else {
        const _Some = _bind$3;
        const _x = _Some;
        const _x$2 = _x._1;
        const _bind$4 = _x$2.endpoints;
        if (_bind$4 === undefined) {
        } else {
          const _Some$2 = _bind$4;
          const _es = _Some$2;
          if (_M0MPC15array5Array8containsGsE(_es, endpoint)) {
            d = _x$2;
            break;
          }
        }
        continue;
      }
    }
  }
  const _bind$3 = d;
  let theirs;
  if (_bind$3 === undefined) {
    theirs = false;
  } else {
    const _Some = _bind$3;
    const _d = _Some;
    theirs = _d.sub === sub;
  }
  const _bind$4 = d;
  let live;
  if (_bind$4 === undefined) {
    live = false;
  } else {
    const _Some = _bind$4;
    const _d = _Some;
    const _bind$5 = _d.exp;
    let _p;
    if (_bind$5.$tag === 1) {
      _p = true;
    } else {
      _p = false;
    }
    const _p$2 = $i64_trunc_f64(_M0MPC16option6Option10unwrap__orGdE(_d.exp, 0));
    const _p$3 = $i64_trunc_f64(now);
    live = !_p || BigInt.asIntN(64, _p$2) > BigInt.asIntN(64, _p$3);
  }
  const _bind$5 = d;
  let role;
  if (_bind$5 === undefined) {
    role = undefined;
  } else {
    const _Some = _bind$5;
    const _d = _Some;
    role = _M0MPC16option6Option3mapGRP39stillfail5rules4lock6MembersE(_M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(s.members, _d.sub), (m) => m.role);
  }
  const _bind$6 = d;
  const _bind$7 = _M0FP39stillfail5rules4role9admission(!(_bind$6 === undefined), theirs, live, !(role === undefined));
  switch (_bind$7) {
    case 0: {
      const _p = d;
      let _tmp;
      if (_p === undefined) {
        _tmp = $panic();
      } else {
        const _p$2 = _p;
        _tmp = _p$2;
      }
      const _tmp$2 = _tmp;
      let _tmp$3;
      if (role === undefined) {
        _tmp$3 = $panic();
      } else {
        const _p$2 = role;
        _tmp$3 = _p$2;
      }
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE2Ok({ _0: _tmp$2, _1: _tmp$3 });
    }
    case 1: {
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("this device is not confirmed in the workspace's lock"));
    }
    case 2: {
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("this device is someone else's in the workspace's lock"));
    }
    case 3: {
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("this device's confirmation ran out"));
    }
    default: {
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("not a member in the workspace's lock"));
    }
  }
}
function _M0FP39stillfail5rules4lock6beforeN5placeS6378(x, y) {
  return _M0IP016_24default__implPB7Compare6op__ltGsE(x, y) ? _M0FP39stillfail5rules4lock6beforeN5tupleS6379 : _M0IP016_24default__implPB7Compare6op__gtGsE(x, y) ? _M0FP39stillfail5rules4lock6beforeN5tupleS6380 : _M0FP39stillfail5rules4lock6beforeN5tupleS6381;
}
function _M0FP39stillfail5rules4lock6before(wa, ra, ta, ha, wb, rb, tb, hb) {
  const _bind = _M0FP39stillfail5rules4lock6beforeN5placeS6378(ta, tb);
  const _pta = _bind._0;
  const _ptb = _bind._1;
  const _bind$2 = _M0FP39stillfail5rules4lock6beforeN5placeS6378(ha, hb);
  const _pha = _bind$2._0;
  const _phb = _bind$2._1;
  return _M0FP39stillfail5rules4fork4step(wa, ra, _pta, _pha, wb, rb, _ptb, _phb);
}
function _M0FP39stillfail5rules4lock6places(xs) {
  const sorted = _M0MPC15array5Array4copyGsE(xs);
  _M0MPC15array5Array4sortGsE(sorted);
  const _bind = [];
  const at = _M0MPB3Map3MapGsiE(new _M0TPB9ArrayViewGUsiEE(_bind, 0, 0), undefined);
  const _bind$2 = sorted.len;
  const _bind$3 = sorted.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind$2) {
      const x = _bind$3[_];
      if (!_M0MPB3Map8containsGsiE(at, x)) {
        _M0MPB3Map3setGsiE(at, x, at.size);
      }
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0MPC15array10FixedArray5makeiGiE(xs.len, (i) => {
    if (i < 0 || i >= xs.len) {
      $panic();
    }
    const _p = _M0MPB3Map3getGsiE(at, xs.buf[i]);
    if (_p === undefined) {
      return $panic();
    } else {
      const _p$2 = _p;
      return _p$2;
    }
  });
}
function _M0FP39stillfail5rules4lock6activeN9sig__textS6408GRP39stillfail5rules4lock9LockStateE(entries, i) {
  let _try_err;
  _L: {
    if (i < 0 || i >= entries.len) {
      $panic();
    }
    const _bind = _M0FP39stillfail5rules4form9canonical(_M0FP39stillfail5rules4lock7sig__of(entries.buf[i]));
    if (_bind.$tag === 1) {
      const _ok = _bind;
      return _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
  }
  return "";
}
function _M0FP39stillfail5rules4lock6activeN5firstS6409GRP39stillfail5rules4lock9LockStateE(_env, h, take) {
  const by_hash = _env._2;
  const entries = _env._1;
  const off = _env._0;
  let got = undefined;
  const _p = _M0MPB3Map3getGsRPB5ArrayGiEE(by_hash, h);
  let _bind;
  if (_p === undefined) {
    _bind = $panic();
  } else {
    const _p$2 = _p;
    _bind = _p$2;
  }
  const _bind$2 = _bind.len;
  const _bind$3 = _bind.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind$2) {
      const i = _bind$3[_];
      _L: {
        const _bind$4 = got;
        if (_bind$4 === undefined) {
        } else {
          _M0MPB3Map3setGiRP39stillfail5rules4lock3OffE(off, i, _M0DTP39stillfail5rules4lock3Off5Again__);
          break _L;
        }
        let why;
        _L$2: {
          _L$3: {
            let _bind$5;
            let _try_err;
            _L$4: {
              _L$5: {
                if (i < 0 || i >= entries.len) {
                  $panic();
                }
                const _bind$6 = take(entries.buf[i]);
                let _tmp$2;
                if (_bind$6.$tag === 1) {
                  const _ok = _bind$6;
                  _tmp$2 = _ok._0;
                } else {
                  const _err = _bind$6;
                  _try_err = _err._0;
                  break _L$5;
                }
                _bind$5 = new _M0DTPB6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(_tmp$2);
                break _L$4;
              }
              _bind$5 = new _M0DTPB6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(_try_err);
            }
            if (_bind$5.$tag === 1) {
              const _Ok = _bind$5;
              const _s = _Ok._0;
              got = new _M0TP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateE(i, h, _s);
            } else {
              const _Err = _bind$5;
              const _x = _Err._0;
              if (_x.$tag === 2) {
                const _Refused = _x;
                const _why = _Refused._0;
                why = _why;
                break _L$3;
              } else {
                const _Refusal = _x;
                const _why = _Refusal._0;
                why = _why;
                break _L$3;
              }
            }
            break _L$2;
          }
          _M0MPB3Map3setGiRP39stillfail5rules4lock3OffE(off, i, new _M0DTP39stillfail5rules4lock3Off8NotValid(why));
        }
        break _L;
      }
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return got;
}
function _M0FP39stillfail5rules4lock6activeGRP39stillfail5rules4lock9LockStateE(entries, genesis, log, c) {
  const _bind = [];
  const off = _M0MPB3Map3MapGiRP39stillfail5rules4lock3OffE(new _M0TPB9ArrayViewGUiRP39stillfail5rules4lock3OffEE(_bind, 0, 0), undefined);
  const hashes = new _M0TPB5ArrayGsE([], 0);
  const _bind$2 = entries.len;
  const _bind$3 = entries.buf;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind$2) {
      const e = _bind$3[i];
      let h;
      let _try_err;
      _L: {
        _L$2: {
          const _bind$4 = _M0FP39stillfail5rules4lock11entry__hash(e, c);
          if (_bind$4.$tag === 1) {
            const _ok = _bind$4;
            h = _ok._0;
          } else {
            const _err = _bind$4;
            _try_err = _err._0;
            break _L$2;
          }
          break _L;
        }
        let why;
        _L$3: {
          if (_try_err.$tag === 2) {
            const _Refused = _try_err;
            const _why = _Refused._0;
            why = _why;
            break _L$3;
          } else {
            const _Refusal = _try_err;
            const _why = _Refusal._0;
            why = _why;
            break _L$3;
          }
        }
        _M0MPB3Map3setGiRP39stillfail5rules4lock3OffE(off, i, new _M0DTP39stillfail5rules4lock3Off8NotValid(why));
        h = "";
      }
      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(hashes, h);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _bind$4 = [];
  const by_hash = _M0MPB3Map3MapGsRPB5ArrayGiEE(new _M0TPB9ArrayViewGUsRPB5ArrayGiEEE(_bind$4, 0, 0), undefined);
  const _bind$5 = [];
  const kids = _M0MPB3Map3MapGsRPB5ArrayGsEE(new _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(_bind$5, 0, 0), undefined);
  const _bind$6 = hashes.len;
  const _bind$7 = hashes.buf;
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp$2;
    if (i < _bind$6) {
      const h = _bind$7[i];
      _L: {
        if (h === "") {
          break _L;
        }
        const _bind$8 = _M0MPB3Map3getGsRPB5ArrayGiEE(by_hash, h);
        if (_bind$8 === undefined) {
          _M0MPB3Map3setGsRPB5ArrayGiEE(by_hash, h, new _M0TPB5ArrayGiE([i], 1));
          if (i < 0 || i >= entries.len) {
            $panic();
          }
          const _bind$9 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(entries.buf[i], "prev"));
          if (_bind$9 === undefined) {
          } else {
            const _Some = _bind$9;
            const _p = _Some;
            const _bind$10 = _M0MPB3Map3getGsRPB5ArrayGsEE(kids, _p);
            if (_bind$10 === undefined) {
              _M0MPB3Map3setGsRPB5ArrayGsEE(kids, _p, new _M0TPB5ArrayGsE([h], 1));
            } else {
              const _Some$2 = _bind$10;
              const _ks = _Some$2;
              _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_ks, h);
            }
          }
        } else {
          const _Some = _bind$8;
          const _xs = _Some;
          _M0MPC15array5Array4pushGiE(_xs, i);
        }
        break _L;
      }
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _it = _M0MPB3Map5iter2GssE(by_hash);
  while (true) {
    const _bind$8 = _M0MPB5Iter24nextGssE(_it);
    if (_bind$8 === undefined) {
      break;
    } else {
      const _Some = _bind$8;
      const _x = _Some;
      const _xs = _x._1;
      _M0MPC15array5Array8sort__byGiE(_xs, (a, b) => _M0IPC16string6StringPB7Compare7compare(_M0FP39stillfail5rules4lock6activeN9sig__textS6408GRP39stillfail5rules4lock9LockStateE(entries, a), _M0FP39stillfail5rules4lock6activeN9sig__textS6408GRP39stillfail5rules4lock9LockStateE(entries, b)));
      continue;
    }
  }
  const _env = { _0: off, _1: entries, _2: by_hash };
  if (_M0MPB3Map8containsGsRPB5ArrayGiEE(by_hash, genesis)) {
    const _bind$8 = _M0FP39stillfail5rules4lock6activeN5firstS6409GRP39stillfail5rules4lock9LockStateE(_env, genesis, log.start);
    let root;
    if (_bind$8 === undefined) {
      _L: {
        const _p = _M0MPB3Map3getGsRPB5ArrayGiEE(by_hash, genesis);
        let _bind$9;
        if (_p === undefined) {
          _bind$9 = $panic();
        } else {
          const _p$2 = _p;
          _bind$9 = _p$2;
        }
        if (0 >= _bind$9.len) {
          $panic();
        }
        const _bind$10 = _M0MPB3Map3getGiRP39stillfail5rules4lock3OffE(off, _bind$9.buf[0]);
        if (_bind$10 === undefined) {
          break _L;
        } else {
          const _Some = _bind$10;
          const _x = _Some;
          if (_x.$tag === 0) {
            const _NotValid = _x;
            const _why = _NotValid._0;
            return new _M0DTPC16result6ResultGRP39stillfail5rules4lock5ChainRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(_why));
          } else {
            break _L;
          }
        }
      }
      return new _M0DTPC16result6ResultGRP39stillfail5rules4lock5ChainRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no lock"));
    } else {
      const _Some = _bind$8;
      root = _Some;
    }
    const _bind$9 = [{ _0: genesis, _1: root }];
    const nodes = _M0MPB3Map3MapGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_bind$9, 0, 1), undefined);
    const _bind$10 = [];
    const children = _M0MPB3Map3MapGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(new _M0TPB9ArrayViewGUsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEEE(_bind$10, 0, 0), undefined);
    const todo = new _M0TPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE([root], 1);
    while (true) {
      const _bind$11 = _M0MPC15array5Array3popGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(todo);
      if (_bind$11 === undefined) {
        break;
      } else {
        const _Some = _bind$11;
        const _p = _Some;
        const ks = new _M0TPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE([], 0);
        const _bind$12 = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0MPB3Map3getGsRPB5ArrayGsEE(kids, _p.hash), new _M0TPB5ArrayGsE([], 0));
        const _bind$13 = _bind$12.len;
        const _bind$14 = _bind$12.buf;
        let _tmp$3 = 0;
        while (true) {
          const _ = _tmp$3;
          if (_ < _bind$13) {
            const h = _bind$14[_];
            const _bind$15 = _M0FP39stillfail5rules4lock6activeN5firstS6409GRP39stillfail5rules4lock9LockStateE(_env, h, (e) => {
              const _func = log.next;
              return _func(_p.state, e);
            });
            if (_bind$15 === undefined) {
            } else {
              const _Some$2 = _bind$15;
              const _n = _Some$2;
              _M0MPB3Map3setGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(nodes, h, _n);
              _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(ks, _n);
              _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(todo, _n);
            }
            _tmp$3 = _ + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        _M0MPB3Map3setGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(children, _p.hash, ks);
      }
      continue;
    }
    const chain = new _M0TPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE([root], 1);
    const beaten = new _M0TPB5ArrayGsE([], 0);
    while (true) {
      const _bind$11 = chain.len - 1 | 0;
      if (_bind$11 < 0 || _bind$11 >= chain.len) {
        $panic();
      }
      const p = chain.buf[_bind$11];
      _L: {
        _L$2: {
          const _bind$12 = _M0MPB3Map3getGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(children, p.hash);
          if (_bind$12 === undefined) {
            break _L$2;
          } else {
            const _Some = _bind$12;
            const _ks = _Some;
            if (_ks.len > 0) {
              const ws = _M0MPC15array10FixedArray5makeiGiE(_ks.len, (i) => {
                const _func = log.weight;
                const _tmp$3 = p.state;
                if (i < 0 || i >= _ks.len) {
                  $panic();
                }
                const _bind$13 = _ks.buf[i].at;
                if (_bind$13 < 0 || _bind$13 >= entries.len) {
                  $panic();
                }
                return _func(_tmp$3, entries.buf[_bind$13]);
              });
              const rs = _M0MPC15array10FixedArray5makeiGbE(_ks.len, (i) => {
                const _func = log.removal;
                const _tmp$3 = p.state;
                if (i < 0 || i >= _ks.len) {
                  $panic();
                }
                const _bind$13 = _ks.buf[i].at;
                if (_bind$13 < 0 || _bind$13 >= entries.len) {
                  $panic();
                }
                return _func(_tmp$3, entries.buf[_bind$13]);
              });
              const _p = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_ks.len);
              const _p$2 = _ks.len;
              const _p$3 = _ks.buf;
              let _tmp$3 = 0;
              while (true) {
                const _p$4 = _tmp$3;
                if (_p$4 < _p$2) {
                  const _p$5 = _p$3[_p$4];
                  const _p$6 = p.hash;
                  const _p$7 = _p$5.at;
                  if (_p$7 < 0 || _p$7 >= entries.len) {
                    $panic();
                  }
                  const _p$8 = _M0FP39stillfail5rules4lock8sig__key(entries.buf[_p$7]);
                  const _p$9 = c.method_table.method_0(c.self, `${_p$6}\u0000${_p$8}`);
                  _p.buf[_p$4] = _p$9;
                  _tmp$3 = _p$4 + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              const ties = _p;
              const ts = _M0FP39stillfail5rules4lock6places(ties);
              const _p$4 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_ks.len);
              const _p$5 = _ks.len;
              const _p$6 = _ks.buf;
              let _tmp$4 = 0;
              while (true) {
                const _p$7 = _tmp$4;
                if (_p$7 < _p$5) {
                  const _p$8 = _p$6[_p$7];
                  const _p$9 = _p$8.hash;
                  _p$4.buf[_p$7] = _p$9;
                  _tmp$4 = _p$7 + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              const hs = _M0FP39stillfail5rules4lock6places(_p$4);
              const b = _M0FP39stillfail5rules4fork4best(ws, rs, ts, hs);
              const _bind$13 = _ks.len;
              const _bind$14 = _ks.buf;
              let _tmp$5 = 0;
              while (true) {
                const i = _tmp$5;
                if (i < _bind$13) {
                  const k = _bind$14[i];
                  if (i !== b) {
                    const by = _M0MPC16option6Option10unwrap__orGRP39stillfail5rules4fork4StepE(_M0FP39stillfail5rules4fork4step(b >>> 0 < ws.length ? ws[b] : $oob(), b >>> 0 < rs.length ? rs[b] : $oob(), b >>> 0 < ts.length ? ts[b] : $oob(), b >>> 0 < hs.length ? hs[b] : $oob(), i >>> 0 < ws.length ? ws[i] : $oob(), i >>> 0 < rs.length ? rs[i] : $oob(), i >>> 0 < ts.length ? ts[i] : $oob(), i >>> 0 < hs.length ? hs[i] : $oob()), 3);
                    const _tmp$6 = k.at;
                    if (b < 0 || b >= _ks.len) {
                      $panic();
                    }
                    _M0MPB3Map3setGiRP39stillfail5rules4lock3OffE(off, _tmp$6, new _M0DTP39stillfail5rules4lock3Off6Beaten(_ks.buf[b].hash, by));
                    _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(beaten, k.hash);
                  }
                  _tmp$5 = i + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              if (b < 0 || b >= _ks.len) {
                $panic();
              }
              _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(chain, _ks.buf[b]);
            } else {
              break _L$2;
            }
          }
          break _L;
        }
        break;
      }
      continue;
    }
    const _bind$11 = beaten.len;
    const _bind$12 = beaten.buf;
    let _tmp$3 = 0;
    while (true) {
      const _ = _tmp$3;
      if (_ < _bind$11) {
        const top = _bind$12[_];
        const below = _M0MPC15array5Array4copyGsE(_M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0MPB3Map3getGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(children, top), new _M0TPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE([], 0)));
        while (true) {
          const _bind$13 = _M0MPC15array5Array3popGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(below);
          if (_bind$13 === undefined) {
            break;
          } else {
            const _Some = _bind$13;
            const _n = _Some;
            _M0MPB3Map3setGiRP39stillfail5rules4lock3OffE(off, _n.at, new _M0DTP39stillfail5rules4lock3Off5Below(top));
            const _bind$14 = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0MPB3Map3getGsRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(children, _n.hash), new _M0TPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE([], 0));
            const _bind$15 = _bind$14.len;
            const _bind$16 = _bind$14.buf;
            let _tmp$4 = 0;
            while (true) {
              const _$2 = _tmp$4;
              if (_$2 < _bind$15) {
                const k = _bind$16[_$2];
                _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(below, k);
                _tmp$4 = _$2 + 1 | 0;
                continue;
              } else {
                break;
              }
            }
          }
          continue;
        }
        _tmp$3 = _ + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _bind$13 = hashes.len;
    const _bind$14 = hashes.buf;
    let _tmp$4 = 0;
    while (true) {
      const i = _tmp$4;
      if (i < _bind$13) {
        const h = _bind$14[i];
        let _tmp$5;
        const _p = "";
        if (!(h === _p)) {
          let _tmp$6;
          if (!_M0MPB3Map8containsGiRP39stillfail5rules4lock3OffE(off, i)) {
            const _bind$15 = _M0MPB3Map3getGsRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEE(nodes, h);
            let _tmp$7;
            if (_bind$15 === undefined) {
              _tmp$7 = false;
            } else {
              const _Some = _bind$15;
              const _n = _Some;
              _tmp$7 = _n.at === i;
            }
            _tmp$6 = !_tmp$7;
          } else {
            _tmp$6 = false;
          }
          _tmp$5 = _tmp$6;
        } else {
          _tmp$5 = false;
        }
        if (_tmp$5) {
          let _tmp$6;
          _L: {
            _L$2: {
              if (i < 0 || i >= entries.len) {
                $panic();
              }
              const _bind$15 = _M0FP39stillfail5rules4lock5field(entries.buf[i], "prev");
              if (_bind$15 === undefined) {
                break _L$2;
              } else {
                const _Some = _bind$15;
                const _x = _Some;
                if (_x.$tag === 0) {
                  _tmp$6 = _M0FP39stillfail5rules4lock6activeN6constrS6410GRP39stillfail5rules4lock9LockStateE;
                } else {
                  break _L$2;
                }
              }
              break _L;
            }
            _tmp$6 = _M0DTP39stillfail5rules4lock3Off8NoParent__;
          }
          _M0MPB3Map3setGiRP39stillfail5rules4lock3OffE(off, i, _tmp$6);
        }
        _tmp$4 = i + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const out = new _M0TPB5ArrayGUiRP39stillfail5rules4lock3OffEE([], 0);
    const _bind$15 = entries.len;
    let _tmp$5 = 0;
    while (true) {
      const i = _tmp$5;
      if (i < _bind$15) {
        const _bind$16 = _M0MPB3Map3getGiRP39stillfail5rules4lock3OffE(off, i);
        if (_bind$16 === undefined) {
        } else {
          const _Some = _bind$16;
          const _o = _Some;
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(out, { _0: i, _1: _o });
        }
        _tmp$5 = i + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _p = _M0MPC15array5Array20unsafe__make__uninitGUssEE(chain.len);
    const _p$2 = chain.len;
    const _p$3 = chain.buf;
    let _tmp$6 = 0;
    while (true) {
      const _p$4 = _tmp$6;
      if (_p$4 < _p$2) {
        const _p$5 = _p$3[_p$4];
        const _p$6 = _p$5.at;
        if (_p$6 < 0 || _p$6 >= entries.len) {
          $panic();
        }
        const _p$7 = entries.buf[_p$6];
        _p.buf[_p$4] = _p$7;
        _tmp$6 = _p$4 + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _p$4 = _M0MPC15array5Array20unsafe__make__uninitGiE(chain.len);
    const _p$5 = chain.len;
    const _p$6 = chain.buf;
    let _tmp$7 = 0;
    while (true) {
      const _p$7 = _tmp$7;
      if (_p$7 < _p$5) {
        const _p$8 = _p$6[_p$7];
        const _p$9 = _p$8.at;
        _p$4.buf[_p$7] = _p$9;
        _tmp$7 = _p$7 + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _p$7 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(chain.len);
    const _p$8 = chain.len;
    const _p$9 = chain.buf;
    let _tmp$8 = 0;
    while (true) {
      const _p$10 = _tmp$8;
      if (_p$10 < _p$8) {
        const _p$11 = _p$9[_p$10];
        const _p$12 = _p$11.hash;
        _p$7.buf[_p$10] = _p$12;
        _tmp$8 = _p$10 + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock5ChainRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock5Chain(_p, _p$4, _p$7, out));
  } else {
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock5ChainRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no lock"));
  }
}
function _M0FP39stillfail5rules4lock11lock__chain(entries, root, votes, now, c) {
  return _M0FP39stillfail5rules4lock6activeGRP39stillfail5rules4lock9LockStateE(entries, root, new _M0TP39stillfail5rules4lock3LogGRP39stillfail5rules4lock9LockStateE((e) => _M0FP39stillfail5rules4lock7genesis(e, c), (s, e) => _M0FP39stillfail5rules4lock5apply(s, e, now, c), (s, e) => {
    if (votes === 0) {
      return 1;
    } else {
      const _bind = _M0FP39stillfail5rules4lock6signer(s, _M0FP39stillfail5rules4lock8sig__key(e), _M0DTPC16option6OptionGdE4None__);
      if (_bind === undefined) {
        return 0;
      } else {
        const _Some = _bind;
        const _w = _Some;
        return _w.role === "owner" ? 3 : _w.role === "admin" ? 2 : 1;
      }
    }
  }, (s, e) => {
    const v = e;
    if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "kind")), _M0FP39stillfail5rules4lock11lock__chainN6constrS6776)) {
      const _bind = _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(s.devices, _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(v, "body"), "id")), ""));
      let _tmp;
      if (_bind === undefined) {
        _tmp = false;
      } else {
        const _Some = _bind;
        const _d = _Some;
        const _bind$2 = _d.sign_key;
        _tmp = !(_bind$2 === undefined);
      }
      return _tmp;
    } else {
      return false;
    }
  }), c);
}
function _M0FP39stillfail5rules4lock13person__chain(entries, root, c) {
  return _M0FP39stillfail5rules4lock6activeGRP39stillfail5rules4lock9LockStateE(entries, root, new _M0TP39stillfail5rules4lock3LogGRP39stillfail5rules4lock6PersonE((e) => {
    const sub = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(e, "body"), "sub")), "");
    return _M0FP39stillfail5rules4lock12person__step(undefined, e, sub, c);
  }, (p, e) => _M0FP39stillfail5rules4lock12person__step(p, e, p.sub, c), (_discard_, _discard_$2) => 1, (_discard_, e) => _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(e, "kind")), _M0FP39stillfail5rules4lock13person__chainN6constrS6797)), c);
}
function _M0FP39stillfail5rules4lock13body__refusalN3tagS6809(_env, x) {
  const ws = _env._1;
  const c = _env._0;
  const _p = x.genesis;
  return c.method_table.method_0(c.self, `stillfail/ws-tag/1\n${ws}\n${_p}`);
}
function _M0FP39stillfail5rules4lock13body__refusal(ws, b, commits, c) {
  if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "ws")), ws)) {
    let h;
    let _try_err;
    _L: {
      _L$2: {
        const _bind = _M0FP39stillfail5rules4lock10body__hash(b, c);
        if (_bind.$tag === 1) {
          const _ok = _bind;
          h = _ok._0;
        } else {
          const _err = _bind;
          _try_err = _err._0;
          break _L$2;
        }
        break _L;
      }
      return _M0FP39stillfail5rules4lock13body__refusalN6constrS6810;
    }
    const _p = new _M0TPB5ArrayGRP39stillfail5rules4lock6CommitE([], 0);
    const _p$2 = commits.len;
    const _p$3 = commits.buf;
    let mine;
    let _tmp = 0;
    while (true) {
      const _p$4 = _tmp;
      if (_p$4 < _p$2) {
        const _p$5 = _p$3[_p$4];
        let _tmp$2;
        if (_p$5.chain.len > 0) {
          const _p$6 = _p$5.chain;
          const _p$7 = _p$5.chain.len - 1 | 0;
          if (_p$7 < 0 || _p$7 >= _p$6.len) {
            $panic();
          }
          const _p$8 = _p$6.buf[_p$7];
          _tmp$2 = _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_p$8, "kind")), _M0FP39stillfail5rules4lock13body__refusalN6constrS6811) && _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(_p$8, "body"), "h")), h);
        } else {
          _tmp$2 = false;
        }
        if (_tmp$2) {
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_p, _p$5);
        }
        _tmp = _p$4 + 1 | 0;
        continue;
      } else {
        mine = _p;
        break;
      }
    }
    if (mine.len > 0) {
      const _env = { _0: c, _1: ws };
      const _p$4 = new _M0TPB5ArrayGRP39stillfail5rules4lock6CommitE([], 0);
      const _p$5 = mine.len;
      const _p$6 = mine.buf;
      let tagged;
      let _tmp$2 = 0;
      while (true) {
        const _p$7 = _tmp$2;
        if (_p$7 < _p$5) {
          const _p$8 = _p$6[_p$7];
          const _p$9 = _p$8.chain;
          const _p$10 = _p$8.chain.len - 1 | 0;
          if (_p$10 < 0 || _p$10 >= _p$9.len) {
            $panic();
          }
          if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(_p$9.buf[_p$10], "body"), "t")), _M0FP39stillfail5rules4lock13body__refusalN3tagS6809(_env, _p$8))) {
            _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(_p$4, _p$8);
          }
          _tmp$2 = _p$7 + 1 | 0;
          continue;
        } else {
          tagged = _p$4;
          break;
        }
      }
      if (tagged.len > 0) {
        const _bind = _M0FP39stillfail5rules4lock9body__why(b);
        if (_bind === undefined) {
        } else {
          const _Some = _bind;
          const _why = _Some;
          return `its shape: ${_why}`;
        }
        const prev = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "prev"));
        if (prev === undefined) {
          return undefined;
        } else {
          const _Some = prev;
          const _p$7 = _Some;
          const _bind$2 = tagged.len;
          const _bind$3 = tagged.buf;
          let _tmp$3 = 0;
          while (true) {
            const _ = _tmp$3;
            if (_ < _bind$2) {
              const x = _bind$3[_];
              const t = _M0FP39stillfail5rules4lock13body__refusalN3tagS6809(_env, x);
              const _bind$4 = x.chain.len - 1 | 0;
              let _tmp$4 = 0;
              while (true) {
                const i = _tmp$4;
                if (i < _bind$4) {
                  const _bind$5 = x.chain;
                  if (i < 0 || i >= _bind$5.len) {
                    $panic();
                  }
                  const e = _bind$5.buf[i];
                  if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(e, "kind")), _M0FP39stillfail5rules4lock13body__refusalN6constrS6812) && (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(e, "body"), "t")), t) && _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(e, "body"), "h")), _p$7))) {
                    return undefined;
                  }
                  _tmp$4 = i + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              _tmp$3 = _ + 1 | 0;
              continue;
            } else {
              break;
            }
          }
          return _M0FP39stillfail5rules4lock13body__refusalN6constrS6813;
        }
      } else {
        return _M0FP39stillfail5rules4lock13body__refusalN6constrS6814;
      }
    } else {
      return _M0FP39stillfail5rules4lock13body__refusalN6constrS6815;
    }
  } else {
    return _M0FP39stillfail5rules4lock13body__refusalN6constrS6816;
  }
}
function _M0FP39stillfail5rules5vault5field(v, k) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 6) {
        const _Object = _x;
        const _m = _Object._0;
        return _M0MPB3Map3getGsRPC14json4JsonE(_m, k);
      } else {
        break _L;
      }
    }
  }
  return undefined;
}
function _M0FP39stillfail5rules5vault10is__object(v) {
  if (v === undefined) {
    return false;
  } else {
    const _Some = v;
    const _x = _Some;
    if (_x.$tag === 6) {
      return true;
    } else {
      return false;
    }
  }
}
function _M0FP39stillfail5rules5vault10js__string(v) {
  if (v === undefined) {
    return "undefined";
  } else {
    const _Some = v;
    const _x = _Some;
    switch (_x.$tag) {
      case 4: {
        const _String = _x;
        return _String._0;
      }
      case 0: {
        return "null";
      }
      case 1: {
        return "true";
      }
      case 2: {
        return "false";
      }
      case 3: {
        let _try_err;
        _L: {
          const _p = _Some;
          let _tmp;
          if (_p === undefined) {
            _tmp = $panic();
          } else {
            const _p$2 = _p;
            _tmp = _p$2;
          }
          const _bind = _M0FP39stillfail5rules4form9canonical(_tmp);
          if (_bind.$tag === 1) {
            const _ok = _bind;
            return _ok._0;
          } else {
            const _err = _bind;
            _try_err = _err._0;
            break _L;
          }
        }
        return "NaN";
      }
      case 5: {
        const _Array = _x;
        const _xs = _Array._0;
        const b = _M0MPB13StringBuilder21StringBuilder_2einner(8);
        const _bind = _xs.len;
        const _bind$2 = _xs.buf;
        let _tmp = 0;
        while (true) {
          const i = _tmp;
          if (i < _bind) {
            const x = _bind$2[i];
            if (i > 0) {
              _M0IPB13StringBuilderPB6Logger13write__string(b, ",");
            }
            if (x.$tag === 0) {
            } else {
              _M0IPB13StringBuilderPB6Logger13write__string(b, _M0FP39stillfail5rules5vault10js__string(x));
            }
            _tmp = i + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        return b.val;
      }
      default: {
        return "[object Object]";
      }
    }
  }
}
function _M0FP39stillfail5rules5vault3int(v) {
  if (v === undefined) {
    return false;
  } else {
    const _Some = v;
    const _x = _Some;
    if (_x.$tag === 3) {
      const _Number = _x;
      const _n = _Number._0;
      return _n === _M0MPC16double6Double5floor(_n) && (_n >= 0 && _n <= 9007199254740991);
    } else {
      return false;
    }
  }
}
function _M0FP39stillfail5rules5vault3num(v) {
  if (v === undefined) {
    return 0;
  } else {
    const _Some = v;
    const _x = _Some;
    if (_x.$tag === 3) {
      const _Number = _x;
      return _Number._0;
    } else {
      return 0;
    }
  }
}
function _M0FP39stillfail5rules5vault12text_2einner(v, max) {
  if (v === undefined) {
    return false;
  } else {
    const _Some = v;
    const _x = _Some;
    if (_x.$tag === 4) {
      const _String = _x;
      const _s = _String._0;
      return _s.length <= max;
    } else {
      return false;
    }
  }
}
function _M0FP39stillfail5rules5vault8text__of(v) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 4) {
        const _String = _x;
        const _s = _String._0;
        return _s;
      } else {
        break _L;
      }
    }
  }
  return undefined;
}
function _M0FP39stillfail5rules5vault10all__units(s, ok) {
  const _bind = s.length;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      if (!ok(i >>> 0 < s.length ? s.charCodeAt(i) : $oob())) {
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
function _M0FP39stillfail5rules5vault5alnum(c) {
  return c >= 48 && c <= 57 || (c >= 97 && c <= 122 || c >= 65 && c <= 90);
}
function _M0FP39stillfail5rules5vault3b64(v, max) {
  if (v === undefined) {
    return false;
  } else {
    const _Some = v;
    const _x = _Some;
    if (_x.$tag === 4) {
      const _String = _x;
      const _s = _String._0;
      return _s.length <= max ? _M0FP39stillfail5rules5vault10all__units(_s, (c) => _M0FP39stillfail5rules5vault5alnum(c) || (c === 95 || c === 45)) : false;
    } else {
      return false;
    }
  }
}
function _M0FP39stillfail5rules5vault5hex32(s) {
  return s.length === 64 && _M0FP39stillfail5rules5vault10all__units(s, (c) => c >= 48 && c <= 57 || c >= 97 && c <= 102);
}
function _M0FP39stillfail5rules5vault8box__key(s) {
  return _M0MPC16string6String11has__prefix(s, _M0FP39stillfail5rules5vault8box__keyN6recordS6918) && _M0FP39stillfail5rules5vault5hex32(_M0MPC16string10StringView9to__owned(_M0MPC16string6String12view_2einner(s, 7, undefined)));
}
function _M0FP39stillfail5rules5vault8ulid__id(s, prefix) {
  if (!_M0MPC16string6String11has__prefix(s, new _M0TPC16string10StringView(prefix, 0, prefix.length)) || s.length !== (prefix.length + 26 | 0)) {
    return false;
  }
  return _M0FP39stillfail5rules5vault10all__units(_M0MPC16string10StringView9to__owned(_M0MPC16string6String12view_2einner(s, prefix.length, undefined)), (c) => c >= 48 && c <= 57 || c >= 65 && c <= 90 && (c !== 73 && (c !== 76 && (c !== 79 && c !== 85))));
}
function _M0FP39stillfail5rules5vault4hostN2lcS6923(c) {
  return c >= 97 && c <= 122 || c >= 48 && c <= 57;
}
function _M0FP39stillfail5rules5vault4host(s) {
  const name = _M0MPC16string6String11has__prefix(s, _M0FP39stillfail5rules5vault4hostN6recordS6924) ? _M0MPC16string10StringView9to__owned(_M0MPC16string6String12view_2einner(s, 2, undefined)) : s;
  const labels = _M0MPB4Iter9to__arrayGUssEE(_M0MPC16string6String5split(name, _M0FP39stillfail5rules5vault4hostN6recordS6925));
  const _bind = labels.len;
  const _bind$2 = labels.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const l = _bind$2[_];
      const l$2 = _M0MPC16string10StringView9to__owned(l);
      if (l$2.length === 0) {
        return false;
      }
      const first = 0 >>> 0 < l$2.length ? l$2.charCodeAt(0) : $oob();
      const _tmp$2 = l$2.length - 1 | 0;
      const last = _tmp$2 >>> 0 < l$2.length ? l$2.charCodeAt(_tmp$2) : $oob();
      if (!_M0FP39stillfail5rules5vault4hostN2lcS6923(first) || (!_M0FP39stillfail5rules5vault4hostN2lcS6923(last) || !_M0FP39stillfail5rules5vault10all__units(l$2, (c) => _M0FP39stillfail5rules5vault4hostN2lcS6923(c) || c === 45))) {
        return false;
      }
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return true;
}
function _M0FP39stillfail5rules5vault9env__name(s) {
  if (s.length > 0) {
    let _tmp;
    const _p = 0 >>> 0 < s.length ? s.charCodeAt(0) : $oob();
    if (!(_p >= 48 && _p <= 57)) {
      _tmp = _M0FP39stillfail5rules5vault10all__units(s, (c) => _M0FP39stillfail5rules5vault5alnum(c) || c === 95);
    } else {
      _tmp = false;
    }
    return _tmp;
  } else {
    return false;
  }
}
function _M0FP39stillfail5rules5vault7strings(v) {
  _L: {
    if (v === undefined) {
      break _L;
    } else {
      const _Some = v;
      const _x = _Some;
      if (_x.$tag === 5) {
        const _Array = _x;
        return _Array._0;
      } else {
        break _L;
      }
    }
  }
  return new _M0TPB5ArrayGRPC14json4JsonE([], 0);
}
function _M0FP39stillfail5rules5vault9has__text(xs, s) {
  const _p = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(xs);
  while (true) {
    const _p$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p);
    if (_p$2 === undefined) {
      return false;
    } else {
      const _p$3 = _p$2;
      const _p$4 = _p$3;
      let _tmp;
      if (_p$4.$tag === 4) {
        const _p$5 = _p$4;
        const _p$6 = _p$5._0;
        _tmp = _p$6 === s;
      } else {
        _tmp = false;
      }
      if (_tmp) {
        return true;
      }
      continue;
    }
  }
}
function _M0FP39stillfail5rules5vault6unique(xs) {
  const _bind = xs.len;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      let _tmp$2 = 0;
      while (true) {
        const j = _tmp$2;
        if (j < i) {
          if (i < 0 || i >= xs.len) {
            $panic();
          }
          const _tmp$3 = xs.buf[i];
          if (j < 0 || j >= xs.len) {
            $panic();
          }
          if (_M0IPC14json4JsonPB2Eq5equal(_tmp$3, xs.buf[j])) {
            _L: {
              _L$2: {
                if (i < 0 || i >= xs.len) {
                  $panic();
                }
                const _bind$2 = xs.buf[i];
                switch (_bind$2.$tag) {
                  case 4: {
                    break _L$2;
                  }
                  case 3: {
                    break _L$2;
                  }
                  case 0: {
                    break _L$2;
                  }
                  case 1: {
                    break _L$2;
                  }
                  case 2: {
                    break _L$2;
                  }
                }
                break _L;
              }
              return false;
            }
          }
          _tmp$2 = j + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return true;
}
function _M0FP39stillfail5rules5vault10sig__shape(s) {
  if (_M0FP39stillfail5rules5vault10is__object(s)) {
    const _bind = _M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(s, "key"));
    let _tmp;
    if (_bind === undefined) {
      _tmp = false;
    } else {
      const _bind$2 = _M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(s, "sig"));
      _tmp = _bind$2 === undefined ? false : _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(s, "alg")), _M0FP39stillfail5rules5vault10sig__shapeN6constrS6959) || _M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(s, "alg")), _M0FP39stillfail5rules5vault10sig__shapeN6constrS6960);
    }
    return _tmp;
  } else {
    return false;
  }
}
function _M0FP39stillfail5rules5vault12without__sig(o) {
  if (o.$tag === 6) {
    const _Object = o;
    const _m = _Object._0;
    const _bind = [];
    const rest = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 0), undefined);
    const _it = _M0MPB3Map5iter2GssE(_m);
    while (true) {
      const _bind$2 = _M0MPB5Iter24nextGssE(_it);
      if (_bind$2 === undefined) {
        break;
      } else {
        const _Some = _bind$2;
        const _x = _Some;
        const _k = _x._0;
        const _v = _x._1;
        const _p = "sig";
        if (!(_k === _p)) {
          _M0MPB3Map3setGsRPC14json4JsonE(rest, _k, _v);
        }
        continue;
      }
    }
    return new _M0DTPC14json4Json6Object(rest);
  } else {
    return o;
  }
}
function _M0FP39stillfail5rules5vault10signed__ok(o, tag, c) {
  const sig = _M0FP39stillfail5rules5vault5field(o, "sig");
  if (_M0FP39stillfail5rules5vault10is__object(sig)) {
    const _bind = _M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(sig, "sig"));
    if (_bind === undefined) {
      return false;
    } else {
      let text;
      let _try_err;
      _L: {
        _L$2: {
          const _bind$2 = _M0FP39stillfail5rules4form9canonical(_M0FP39stillfail5rules5vault12without__sig(o));
          if (_bind$2.$tag === 1) {
            const _ok = _bind$2;
            text = _ok._0;
          } else {
            const _err = _bind$2;
            _try_err = _err._0;
            break _L$2;
          }
          break _L;
        }
        return false;
      }
      let _tmp;
      if (sig === undefined) {
        _tmp = $panic();
      } else {
        const _p = sig;
        _tmp = _p;
      }
      return c.method_table.method_0(c.self, _tmp, tag, text);
    }
  } else {
    return false;
  }
}
function _M0FP39stillfail5rules5vault10signer__of(lock, key) {
  const _it = _M0MPB3Map5iter2GssE(lock.devices);
  while (true) {
    const _bind = _M0MPB5Iter24nextGssE(_it);
    if (_bind === undefined) {
      break;
    } else {
      const _Some = _bind;
      const _x = _Some;
      const _id = _x._0;
      const _d = _x._1;
      if (_M0FP39stillfail5rules4role13device__signs(_d.kind === "app", _M0IPC16option6OptionPB2Eq5equalGsE(_d.sign_key, key), _d.own, _M0MPB3Map8containsGsuE(lock.members, _d.sub))) {
        return { _0: _d.sub, _1: _id };
      }
      continue;
    }
  }
  return undefined;
}
function _M0FP39stillfail5rules5vault8cert__ok(lock, cert, ever, c) {
  let _tmp;
  if (!_M0FP39stillfail5rules5vault10is__object(cert)) {
    _tmp = true;
  } else {
    let _tmp$2;
    if (_M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(cert, "v")) !== 1) {
      _tmp$2 = true;
    } else {
      let _tmp$3;
      const _bind = _M0FP39stillfail5rules5vault5field(cert, "v");
      let _tmp$4;
      if (_bind === undefined) {
        _tmp$4 = false;
      } else {
        const _Some = _bind;
        const _x = _Some;
        if (_x.$tag === 3) {
          _tmp$4 = true;
        } else {
          _tmp$4 = false;
        }
      }
      if (!_tmp$4) {
        _tmp$3 = true;
      } else {
        _tmp$3 = _M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(cert, "ws")), lock.ws);
      }
      _tmp$2 = _tmp$3;
    }
    _tmp = _tmp$2;
  }
  if (_tmp) {
    return _M0FP39stillfail5rules5vault8cert__okN5shapeS6997;
  }
  const device = _M0FP39stillfail5rules5vault10js__string(_M0FP39stillfail5rules5vault5field(cert, "device"));
  if (!_M0FP39stillfail5rules5vault5hex32(device) || (!_M0FP39stillfail5rules5vault8box__key(_M0FP39stillfail5rules5vault10js__string(_M0FP39stillfail5rules5vault5field(cert, "box"))) || (!_M0FP39stillfail5rules5vault3int(_M0FP39stillfail5rules5vault5field(cert, "at")) || !_M0FP39stillfail5rules5vault10sig__shape(_M0FP39stillfail5rules5vault5field(cert, "sig"))))) {
    return _M0FP39stillfail5rules5vault8cert__okN5shapeS6997;
  }
  let d;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules5vault5field(cert, "device");
      if (_bind === undefined) {
        break _L$2;
      } else {
        const _Some = _bind;
        const _x = _Some;
        if (_x.$tag === 4) {
          const _String = _x;
          const _id = _String._0;
          d = _M0MPB3Map3getGsRP39stillfail5rules5vault6DeviceE(lock.devices, _id);
        } else {
          break _L$2;
        }
      }
      break _L;
    }
    d = undefined;
  }
  _L$2: {
    if (d === undefined) {
      break _L$2;
    } else {
      const _Some = d;
      const _d = _Some;
      if (_d.kind === "app") {
        if (_M0MPB3Map8containsGsuE(lock.members, _d.sub)) {
          const _p = _d.own;
          if (!(_p ? true : ever)) {
            return _M0FP39stillfail5rules5vault8cert__okN6constrS6994;
          }
          const _p$2 = _M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(_M0FP39stillfail5rules5vault5field(cert, "sig"), "key"));
          let key;
          if (_p$2 === undefined) {
            key = $panic();
          } else {
            const _p$3 = _p$2;
            key = _p$3;
          }
          const had = _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0MPB3Map3getGsRPB5ArrayGsEE(lock.sign_keys, device), new _M0TPB5ArrayGsE([], 0));
          const _p$3 = _M0IPC16option6OptionPB2Eq5equalGsE(_d.sign_key, key);
          const _p$4 = _M0MPC15array5Array8containsGsE(had, key);
          if (!(_p$3 ? true : ever ? _p$4 : false)) {
            return _M0FP39stillfail5rules5vault8cert__okN6constrS6995;
          }
          let _tmp$2;
          if (cert === undefined) {
            _tmp$2 = $panic();
          } else {
            const _p$5 = cert;
            _tmp$2 = _p$5;
          }
          if (!_M0FP39stillfail5rules5vault10signed__ok(_tmp$2, "stillfail-vault-box/1", c)) {
            return _M0FP39stillfail5rules5vault8cert__okN6constrS6996;
          }
          return undefined;
        } else {
          break _L$2;
        }
      } else {
        break _L$2;
      }
    }
  }
  return _M0FP39stillfail5rules5vault8cert__okN6constrS6993;
}
function _M0FP39stillfail5rules5vault5whole(n) {
  let _try_err;
  _L: {
    const _p = undefined;
    const _bind = _M0FP39stillfail5rules4form9canonical(new _M0DTPC14json4Json6Number(n, _p));
    if (_bind.$tag === 1) {
      const _ok = _bind;
      return _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
  }
  return "NaN";
}
function _M0FP39stillfail5rules5vault9vault__ok(lock, prev, next, copy, c) {
  const v = next;
  let _tmp;
  if (!_M0FP39stillfail5rules5vault10is__object(v)) {
    _tmp = true;
  } else {
    let _tmp$2;
    const _bind = _M0FP39stillfail5rules5vault5field(v, "v");
    let _tmp$3;
    if (_bind === undefined) {
      _tmp$3 = false;
    } else {
      const _Some = _bind;
      const _x = _Some;
      if (_x.$tag === 3) {
        const _Number = _x;
        const _x$2 = _Number._0;
        if (_x$2 === 1) {
          _tmp$3 = true;
        } else {
          _tmp$3 = false;
        }
      } else {
        _tmp$3 = false;
      }
    }
    if (!_tmp$3) {
      _tmp$2 = true;
    } else {
      _tmp$2 = _M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(v, "ws")), lock.ws);
    }
    _tmp = _tmp$2;
  }
  if (_tmp) {
    return _M0FP39stillfail5rules5vault9vault__okN6constrS7021;
  }
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules5vault5field(v, "id");
      if (_bind === undefined) {
        break _L$2;
      } else {
        const _Some = _bind;
        const _x = _Some;
        if (_x.$tag === 4) {
          const _String = _x;
          const _id = _String._0;
          if (_M0FP39stillfail5rules5vault8ulid__id(_id, "v_")) {
            if (!_M0FP39stillfail5rules5vault3int(_M0FP39stillfail5rules5vault5field(v, "seq")) || (!_M0FP39stillfail5rules5vault3int(_M0FP39stillfail5rules5vault5field(v, "epoch")) || !_M0FP39stillfail5rules5vault3int(_M0FP39stillfail5rules5vault5field(v, "at")))) {
              return _M0FP39stillfail5rules5vault9vault__okN6constrS7023;
            }
            _L$3: {
              _L$4: {
                const _bind$2 = _M0FP39stillfail5rules5vault5field(v, "owner");
                if (_bind$2 === undefined) {
                  break _L$4;
                } else {
                  const _Some$2 = _bind$2;
                  const _x$2 = _Some$2;
                  if (_x$2.$tag === 4) {
                    const _String$2 = _x$2;
                    const _owner = _String$2._0;
                    if (_owner.length <= 200) {
                      const _p = "";
                      if (!(_owner === _p)) {
                        if (_M0FP39stillfail5rules5vault12text_2einner(_M0FP39stillfail5rules5vault5field(v, "name"), 200)) {
                          let members;
                          _L$5: {
                            _L$6: {
                              const _bind$3 = _M0FP39stillfail5rules5vault5field(v, "members");
                              if (_bind$3 === undefined) {
                                break _L$6;
                              } else {
                                const _Some$3 = _bind$3;
                                const _x$3 = _Some$3;
                                if (_x$3.$tag === 5) {
                                  const _Array = _x$3;
                                  const _xs = _Array._0;
                                  let _tmp$2;
                                  if (_xs.len <= 256) {
                                    let _tmp$3;
                                    const _p$2 = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_xs);
                                    let _tmp$4;
                                    while (true) {
                                      const _p$3 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p$2);
                                      if (_p$3 === undefined) {
                                        _tmp$4 = true;
                                        break;
                                      } else {
                                        const _p$4 = _p$3;
                                        const _p$5 = _p$4;
                                        let _tmp$5;
                                        if (_p$5.$tag === 4) {
                                          const _p$6 = _p$5;
                                          const _p$7 = _p$6._0;
                                          if (_p$7.length <= 200) {
                                            const _p$8 = "";
                                            _tmp$5 = !(_p$7 === _p$8);
                                          } else {
                                            _tmp$5 = false;
                                          }
                                        } else {
                                          _tmp$5 = false;
                                        }
                                        if (_tmp$5) {
                                        } else {
                                          _tmp$4 = false;
                                          break;
                                        }
                                        continue;
                                      }
                                    }
                                    if (_tmp$4) {
                                      _tmp$3 = _M0FP39stillfail5rules5vault6unique(_xs);
                                    } else {
                                      _tmp$3 = false;
                                    }
                                    _tmp$2 = _tmp$3;
                                  } else {
                                    _tmp$2 = false;
                                  }
                                  if (_tmp$2) {
                                    const _p$2 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_xs.len);
                                    const _p$3 = _xs.len;
                                    const _p$4 = _xs.buf;
                                    let _tmp$3 = 0;
                                    while (true) {
                                      const _p$5 = _tmp$3;
                                      if (_p$5 < _p$3) {
                                        const _p$6 = _p$4[_p$5];
                                        const _p$7 = _M0FP39stillfail5rules5vault8text__of(_p$6);
                                        let _p$8;
                                        if (_p$7 === undefined) {
                                          _p$8 = $panic();
                                        } else {
                                          const _p$9 = _p$7;
                                          _p$8 = _p$9;
                                        }
                                        _p$2.buf[_p$5] = _p$8;
                                        _tmp$3 = _p$5 + 1 | 0;
                                        continue;
                                      } else {
                                        break;
                                      }
                                    }
                                    members = _p$2;
                                  } else {
                                    break _L$6;
                                  }
                                } else {
                                  break _L$6;
                                }
                              }
                              break _L$5;
                            }
                            return _M0FP39stillfail5rules5vault9vault__okN6constrS7025;
                          }
                          if (!_M0MPC15array5Array8containsGsE(members, _owner)) {
                            return _M0FP39stillfail5rules5vault9vault__okN6constrS7026;
                          }
                          let keys;
                          _L$6: {
                            _L$7: {
                              const _bind$3 = _M0FP39stillfail5rules5vault5field(v, "keys");
                              if (_bind$3 === undefined) {
                                break _L$7;
                              } else {
                                const _Some$3 = _bind$3;
                                const _x$3 = _Some$3;
                                if (_x$3.$tag === 5) {
                                  const _Array = _x$3;
                                  const _xs = _Array._0;
                                  if (_xs.len <= 1024) {
                                    keys = _xs;
                                  } else {
                                    break _L$7;
                                  }
                                } else {
                                  break _L$7;
                                }
                              }
                              break _L$6;
                            }
                            return _M0FP39stillfail5rules5vault9vault__okN6constrS7027;
                          }
                          const _bind$3 = _M0FP39stillfail5rules5vault5field(v, "recovery");
                          if (_bind$3 === undefined) {
                          } else {
                            if (!_M0FP39stillfail5rules5vault3b64(_M0FP39stillfail5rules5vault5field(v, "recovery"), 200)) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7028;
                            }
                          }
                          const _bind$4 = _M0FP39stillfail5rules5vault5field(v, "lasts");
                          if (_bind$4 === undefined) {
                          } else {
                            const _Some$3 = _bind$4;
                            const _l = _Some$3;
                            let _tmp$2;
                            if (_l.$tag === 4) {
                              const _String$3 = _l;
                              const _s = _String$3._0;
                              _tmp$2 = _M0MPC15array5Array8containsGsE(_M0FP39stillfail5rules5vault6scopes, _s);
                            } else {
                              _tmp$2 = false;
                            }
                            if (!_tmp$2) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7029;
                            }
                          }
                          const _bind$5 = _M0FP39stillfail5rules5vault5field(v, "deleted");
                          let deleted;
                          if (_bind$5 === undefined) {
                            deleted = false;
                          } else {
                            const _Some$3 = _bind$5;
                            const _x$3 = _Some$3;
                            if (_x$3.$tag === 1) {
                              deleted = true;
                            } else {
                              deleted = false;
                            }
                          }
                          const _bind$6 = _M0FP39stillfail5rules5vault5field(v, "deleted");
                          if (_bind$6 === undefined) {
                          } else {
                            _L$7: {
                              _L$8: {
                                if (!deleted) {
                                  break _L$8;
                                } else {
                                  if (keys.len > 0) {
                                    break _L$8;
                                  } else {
                                    const _bind$7 = _M0FP39stillfail5rules5vault5field(v, "recovery");
                                    if (_bind$7 === undefined) {
                                    } else {
                                      break _L$8;
                                    }
                                  }
                                }
                                break _L$7;
                              }
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7030;
                            }
                          }
                          if (!_M0FP39stillfail5rules5vault10sig__shape(_M0FP39stillfail5rules5vault5field(v, "sig"))) {
                            return _M0FP39stillfail5rules5vault9vault__okN6constrS7031;
                          }
                          const seq = _M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(v, "seq"));
                          const epoch = _M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(v, "epoch"));
                          if (prev === undefined) {
                            if (seq !== 0 && !copy) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7032;
                            }
                          } else {
                            const _Some$3 = prev;
                            if (_M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(_Some$3, "id")), _id)) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7033;
                            }
                            const held = _M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(_Some$3, "seq"));
                            const _p$2 = $i64_trunc_f64(held);
                            const _p$3 = $i64_trunc_f64(seq);
                            if (!(copy ? BigInt.asIntN(64, _p$3) > BigInt.asIntN(64, _p$2) : BigInt.asUintN(64, _p$3) === BigInt.asUintN(64, BigInt.asUintN(64, _p$2 + 1n)))) {
                              return copy ? `a copy is later than seq ${_M0FP39stillfail5rules5vault5whole(held)}` : `seq ${_M0FP39stillfail5rules5vault5whole(held + 1)} follows ${_M0FP39stillfail5rules5vault5whole(held)}`;
                            }
                            if (_M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(_Some$3, "owner")), _owner)) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7034;
                            }
                            const _bind$7 = _M0FP39stillfail5rules5vault5field(_Some$3, "deleted");
                            let _p$4;
                            if (_bind$7 === undefined) {
                              _p$4 = false;
                            } else {
                              const _Some$4 = _bind$7;
                              const _x$3 = _Some$4;
                              if (_x$3.$tag === 1) {
                                _p$4 = true;
                              } else {
                                _p$4 = false;
                              }
                            }
                            if (!(!_p$4 || deleted)) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7035;
                            }
                            const held_epoch = $i64_trunc_f64(_M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(_Some$3, "epoch")));
                            const _p$5 = $i64_trunc_f64(epoch);
                            if (!(BigInt.asIntN(64, _p$5) < BigInt.asIntN(64, held_epoch) ? false : !(false && BigInt.asUintN(64, _p$5) === BigInt.asUintN(64, held_epoch)))) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7036;
                            }
                            const _p$6 = _M0MPC15array5Array20unsafe__make__uninitGORPC14json4JsonE(keys.len);
                            const _p$7 = keys.len;
                            const _p$8 = keys.buf;
                            let _tmp$2 = 0;
                            while (true) {
                              const _p$9 = _tmp$2;
                              if (_p$9 < _p$7) {
                                const _p$10 = _p$8[_p$9];
                                const _p$11 = _M0FP39stillfail5rules5vault5field(_M0FP39stillfail5rules5vault5field(_p$10, "cert"), "device");
                                _p$6.buf[_p$9] = _p$11;
                                _tmp$2 = _p$9 + 1 | 0;
                                continue;
                              } else {
                                break;
                              }
                            }
                            const devices = _p$6;
                            let gone;
                            const _p$9 = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_M0FP39stillfail5rules5vault7strings(_M0FP39stillfail5rules5vault5field(_Some$3, "members")));
                            let _tmp$3;
                            while (true) {
                              const _p$10 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p$9);
                              if (_p$10 === undefined) {
                                _tmp$3 = false;
                                break;
                              } else {
                                const _p$11 = _p$10;
                                const _p$12 = _p$11;
                                let _tmp$4;
                                if (_p$12.$tag === 4) {
                                  const _p$13 = _p$12;
                                  const _p$14 = _p$13._0;
                                  _tmp$4 = _M0MPC15array5Array8containsGsE(members, _p$14);
                                } else {
                                  _tmp$4 = false;
                                }
                                if (!_tmp$4) {
                                  _tmp$3 = true;
                                  break;
                                }
                                continue;
                              }
                            }
                            if (_tmp$3) {
                              gone = true;
                            } else {
                              const _p$10 = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_M0FP39stillfail5rules5vault7strings(_M0FP39stillfail5rules5vault5field(_Some$3, "keys")));
                              let _tmp$4;
                              while (true) {
                                const _p$11 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p$10);
                                if (_p$11 === undefined) {
                                  _tmp$4 = false;
                                  break;
                                } else {
                                  const _p$12 = _p$11;
                                  const _p$13 = _p$12;
                                  const _p$14 = _M0FP39stillfail5rules5vault5field(_M0FP39stillfail5rules5vault5field(_p$13, "cert"), "device");
                                  const _p$15 = _M0MPC15array5Array4iterGORPC14json4JsonE(devices);
                                  let _tmp$5;
                                  while (true) {
                                    const _p$16 = _M0MPB4Iter4nextGORPC14json4JsonE(_p$15);
                                    if (_p$16.$tag === 1) {
                                      const _p$17 = _p$16;
                                      const _p$18 = _p$17._0;
                                      if (_M0IPC16option6OptionPB2Eq5equalGRPC14json4JsonE(_p$18, _p$14)) {
                                        _tmp$5 = true;
                                        break;
                                      }
                                      continue;
                                    } else {
                                      _tmp$5 = false;
                                      break;
                                    }
                                  }
                                  if (!_tmp$5) {
                                    _tmp$4 = true;
                                    break;
                                  }
                                  continue;
                                }
                              }
                              gone = _tmp$4;
                            }
                            const _p$10 = $i64_trunc_f64(epoch);
                            if (!(BigInt.asIntN(64, _p$10) < BigInt.asIntN(64, held_epoch) ? false : !(gone && BigInt.asUintN(64, _p$10) === BigInt.asUintN(64, held_epoch)))) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7037;
                            }
                          }
                          const _bind$7 = members.len;
                          const _bind$8 = members.buf;
                          let _tmp$2 = 0;
                          while (true) {
                            const _ = _tmp$2;
                            if (_ < _bind$7) {
                              const m = _bind$8[_];
                              if (!_M0MPB3Map8containsGsuE(lock.members, m)) {
                                return `member ${m} is not in the lock`;
                              }
                              _tmp$2 = _ + 1 | 0;
                              continue;
                            } else {
                              break;
                            }
                          }
                          const _bind$9 = [];
                          const seen = _M0MPB3Map3MapGsuE(new _M0TPB9ArrayViewGUsuEE(_bind$9, 0, 0), undefined);
                          const _bind$10 = keys.len;
                          const _bind$11 = keys.buf;
                          let _tmp$3 = 0;
                          while (true) {
                            const _ = _tmp$3;
                            if (_ < _bind$10) {
                              const k = _bind$11[_];
                              const k$2 = k;
                              if (!_M0FP39stillfail5rules5vault10is__object(k$2) || !_M0FP39stillfail5rules5vault3b64(_M0FP39stillfail5rules5vault5field(k$2, "wrapped"), 200)) {
                                return _M0FP39stillfail5rules5vault9vault__okN6constrS7038;
                              }
                              const _bind$12 = _M0FP39stillfail5rules5vault8cert__ok(lock, _M0FP39stillfail5rules5vault5field(k$2, "cert"), true, c);
                              if (_bind$12 === undefined) {
                              } else {
                                const _Some$3 = _bind$12;
                                const _why = _Some$3;
                                return _why;
                              }
                              const _p$2 = _M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(_M0FP39stillfail5rules5vault5field(k$2, "cert"), "device"));
                              let device;
                              if (_p$2 === undefined) {
                                device = $panic();
                              } else {
                                const _p$3 = _p$2;
                                device = _p$3;
                              }
                              const _p$3 = _M0MPB3Map3getGsRP39stillfail5rules5vault6DeviceE(lock.devices, device);
                              let _tmp$4;
                              if (_p$3 === undefined) {
                                _tmp$4 = $panic();
                              } else {
                                const _p$4 = _p$3;
                                _tmp$4 = _p$4;
                              }
                              const member = _M0MPC15array5Array8containsGsE(members, _tmp$4.sub);
                              const _p$4 = _M0MPB3Map8containsGsuE(seen, device);
                              if (!(_p$4 ? false : member)) {
                                return _M0MPB3Map8containsGsuE(seen, device) ? "one key per device" : "a key is for a member's device";
                              }
                              _M0MPB3Map3setGsuE(seen, device, undefined);
                              _tmp$3 = _ + 1 | 0;
                              continue;
                            } else {
                              break;
                            }
                          }
                          const _p$2 = _M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(_M0FP39stillfail5rules5vault5field(v, "sig"), "key"));
                          let key;
                          if (_p$2 === undefined) {
                            key = $panic();
                          } else {
                            const _p$3 = _p$2;
                            key = _p$3;
                          }
                          const by = _M0FP39stillfail5rules5vault10signer__of(lock, key);
                          const _p$3 = !(by === undefined);
                          const _p$4 = _M0MPC16option6Option10unwrap__orGbE(_M0MPC16option6Option3mapGUssEbE(by, (b) => b._0 === _owner), false);
                          if (_p$3 ? _p$4 : false) {
                            if (!_M0FP39stillfail5rules5vault10signed__ok(next, "stillfail-vault/1", c)) {
                              return _M0FP39stillfail5rules5vault9vault__okN6constrS7039;
                            }
                            return undefined;
                          } else {
                            return _M0FP39stillfail5rules5vault9vault__okN6constrS7040;
                          }
                        } else {
                          break _L$3;
                        }
                      } else {
                        break _L$3;
                      }
                    } else {
                      break _L$3;
                    }
                  } else {
                    break _L$4;
                  }
                }
              }
              break _L$3;
            }
            return _M0FP39stillfail5rules5vault9vault__okN6constrS7024;
          } else {
            break _L;
          }
        } else {
          break _L$2;
        }
      }
    }
    break _L;
  }
  return _M0FP39stillfail5rules5vault9vault__okN6constrS7022;
}
function _M0FP39stillfail5rules5vault20browser__listing__ok(kind, modes, hosts) {
  const sign = kind === "browser";
  let _tmp;
  const _p = _M0MPC15array5Array8containsGsE(modes, "browser");
  if (!(sign === _p)) {
    _tmp = true;
  } else {
    _tmp = sign && modes.len !== 1;
  }
  if (_tmp) {
    return _M0FP39stillfail5rules5vault20browser__listing__okN6constrS7135;
  }
  let _tmp$2;
  if (sign) {
    let _tmp$3;
    if (hosts.len === 0) {
      _tmp$3 = true;
    } else {
      const _p$2 = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(hosts);
      let _tmp$4;
      while (true) {
        const _p$3 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p$2);
        if (_p$3 === undefined) {
          _tmp$4 = false;
          break;
        } else {
          const _p$4 = _p$3;
          const _p$5 = _p$4;
          if (_M0MPC16string6String11has__prefix(_p$5, _M0FP39stillfail5rules5vault20browser__listing__okN6recordS7136)) {
            _tmp$4 = true;
            break;
          }
          continue;
        }
      }
      _tmp$3 = _tmp$4;
    }
    _tmp$2 = _tmp$3;
  } else {
    _tmp$2 = false;
  }
  if (_tmp$2) {
    return _M0FP39stillfail5rules5vault20browser__listing__okN6constrS7137;
  }
  return undefined;
}
function _M0FP39stillfail5rules5vault11listing__ok(l) {
  _L: {
    if (_M0FP39stillfail5rules5vault10is__object(l)) {
      if (_M0FP39stillfail5rules5vault12text_2einner(_M0FP39stillfail5rules5vault5field(l, "name"), 200)) {
        _L$2: {
          const _bind = _M0FP39stillfail5rules5vault5field(l, "kind");
          if (_bind === undefined) {
            break _L$2;
          } else {
            const _Some = _bind;
            const _x = _Some;
            if (_x.$tag === 4) {
              const _String = _x;
              const _kind = _String._0;
              if (_M0MPC15array5Array8containsGsE(_M0FP39stillfail5rules5vault5kinds, _kind)) {
                let ms;
                _L$3: {
                  _L$4: {
                    const _bind$2 = _M0FP39stillfail5rules5vault5field(l, "modes");
                    if (_bind$2 === undefined) {
                      break _L$4;
                    } else {
                      const _Some$2 = _bind$2;
                      const _x$2 = _Some$2;
                      if (_x$2.$tag === 5) {
                        const _Array = _x$2;
                        const _xs = _Array._0;
                        let _tmp;
                        const _p = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_xs);
                        let _tmp$2;
                        while (true) {
                          const _p$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p);
                          if (_p$2 === undefined) {
                            _tmp$2 = true;
                            break;
                          } else {
                            const _p$3 = _p$2;
                            const _p$4 = _p$3;
                            let _tmp$3;
                            if (_p$4.$tag === 4) {
                              const _p$5 = _p$4;
                              const _p$6 = _p$5._0;
                              _tmp$3 = _M0MPC15array5Array8containsGsE(_M0FP39stillfail5rules5vault5modes, _p$6);
                            } else {
                              _tmp$3 = false;
                            }
                            if (_tmp$3) {
                            } else {
                              _tmp$2 = false;
                              break;
                            }
                            continue;
                          }
                        }
                        if (_tmp$2) {
                          _tmp = _M0FP39stillfail5rules5vault6unique(_xs);
                        } else {
                          _tmp = false;
                        }
                        if (_tmp) {
                          const _p$2 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_xs.len);
                          const _p$3 = _xs.len;
                          const _p$4 = _xs.buf;
                          let _tmp$3 = 0;
                          while (true) {
                            const _p$5 = _tmp$3;
                            if (_p$5 < _p$3) {
                              const _p$6 = _p$4[_p$5];
                              const _p$7 = _M0FP39stillfail5rules5vault8text__of(_p$6);
                              let _p$8;
                              if (_p$7 === undefined) {
                                _p$8 = $panic();
                              } else {
                                const _p$9 = _p$7;
                                _p$8 = _p$9;
                              }
                              _p$2.buf[_p$5] = _p$8;
                              _tmp$3 = _p$5 + 1 | 0;
                              continue;
                            } else {
                              break;
                            }
                          }
                          ms = _p$2;
                        } else {
                          break _L$4;
                        }
                      } else {
                        break _L$4;
                      }
                    }
                    break _L$3;
                  }
                  return _M0FP39stillfail5rules5vault11listing__okN6constrS7144;
                }
                let hs;
                _L$4: {
                  _L$5: {
                    const _bind$2 = _M0FP39stillfail5rules5vault5field(l, "hosts");
                    if (_bind$2 === undefined) {
                      break _L$5;
                    } else {
                      const _Some$2 = _bind$2;
                      const _x$2 = _Some$2;
                      if (_x$2.$tag === 5) {
                        const _Array = _x$2;
                        const _xs = _Array._0;
                        let _tmp;
                        if (_xs.len <= 64) {
                          const _p = _M0MPC15array5Array4iterGRP39stillfail5rules4lock4StmtE(_xs);
                          let _tmp$2;
                          while (true) {
                            const _p$2 = _M0MPB4Iter4nextGUsRP39stillfail5rules4lock9PersonWebEE(_p);
                            if (_p$2 === undefined) {
                              _tmp$2 = true;
                              break;
                            } else {
                              const _p$3 = _p$2;
                              const _p$4 = _p$3;
                              let _tmp$3;
                              if (_p$4.$tag === 4) {
                                const _p$5 = _p$4;
                                const _p$6 = _p$5._0;
                                _tmp$3 = _p$6.length <= 253 && _M0FP39stillfail5rules5vault4host(_p$6);
                              } else {
                                _tmp$3 = false;
                              }
                              if (_tmp$3) {
                              } else {
                                _tmp$2 = false;
                                break;
                              }
                              continue;
                            }
                          }
                          _tmp = _tmp$2;
                        } else {
                          _tmp = false;
                        }
                        if (_tmp) {
                          const _p = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_xs.len);
                          const _p$2 = _xs.len;
                          const _p$3 = _xs.buf;
                          let _tmp$2 = 0;
                          while (true) {
                            const _p$4 = _tmp$2;
                            if (_p$4 < _p$2) {
                              const _p$5 = _p$3[_p$4];
                              const _p$6 = _M0FP39stillfail5rules5vault8text__of(_p$5);
                              let _p$7;
                              if (_p$6 === undefined) {
                                _p$7 = $panic();
                              } else {
                                const _p$8 = _p$6;
                                _p$7 = _p$8;
                              }
                              _p.buf[_p$4] = _p$7;
                              _tmp$2 = _p$4 + 1 | 0;
                              continue;
                            } else {
                              break;
                            }
                          }
                          hs = _p;
                        } else {
                          break _L$5;
                        }
                      } else {
                        break _L$5;
                      }
                    }
                    break _L$4;
                  }
                  return _M0FP39stillfail5rules5vault11listing__okN6constrS7145;
                }
                const _bind$2 = _M0FP39stillfail5rules5vault20browser__listing__ok(_kind, ms, hs);
                if (_bind$2 === undefined) {
                } else {
                  const _Some$2 = _bind$2;
                  const _why = _Some$2;
                  return _why;
                }
                const _bind$3 = _M0FP39stillfail5rules5vault5field(l, "env");
                if (_bind$3 === undefined) {
                } else {
                  const _Some$2 = _bind$3;
                  const _e = _Some$2;
                  let _tmp;
                  if (_e.$tag === 4) {
                    const _String$2 = _e;
                    const _s = _String$2._0;
                    _tmp = _s.length <= 100 && _M0FP39stillfail5rules5vault9env__name(_s);
                  } else {
                    _tmp = false;
                  }
                  if (!_tmp) {
                    return _M0FP39stillfail5rules5vault11listing__okN6constrS7146;
                  }
                }
                const _bind$4 = _M0FP39stillfail5rules5vault5field(l, "lasts");
                if (_bind$4 === undefined) {
                } else {
                  const _Some$2 = _bind$4;
                  const _x$2 = _Some$2;
                  let _tmp;
                  if (_x$2.$tag === 4) {
                    const _String$2 = _x$2;
                    const _s = _String$2._0;
                    _tmp = _M0MPC15array5Array8containsGsE(_M0FP39stillfail5rules5vault6scopes, _s);
                  } else {
                    _tmp = false;
                  }
                  if (!_tmp) {
                    return _M0FP39stillfail5rules5vault11listing__okN6constrS7147;
                  }
                }
                return undefined;
              } else {
                break _L;
              }
            } else {
              break _L$2;
            }
          }
        }
        break _L;
      } else {
        break _L;
      }
    } else {
      break _L;
    }
  }
  return _M0FP39stillfail5rules5vault11listing__okN6constrS7143;
}
function _M0FP39stillfail5rules5vault8item__ok(lock, vault, prev, next, copy, c) {
  const i = next;
  const vault$2 = vault;
  let _tmp;
  if (!_M0FP39stillfail5rules5vault10is__object(i)) {
    _tmp = true;
  } else {
    let _tmp$2;
    const _bind = _M0FP39stillfail5rules5vault5field(i, "v");
    let _tmp$3;
    if (_bind === undefined) {
      _tmp$3 = false;
    } else {
      const _Some = _bind;
      const _x = _Some;
      if (_x.$tag === 3) {
        const _Number = _x;
        const _x$2 = _Number._0;
        if (_x$2 === 1) {
          _tmp$3 = true;
        } else {
          _tmp$3 = false;
        }
      } else {
        _tmp$3 = false;
      }
    }
    if (!_tmp$3) {
      _tmp$2 = true;
    } else {
      let _tmp$4;
      if (_M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(i, "ws")), lock.ws)) {
        _tmp$4 = true;
      } else {
        let _tmp$5;
        if (_M0IP016_24default__implPB2Eq10not__equalGORPC14json4JsonE(_M0FP39stillfail5rules5vault5field(i, "vault"), _M0FP39stillfail5rules5vault5field(vault$2, "id"))) {
          _tmp$5 = true;
        } else {
          const _bind$2 = _M0FP39stillfail5rules5vault5field(i, "vault");
          let _tmp$6;
          if (_bind$2 === undefined) {
            _tmp$6 = false;
          } else {
            const _Some = _bind$2;
            const _x = _Some;
            if (_x.$tag === 4) {
              _tmp$6 = true;
            } else {
              _tmp$6 = false;
            }
          }
          _tmp$5 = !_tmp$6;
        }
        _tmp$4 = _tmp$5;
      }
      _tmp$2 = _tmp$4;
    }
    _tmp = _tmp$2;
  }
  if (_tmp) {
    return _M0FP39stillfail5rules5vault8item__okN6constrS7191;
  }
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules5vault5field(i, "id");
      if (_bind === undefined) {
        break _L$2;
      } else {
        const _Some = _bind;
        const _x = _Some;
        if (_x.$tag === 4) {
          const _String = _x;
          const _id = _String._0;
          if (_M0FP39stillfail5rules5vault8ulid__id(_id, "i_")) {
            if (!_M0FP39stillfail5rules5vault3int(_M0FP39stillfail5rules5vault5field(i, "version")) || (!_M0FP39stillfail5rules5vault3int(_M0FP39stillfail5rules5vault5field(i, "epoch")) || !_M0FP39stillfail5rules5vault3int(_M0FP39stillfail5rules5vault5field(i, "at")))) {
              return _M0FP39stillfail5rules5vault8item__okN6constrS7193;
            }
            const _bind$2 = _M0FP39stillfail5rules5vault5field(i, "deleted");
            if (_bind$2 === undefined) {
            } else {
              const _Some$2 = _bind$2;
              const _d = _Some$2;
              let _tmp$2;
              if (_d.$tag === 1) {
                _tmp$2 = true;
              } else {
                _tmp$2 = false;
              }
              if (!_tmp$2) {
                return _M0FP39stillfail5rules5vault8item__okN6constrS7194;
              }
            }
            const _bind$3 = _M0FP39stillfail5rules5vault5field(i, "deleted");
            let deleted;
            if (_bind$3 === undefined) {
              deleted = false;
            } else {
              const _Some$2 = _bind$3;
              const _x$2 = _Some$2;
              if (_x$2.$tag === 1) {
                deleted = true;
              } else {
                deleted = false;
              }
            }
            if (!_M0FP39stillfail5rules5vault3b64(_M0FP39stillfail5rules5vault5field(i, "ct"), 1048576)) {
              return _M0FP39stillfail5rules5vault8item__okN6constrS7195;
            }
            const _p = _M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(i, "ct"));
            let ct;
            if (_p === undefined) {
              ct = $panic();
            } else {
              const _p$2 = _p;
              ct = _p$2;
            }
            if (deleted) {
              _L$3: {
                _L$4: {
                  const _p$2 = "";
                  if (!(ct === _p$2)) {
                    break _L$4;
                  } else {
                    const _bind$4 = _M0FP39stillfail5rules5vault5field(i, "listing");
                    if (_bind$4 === undefined) {
                    } else {
                      break _L$4;
                    }
                  }
                  break _L$3;
                }
                return _M0FP39stillfail5rules5vault8item__okN6constrS7196;
              }
            }
            if (!deleted && ct.length < 38) {
              return _M0FP39stillfail5rules5vault8item__okN6constrS7197;
            }
            const _bind$4 = _M0FP39stillfail5rules5vault5field(i, "listing");
            if (_bind$4 === undefined) {
            } else {
              const _bind$5 = _M0FP39stillfail5rules5vault11listing__ok(_M0FP39stillfail5rules5vault5field(i, "listing"));
              if (_bind$5 === undefined) {
              } else {
                const _Some$2 = _bind$5;
                const _why = _Some$2;
                return _why;
              }
            }
            if (!_M0FP39stillfail5rules5vault10sig__shape(_M0FP39stillfail5rules5vault5field(i, "sig"))) {
              return _M0FP39stillfail5rules5vault8item__okN6constrS7198;
            }
            const epoch = _M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(i, "epoch"));
            const vault_epoch = _M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(vault$2, "epoch"));
            if (!_M0FP39stillfail5rules7history15item__epoch__ok(deleted, copy, $i64_trunc_f64(epoch), $i64_trunc_f64(vault_epoch))) {
              return `an item is written under the vault's epoch ${_M0FP39stillfail5rules5vault5whole(vault_epoch)}`;
            }
            const version = _M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(i, "version"));
            if (prev === undefined) {
              if (version !== 0 && !copy) {
                return _M0FP39stillfail5rules5vault8item__okN6constrS7199;
              }
            } else {
              const _Some$2 = prev;
              if (_M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(_Some$2, "id")), _id) || _M0IP016_24default__implPB2Eq10not__equalGORPC14json4JsonE(_M0FP39stillfail5rules5vault5field(_Some$2, "vault"), _M0FP39stillfail5rules5vault5field(i, "vault"))) {
                return _M0FP39stillfail5rules5vault8item__okN6constrS7200;
              }
              const _bind$5 = _M0FP39stillfail5rules5vault5field(_Some$2, "deleted");
              let _p$2;
              if (_bind$5 === undefined) {
                _p$2 = false;
              } else {
                const _Some$3 = _bind$5;
                const _x$2 = _Some$3;
                if (_x$2.$tag === 1) {
                  _p$2 = true;
                } else {
                  _p$2 = false;
                }
              }
              if (!!_p$2) {
                return _M0FP39stillfail5rules5vault8item__okN6constrS7201;
              }
              const held = _M0FP39stillfail5rules5vault3num(_M0FP39stillfail5rules5vault5field(_Some$2, "version"));
              const _p$3 = $i64_trunc_f64(held);
              const _p$4 = $i64_trunc_f64(version);
              if (!(copy ? BigInt.asIntN(64, _p$4) > BigInt.asIntN(64, _p$3) : BigInt.asUintN(64, _p$4) === BigInt.asUintN(64, BigInt.asUintN(64, _p$3 + 1n)))) {
                return copy ? `a copy is later than version ${_M0FP39stillfail5rules5vault5whole(held)}` : `version ${_M0FP39stillfail5rules5vault5whole(held + 1)} follows ${_M0FP39stillfail5rules5vault5whole(held)}`;
              }
            }
            const _p$2 = _M0FP39stillfail5rules5vault8text__of(_M0FP39stillfail5rules5vault5field(_M0FP39stillfail5rules5vault5field(i, "sig"), "key"));
            let key;
            if (_p$2 === undefined) {
              key = $panic();
            } else {
              const _p$3 = _p$2;
              key = _p$3;
            }
            const members = _M0FP39stillfail5rules5vault7strings(_M0FP39stillfail5rules5vault5field(vault$2, "members"));
            const by = _M0FP39stillfail5rules5vault10signer__of(lock, key);
            const _p$3 = !(by === undefined);
            const _p$4 = _M0MPC16option6Option10unwrap__orGbE(_M0MPC16option6Option3mapGUssEbE(by, (b) => _M0FP39stillfail5rules5vault9has__text(members, b._0)), false);
            if (_p$3 ? _p$4 : false) {
              if (!_M0FP39stillfail5rules5vault10signed__ok(next, "stillfail-vault-item/1", c)) {
                return _M0FP39stillfail5rules5vault8item__okN6constrS7202;
              }
              return undefined;
            } else {
              return _M0FP39stillfail5rules5vault8item__okN6constrS7203;
            }
          } else {
            break _L;
          }
        } else {
          break _L$2;
        }
      }
    }
    break _L;
  }
  return _M0FP39stillfail5rules5vault8item__okN6constrS7192;
}
function _M0FP39stillfail5rules2js8json__of(v) {
  const _bind = _M0FP39stillfail5rules2js8js__kind(v);
  switch (_bind) {
    case 0: {
      return new _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(_M0DTPC14json4Json4Null__);
    }
    case 1: {
      const _p = _M0FP39stillfail5rules2js8js__bool(v);
      return new _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(_p ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__);
    }
    case 2: {
      const _p$2 = _M0FP39stillfail5rules2js7js__num(v);
      const _p$3 = undefined;
      return new _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(new _M0DTPC14json4Json6Number(_p$2, _p$3));
    }
    case 3: {
      const _p$4 = _M0FP39stillfail5rules2js7js__str(v);
      return new _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(new _M0DTPC14json4Json6String(_p$4));
    }
    case 4: {
      const xs = new _M0TPB5ArrayGRPC14json4JsonE([], 0);
      const _bind$2 = _M0FP39stillfail5rules2js7js__len(v);
      let _tmp = 0;
      while (true) {
        const i = _tmp;
        if (i < _bind$2) {
          const _bind$3 = _M0FP39stillfail5rules2js8json__of(_M0FP39stillfail5rules2js6js__at(v, i));
          let _tmp$2;
          if (_bind$3.$tag === 1) {
            const _ok = _bind$3;
            _tmp$2 = _ok._0;
          } else {
            return _bind$3;
          }
          _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(xs, _tmp$2);
          _tmp = i + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      return new _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(new _M0DTPC14json4Json5Array(xs));
    }
    case 5: {
      const keys = _M0FP39stillfail5rules2js8js__keys(v);
      const _bind$3 = [];
      const m = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$3, 0, 0), undefined);
      const _bind$4 = _M0FP39stillfail5rules2js7js__len(keys);
      let _tmp$2 = 0;
      while (true) {
        const i = _tmp$2;
        if (i < _bind$4) {
          const k = _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js6js__at(keys, i));
          const _bind$5 = _M0FP39stillfail5rules2js8json__of(_M0FP39stillfail5rules2js7js__get(v, k));
          let _tmp$3;
          if (_bind$5.$tag === 1) {
            const _ok = _bind$5;
            _tmp$3 = _ok._0;
          } else {
            return _bind$5;
          }
          _M0MPB3Map3setGsRPC14json4JsonE(m, k, _tmp$3);
          _tmp$2 = i + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      return new _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(new _M0DTPC14json4Json6Object(m));
    }
    default: {
      return new _M0DTPC16result6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE3Err(new _M0DTPC15error5Error44stillfail_2frules_2fform_2eInvalid_2eInvalid("not a lock value"));
    }
  }
}
function _M0FP39stillfail5rules2js13canonical__of(v) {
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js8json__of(v);
    let _tmp;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _tmp = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules4form9canonical(_tmp);
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      return _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
  }
  const _Invalid = _try_err;
  const _why = _Invalid._0;
  return `!${_why}`;
}
function _M0FP39stillfail5rules2js15entry__text__of(v) {
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js8json__of(v);
    let _tmp;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _tmp = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules4form11entry__text(_tmp);
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      return _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
  }
  const _Invalid = _try_err;
  const _why = _Invalid._0;
  return `!${_why}`;
}
function _M0FP39stillfail5rules2js8role__of(s) {
  switch (s) {
    case "owner": {
      return 3;
    }
    case "admin": {
      return 2;
    }
    case "member": {
      return 1;
    }
    default: {
      return 0;
    }
  }
}
function _M0FP39stillfail5rules2js10role__name(r) {
  switch (r) {
    case 3: {
      return "owner";
    }
    case 2: {
      return "admin";
    }
    case 1: {
      return "member";
    }
    default: {
      return "viewer";
    }
  }
}
function _M0FP39stillfail5rules2js11lower__role(a, b) {
  return _M0FP39stillfail5rules2js10role__name(_M0FP39stillfail5rules4role5lower(_M0FP39stillfail5rules2js8role__of(a), _M0FP39stillfail5rules2js8role__of(b)));
}
function _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto11sha256__hex(self, s) {
  return _M0FP39stillfail5rules2js15js__sha256__hex(self, s);
}
function _M0FP39stillfail5rules2js6to__js(v) {
  switch (v.$tag) {
    case 0: {
      return _M0FP39stillfail5rules2js8js__null();
    }
    case 1: {
      return _M0FP39stillfail5rules2js12js__of__bool(true);
    }
    case 2: {
      return _M0FP39stillfail5rules2js12js__of__bool(false);
    }
    case 3: {
      const _Number = v;
      const _n = _Number._0;
      return _M0FP39stillfail5rules2js11js__of__num(_n);
    }
    case 4: {
      const _String = v;
      const _s = _String._0;
      return _M0FP39stillfail5rules2js11js__of__str(_s);
    }
    case 5: {
      const _Array = v;
      const _xs = _Array._0;
      const a = _M0FP39stillfail5rules2js14js__new__array();
      const _bind = _xs.len;
      const _bind$2 = _xs.buf;
      let _tmp = 0;
      while (true) {
        const _ = _tmp;
        if (_ < _bind) {
          const x = _bind$2[_];
          _M0FP39stillfail5rules2js8js__push(a, _M0FP39stillfail5rules2js6to__js(x));
          _tmp = _ + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      return a;
    }
    default: {
      const _Object = v;
      const _m = _Object._0;
      const o = _M0FP39stillfail5rules2js15js__new__object();
      const _it = _M0MPB3Map5iter2GssE(_m);
      while (true) {
        const _bind$3 = _M0MPB5Iter24nextGssE(_it);
        if (_bind$3 === undefined) {
          break;
        } else {
          const _Some = _bind$3;
          const _x = _Some;
          const _k = _x._0;
          const _x$2 = _x._1;
          _M0FP39stillfail5rules2js7js__put(o, _k, _M0FP39stillfail5rules2js6to__js(_x$2));
          continue;
        }
      }
      return o;
    }
  }
}
function _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto10sig__valid(self, sig, hash, origins, rp_id, passkey) {
  const _tmp = _M0FP39stillfail5rules2js6to__js(sig);
  const _p = _M0MPC15array5Array20unsafe__make__uninitGUssEE(origins.len);
  const _p$2 = origins.len;
  const _p$3 = origins.buf;
  let _tmp$2 = 0;
  while (true) {
    const _p$4 = _tmp$2;
    if (_p$4 < _p$2) {
      const _p$5 = _p$3[_p$4];
      const _p$6 = new _M0DTPC14json4Json6String(_p$5);
      _p.buf[_p$4] = _p$6;
      _tmp$2 = _p$4 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$4 = _p;
  return _M0FP39stillfail5rules2js14js__sig__valid(self, _tmp, hash, _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json5Array(_p$4)), rp_id, passkey);
}
function _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto14valid__key__id(self, id) {
  return _M0FP39stillfail5rules2js18js__valid__key__id(self, id);
}
function _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto15endpoint__proof(self, ws, base, endpoint, proof) {
  return _M0FP39stillfail5rules2js19js__endpoint__proof(self, ws, base, endpoint, proof);
}
function _M0FP39stillfail5rules2js8opt__num(v) {
  return _M0FP39stillfail5rules2js8js__kind(v) === 2 ? new _M0DTPC16option6OptionGdE4Some(_M0FP39stillfail5rules2js7js__num(v)) : _M0DTPC16option6OptionGdE4None__;
}
function _M0FP39stillfail5rules2js8opt__str(v) {
  return _M0FP39stillfail5rules2js8js__kind(v) === 3 ? _M0FP39stillfail5rules2js7js__str(v) : undefined;
}
function _M0FP39stillfail5rules2js11state__jsonN5pairsS7321(xs) {
  const _p = _M0MPC15array5Array20unsafe__make__uninitGUssEE(xs.len);
  const _p$2 = xs.len;
  const _p$3 = xs.buf;
  let _tmp = 0;
  while (true) {
    const _p$4 = _tmp;
    if (_p$4 < _p$2) {
      const _p$5 = _p$3[_p$4];
      const _p$6 = _p$5._0;
      const _p$7 = new _M0TPB5ArrayGRPC14json4JsonE([new _M0DTPC14json4Json6String(_p$6), _p$5._1], 2);
      const _p$8 = new _M0DTPC14json4Json5Array(_p$7);
      _p.buf[_p$4] = _p$8;
      _tmp = _p$4 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$4 = _p;
  return new _M0DTPC14json4Json5Array(_p$4);
}
function _M0FP39stillfail5rules2js11state__json(s) {
  const _p = s.ws;
  const _tmp = { _0: "ws", _1: new _M0DTPC14json4Json6String(_p) };
  const _p$2 = s.seq;
  const _p$3 = undefined;
  const _tmp$2 = { _0: "seq", _1: new _M0DTPC14json4Json6Number(_p$2, _p$3) };
  const _p$4 = s.head;
  const _tmp$3 = { _0: "head", _1: new _M0DTPC14json4Json6String(_p$4) };
  const _p$5 = s.genesis;
  const _tmp$4 = { _0: "genesis", _1: new _M0DTPC14json4Json6String(_p$5) };
  const _p$6 = s.origins;
  const _p$7 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$6.len);
  const _p$8 = _p$6.len;
  const _p$9 = _p$6.buf;
  let _tmp$5 = 0;
  while (true) {
    const _p$10 = _tmp$5;
    if (_p$10 < _p$8) {
      const _p$11 = _p$9[_p$10];
      const _p$12 = new _M0DTPC14json4Json6String(_p$11);
      _p$7.buf[_p$10] = _p$12;
      _tmp$5 = _p$10 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$10 = _p$7;
  const _tmp$6 = { _0: "origins", _1: new _M0DTPC14json4Json5Array(_p$10) };
  const _p$11 = s.rp_id;
  const _tmp$7 = { _0: "rp_id", _1: new _M0DTPC14json4Json6String(_p$11) };
  const _tmp$8 = { _0: "cloud_keys", _1: s.cloud_keys };
  const _tmp$9 = { _0: "members", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS7321(_M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(s.members), (p) => {
    const _tmp$10 = p._0;
    const _p$12 = p._1.sub;
    const _tmp$11 = { _0: "sub", _1: new _M0DTPC14json4Json6String(_p$12) };
    const _p$13 = p._1.email;
    const _tmp$12 = { _0: "email", _1: new _M0DTPC14json4Json6String(_p$13) };
    const _p$14 = p._1.role;
    const _bind = [_tmp$11, _tmp$12, { _0: "role", _1: new _M0DTPC14json4Json6String(_p$14) }];
    const _p$15 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 3), undefined);
    return { _0: _tmp$10, _1: new _M0DTPC14json4Json6Object(_p$15) };
  }))) };
  const _tmp$10 = { _0: "devices", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS7321(_M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(s.devices), (p) => {
    const _tmp$11 = p._0;
    const d = p._1;
    const _p$12 = d.id;
    const _tmp$12 = { _0: "id", _1: new _M0DTPC14json4Json6String(_p$12) };
    const _p$13 = d.sub;
    const _tmp$13 = { _0: "sub", _1: new _M0DTPC14json4Json6String(_p$13) };
    const _p$14 = d.kind;
    const _tmp$14 = { _0: "kind", _1: new _M0DTPC14json4Json6String(_p$14) };
    const _p$15 = d.label;
    const _tmp$15 = { _0: "label", _1: new _M0DTPC14json4Json6String(_p$15) };
    const _p$16 = d.own;
    const _bind = [_tmp$12, _tmp$13, _tmp$14, _tmp$15, { _0: "own", _1: _p$16 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ }];
    const m = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 5), undefined);
    const _bind$2 = d.sign_key;
    if (_bind$2 === undefined) {
    } else {
      const _Some = _bind$2;
      const _k = _Some;
      _M0MPB3Map3setGsRPC14json4JsonE(m, "sign_key", new _M0DTPC14json4Json6String(_k));
    }
    const _bind$3 = d.endpoints;
    if (_bind$3 === undefined) {
    } else {
      const _Some = _bind$3;
      const _es = _Some;
      const _p$17 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_es.len);
      const _p$18 = _es.len;
      const _p$19 = _es.buf;
      let _tmp$16 = 0;
      while (true) {
        const _p$20 = _tmp$16;
        if (_p$20 < _p$18) {
          const _p$21 = _p$19[_p$20];
          const _p$22 = new _M0DTPC14json4Json6String(_p$21);
          _p$17.buf[_p$20] = _p$22;
          _tmp$16 = _p$20 + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      const _p$20 = _p$17;
      _M0MPB3Map3setGsRPC14json4JsonE(m, "endpoints", new _M0DTPC14json4Json5Array(_p$20));
    }
    const _bind$4 = d.exp;
    if (_bind$4.$tag === 1) {
      const _Some = _bind$4;
      const _x = _Some._0;
      const _p$17 = undefined;
      _M0MPB3Map3setGsRPC14json4JsonE(m, "exp", new _M0DTPC14json4Json6Number(_x, _p$17));
    }
    const _bind$5 = d.by;
    if (_bind$5 === undefined) {
    } else {
      const _Some = _bind$5;
      const _b = _Some;
      _M0MPB3Map3setGsRPC14json4JsonE(m, "by", new _M0DTPC14json4Json6String(_b));
    }
    return { _0: _tmp$11, _1: new _M0DTPC14json4Json6Object(m) };
  }))) };
  const _tmp$11 = { _0: "signKeys", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS7321(_M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(s.sign_keys), (p) => {
    const _tmp$12 = p._0;
    const _p$12 = p._1;
    const _p$13 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$12.len);
    const _p$14 = _p$12.len;
    const _p$15 = _p$12.buf;
    let _tmp$13 = 0;
    while (true) {
      const _p$16 = _tmp$13;
      if (_p$16 < _p$14) {
        const _p$17 = _p$15[_p$16];
        const _p$18 = new _M0DTPC14json4Json6String(_p$17);
        _p$13.buf[_p$16] = _p$18;
        _tmp$13 = _p$16 + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _p$16 = _p$13;
    return { _0: _tmp$12, _1: new _M0DTPC14json4Json5Array(_p$16) };
  }))) };
  const _tmp$12 = { _0: "passkeys", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS7321(_M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(s.passkeys), (p) => {
    const _tmp$13 = p._0;
    const _p$12 = p._1.id;
    const _tmp$14 = { _0: "id", _1: new _M0DTPC14json4Json6String(_p$12) };
    const _p$13 = p._1.sub;
    const _tmp$15 = { _0: "sub", _1: new _M0DTPC14json4Json6String(_p$13) };
    const _p$14 = p._1.key;
    const _tmp$16 = { _0: "key", _1: new _M0DTPC14json4Json6String(_p$14) };
    const _p$15 = p._1.label;
    const _tmp$17 = { _0: "label", _1: new _M0DTPC14json4Json6String(_p$15) };
    const _p$16 = p._1.own;
    const _bind = [_tmp$14, _tmp$15, _tmp$16, _tmp$17, { _0: "own", _1: _p$16 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ }];
    const _p$17 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 5), undefined);
    return { _0: _tmp$13, _1: new _M0DTPC14json4Json6Object(_p$17) };
  }))) };
  const _p$12 = _M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map4keysGsuE(s.signed), (_hole286) => new _M0DTPC14json4Json6String(_hole286)));
  const _tmp$13 = { _0: "signed", _1: new _M0DTPC14json4Json5Array(_p$12) };
  const _tmp$14 = { _0: "stations", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS7321(_M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(s.stations), (p) => {
    const _tmp$15 = p._0;
    const _p$13 = p._1.key;
    const _tmp$16 = { _0: "key", _1: new _M0DTPC14json4Json6String(_p$13) };
    const _p$14 = p._1.name;
    const _bind = [_tmp$16, { _0: "name", _1: new _M0DTPC14json4Json6String(_p$14) }];
    const _p$15 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 2), undefined);
    return { _0: _tmp$15, _1: new _M0DTPC14json4Json6Object(_p$15) };
  }))) };
  const _p$13 = _M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map4keysGsuE(s.gateways), (_hole289) => new _M0DTPC14json4Json6String(_hole289)));
  const _tmp$15 = { _0: "gateways", _1: new _M0DTPC14json4Json5Array(_p$13) };
  const _tmp$16 = { _0: "persons", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS7321(_M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map4iterGsRP39stillfail5rules4lock12PersonDeviceE(s.persons), (p) => {
    const _tmp$17 = p._0;
    const _p$14 = p._1;
    return { _0: _tmp$17, _1: new _M0DTPC14json4Json6String(_p$14) };
  }))) };
  const _p$14 = s.disabled;
  const _bind = [_tmp, _tmp$2, _tmp$3, _tmp$4, _tmp$6, _tmp$7, _tmp$8, _tmp$9, _tmp$10, _tmp$11, _tmp$12, _tmp$13, _tmp$14, _tmp$15, _tmp$16, { _0: "disabled", _1: _p$14 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ }];
  const _p$15 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 16), undefined);
  const out = new _M0DTPC14json4Json6Object(_p$15);
  const _bind$2 = s.moved;
  if (out.$tag === 6) {
    const _Object = out;
    const _m = _Object._0;
    if (_bind$2 === undefined) {
    } else {
      const _Some = _bind$2;
      const _root = _Some;
      _M0MPB3Map3setGsRPC14json4JsonE(_m, "moved", new _M0DTPC14json4Json6String(_root));
    }
  }
  return out;
}
function _M0FP39stillfail5rules2js11entries__of(v) {
  const out = new _M0TPB5ArrayGRPC14json4JsonE([], 0);
  const _bind = _M0FP39stillfail5rules2js7js__len(v);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      const _bind$2 = _M0FP39stillfail5rules2js8json__of(_M0FP39stillfail5rules2js6js__at(v, i));
      let _tmp$2;
      if (_bind$2.$tag === 1) {
        const _ok = _bind$2;
        _tmp$2 = _ok._0;
      } else {
        return _bind$2;
      }
      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(out, _tmp$2);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return new _M0DTPC16result6ResultGRPB5ArrayGRPC14json4JsonERP39stillfail5rules4form7InvalidE2Ok(out);
}
function _M0FP39stillfail5rules2js8fold__js(entries, now, crypto) {
  let out;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules2js11entries__of(entries);
      let _tmp;
      if (_bind.$tag === 1) {
        const _ok = _bind;
        _tmp = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      const _bind$2 = _M0FP39stillfail5rules4lock4fold(_tmp, _M0FP39stillfail5rules2js8opt__num(now), { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
      let s;
      if (_bind$2.$tag === 1) {
        const _ok = _bind$2;
        s = _ok._0;
      } else {
        const _err = _bind$2;
        _try_err = _err._0;
        break _L$2;
      }
      const _bind$3 = [{ _0: "state", _1: _M0FP39stillfail5rules2js11state__json(s) }];
      const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$3, 0, 1), undefined);
      out = new _M0DTPC14json4Json6Object(_p);
      break _L;
    }
    let why;
    _L$3: {
      _L$4: {
        switch (_try_err.$tag) {
          case 2: {
            const _Refused = _try_err;
            const _why = _Refused._0;
            why = _why;
            break _L$4;
          }
          case 1: {
            const _Refusal = _try_err;
            const _why$2 = _Refusal._0;
            why = _why$2;
            break _L$4;
          }
          case 0: {
            const _Invalid = _try_err;
            const _why$3 = _Invalid._0;
            const _bind = [{ _0: "error", _1: new _M0DTPC14json4Json6String(_why$3) }];
            const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
            out = new _M0DTPC14json4Json6Object(_p);
            break;
          }
          default: {
            const _p$2 = _M0FP15Error10to__string(_try_err);
            const _bind$2 = [{ _0: "error", _1: new _M0DTPC14json4Json6String(_p$2) }];
            const _p$3 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$2, 0, 1), undefined);
            out = new _M0DTPC14json4Json6Object(_p$3);
          }
        }
        break _L$3;
      }
      const _bind = [{ _0: "error", _1: new _M0DTPC14json4Json6String(why) }];
      const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
      out = new _M0DTPC14json4Json6Object(_p);
    }
  }
  return _M0FP39stillfail5rules2js6to__js(out);
}
function _M0FP39stillfail5rules2js9admit__js(entries, fold_now, queries, crypto) {
  let s;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules2js11entries__of(entries);
      let _tmp;
      if (_bind.$tag === 1) {
        const _ok = _bind;
        _tmp = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      const _bind$2 = _M0FP39stillfail5rules4lock4fold(_tmp, _M0FP39stillfail5rules2js8opt__num(fold_now), { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
      if (_bind$2.$tag === 1) {
        const _ok = _bind$2;
        s = _ok._0;
      } else {
        const _err = _bind$2;
        _try_err = _err._0;
        break _L$2;
      }
      break _L;
    }
    let why;
    _L$3: {
      switch (_try_err.$tag) {
        case 2: {
          const _Refused = _try_err;
          const _why = _Refused._0;
          why = _why;
          break _L$3;
        }
        case 1: {
          const _Refusal = _try_err;
          const _why$2 = _Refusal._0;
          why = _why$2;
          break _L$3;
        }
        case 0: {
          const _Invalid = _try_err;
          const _why$3 = _Invalid._0;
          const _bind = [{ _0: "error", _1: new _M0DTPC14json4Json6String(_why$3) }];
          const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
          return _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json6Object(_p));
        }
        default: {
          const _p$2 = _M0FP15Error10to__string(_try_err);
          const _bind$2 = [{ _0: "error", _1: new _M0DTPC14json4Json6String(_p$2) }];
          const _p$3 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$2, 0, 1), undefined);
          return _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json6Object(_p$3));
        }
      }
    }
    const _bind = [{ _0: "error", _1: new _M0DTPC14json4Json6String(why) }];
    const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
    return _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json6Object(_p));
  }
  const out = new _M0TPB5ArrayGRPC14json4JsonE([], 0);
  const _bind = _M0FP39stillfail5rules2js7js__len(queries);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      const q = _M0FP39stillfail5rules2js6js__at(queries, i);
      let answer;
      let _try_err$2;
      _L$2: {
        _L$3: {
          const _bind$2 = _M0FP39stillfail5rules4lock5admit(s, _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(q, "sub")), _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(q, "endpoint")), _M0FP39stillfail5rules2js8opt__str(_M0FP39stillfail5rules2js7js__get(q, "base")), _M0FP39stillfail5rules2js8opt__str(_M0FP39stillfail5rules2js7js__get(q, "proof")), _M0FP39stillfail5rules2js7js__num(_M0FP39stillfail5rules2js7js__get(q, "now")), { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
          let _bind$3;
          if (_bind$2.$tag === 1) {
            const _ok = _bind$2;
            _bind$3 = _ok._0;
          } else {
            const _err = _bind$2;
            _try_err$2 = _err._0;
            break _L$3;
          }
          const _d = _bind$3._0;
          const _role = _bind$3._1;
          const _p = _d.id;
          const _bind$4 = [{ _0: "device", _1: new _M0DTPC14json4Json6String(_p) }, { _0: "role", _1: new _M0DTPC14json4Json6String(_role) }];
          const _p$2 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$4, 0, 2), undefined);
          answer = new _M0DTPC14json4Json6Object(_p$2);
          break _L$2;
        }
        let why;
        _L$4: {
          if (_try_err$2.$tag === 1) {
            const _Refusal = _try_err$2;
            const _why = _Refusal._0;
            why = _why;
            break _L$4;
          } else {
            const _Refused = _try_err$2;
            const _why = _Refused._0;
            why = _why;
            break _L$4;
          }
        }
        const _bind$2 = [{ _0: "refusal", _1: new _M0DTPC14json4Json6String(why) }];
        const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$2, 0, 1), undefined);
        answer = new _M0DTPC14json4Json6Object(_p);
      }
      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(out, answer);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json5Array(out));
}
function _M0FP39stillfail5rules2js4held(s) {
  const o = _M0FP39stillfail5rules2js15js__new__object();
  _M0FP39stillfail5rules2js7js__put(o, "state", _M0FP39stillfail5rules2js6to__js(_M0FP39stillfail5rules2js11state__json(s)));
  _M0FP39stillfail5rules2js7js__put(o, "rules", _M0FP39stillfail5rules2js6handle(s));
  return o;
}
function _M0FP39stillfail5rules2js7refused(why) {
  const o = _M0FP39stillfail5rules2js15js__new__object();
  _M0FP39stillfail5rules2js7js__put(o, "error", _M0FP39stillfail5rules2js11js__of__str(why));
  return o;
}
function _M0FP39stillfail5rules2js11genesis__js(entry, crypto) {
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js8json__of(entry);
    let _tmp;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _tmp = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules4lock7genesis(_tmp, { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
    let _tmp$2;
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _tmp$2 = _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
    return _M0FP39stillfail5rules2js4held(_tmp$2);
  }
  let why;
  _L$2: {
    switch (_try_err.$tag) {
      case 2: {
        const _Refused = _try_err;
        const _why = _Refused._0;
        why = _why;
        break _L$2;
      }
      case 1: {
        const _Refusal = _try_err;
        const _why$2 = _Refusal._0;
        why = _why$2;
        break _L$2;
      }
      case 0: {
        const _Invalid = _try_err;
        const _why$3 = _Invalid._0;
        return _M0FP39stillfail5rules2js7refused(_why$3);
      }
      default: {
        return _M0FP39stillfail5rules2js7refused(_M0FP15Error10to__string(_try_err));
      }
    }
  }
  return _M0FP39stillfail5rules2js7refused(why);
}
function _M0FP39stillfail5rules2js9apply__js(prev, entry, now, crypto) {
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js8json__of(entry);
    let _tmp;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _tmp = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules4lock5apply(prev, _tmp, _M0FP39stillfail5rules2js8opt__num(now), { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
    let _tmp$2;
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _tmp$2 = _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
    return _M0FP39stillfail5rules2js4held(_tmp$2);
  }
  let why;
  _L$2: {
    switch (_try_err.$tag) {
      case 2: {
        const _Refused = _try_err;
        const _why = _Refused._0;
        why = _why;
        break _L$2;
      }
      case 1: {
        const _Refusal = _try_err;
        const _why$2 = _Refusal._0;
        why = _why$2;
        break _L$2;
      }
      case 0: {
        const _Invalid = _try_err;
        const _why$3 = _Invalid._0;
        return _M0FP39stillfail5rules2js7refused(_why$3);
      }
      default: {
        return _M0FP39stillfail5rules2js7refused(_M0FP15Error10to__string(_try_err));
      }
    }
  }
  return _M0FP39stillfail5rules2js7refused(why);
}
function _M0FP39stillfail5rules2js10signer__js(s, key, now) {
  const _bind = _M0FP39stillfail5rules4lock6signer(s, key, _M0FP39stillfail5rules2js8opt__num(now));
  if (_bind === undefined) {
    return _M0FP39stillfail5rules2js8js__null();
  } else {
    const _Some = _bind;
    const _w = _Some;
    const _p = _w.sub;
    const _tmp = { _0: "sub", _1: new _M0DTPC14json4Json6String(_p) };
    const _p$2 = _w.role;
    const _tmp$2 = { _0: "role", _1: new _M0DTPC14json4Json6String(_p$2) };
    const _p$3 = _w.passkey;
    const _tmp$3 = { _0: "passkey", _1: _p$3 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ };
    const _p$4 = _w.own;
    const _bind$2 = [_tmp, _tmp$2, _tmp$3, { _0: "own", _1: _p$4 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ }];
    const _p$5 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$2, 0, 4), undefined);
    return _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json6Object(_p$5));
  }
}
function _M0FP39stillfail5rules2js14admit__one__js(s, who, now, crypto) {
  let answer;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules4lock5admit(s, _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(who, "sub")), _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(who, "endpoint")), _M0FP39stillfail5rules2js8opt__str(_M0FP39stillfail5rules2js7js__get(who, "base")), _M0FP39stillfail5rules2js8opt__str(_M0FP39stillfail5rules2js7js__get(who, "proof")), now, { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
      let _bind$2;
      if (_bind.$tag === 1) {
        const _ok = _bind;
        _bind$2 = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      const _d = _bind$2._0;
      const _role = _bind$2._1;
      const _p = _d.id;
      const _bind$3 = [{ _0: "device", _1: new _M0DTPC14json4Json6String(_p) }, { _0: "role", _1: new _M0DTPC14json4Json6String(_role) }];
      const _p$2 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$3, 0, 2), undefined);
      answer = new _M0DTPC14json4Json6Object(_p$2);
      break _L;
    }
    let why;
    _L$3: {
      if (_try_err.$tag === 1) {
        const _Refusal = _try_err;
        const _why = _Refusal._0;
        why = _why;
        break _L$3;
      } else {
        const _Refused = _try_err;
        const _why = _Refused._0;
        why = _why;
        break _L$3;
      }
    }
    const _bind = [{ _0: "refusal", _1: new _M0DTPC14json4Json6String(why) }];
    const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
    answer = new _M0DTPC14json4Json6Object(_p);
  }
  return _M0FP39stillfail5rules2js6to__js(answer);
}
function _M0FP39stillfail5rules2js14fold__held__js(entries, now, crypto) {
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js11entries__of(entries);
    let _tmp;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _tmp = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules4lock4fold(_tmp, _M0FP39stillfail5rules2js8opt__num(now), { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
    let _tmp$2;
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _tmp$2 = _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
    return _M0FP39stillfail5rules2js4held(_tmp$2);
  }
  let why;
  _L$2: {
    switch (_try_err.$tag) {
      case 2: {
        const _Refused = _try_err;
        const _why = _Refused._0;
        why = _why;
        break _L$2;
      }
      case 1: {
        const _Refusal = _try_err;
        const _why$2 = _Refusal._0;
        why = _why$2;
        break _L$2;
      }
      case 0: {
        const _Invalid = _try_err;
        const _why$3 = _Invalid._0;
        return _M0FP39stillfail5rules2js7refused(_why$3);
      }
      default: {
        return _M0FP39stillfail5rules2js7refused(_M0FP15Error10to__string(_try_err));
      }
    }
  }
  return _M0FP39stillfail5rules2js7refused(why);
}
function _M0FP39stillfail5rules2js12person__jsonN6deviceS7490(d) {
  const _p = d.key;
  const _tmp = { _0: "key", _1: new _M0DTPC14json4Json6String(_p) };
  const _p$2 = d.id;
  const _tmp$2 = { _0: "id", _1: new _M0DTPC14json4Json6String(_p$2) };
  const _p$3 = d.label;
  const _bind = [_tmp, _tmp$2, { _0: "label", _1: new _M0DTPC14json4Json6String(_p$3) }];
  const _p$4 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 3), undefined);
  return new _M0DTPC14json4Json6Object(_p$4);
}
function _M0FP39stillfail5rules2js12person__json(p) {
  const _p = p.sub;
  const _tmp = { _0: "sub", _1: new _M0DTPC14json4Json6String(_p) };
  const _p$2 = p.genesis;
  const _tmp$2 = { _0: "genesis", _1: new _M0DTPC14json4Json6String(_p$2) };
  const _p$3 = p.head;
  const _tmp$3 = { _0: "head", _1: new _M0DTPC14json4Json6String(_p$3) };
  const _p$4 = p.seq;
  const _p$5 = undefined;
  const _tmp$4 = { _0: "seq", _1: new _M0DTPC14json4Json6Number(_p$4, _p$5) };
  const _p$6 = _M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map6valuesGsRP39stillfail5rules4lock12PersonDeviceE(p.devices), _M0FP39stillfail5rules2js12person__jsonN6deviceS7490));
  const _tmp$5 = { _0: "devices", _1: new _M0DTPC14json4Json5Array(_p$6) };
  const _p$7 = _M0MPB4Iter9to__arrayGUssEE(_M0MPB4Iter3mapGRP39stillfail5rules4lock12PersonDeviceRPC14json4JsonE(_M0MPB3Map6valuesGsRP39stillfail5rules4lock12PersonDeviceE(p.webs), (w) => {
    const _p$8 = w.id;
    const _tmp$6 = { _0: "id", _1: new _M0DTPC14json4Json6String(_p$8) };
    const _p$9 = w.label;
    const _tmp$7 = { _0: "label", _1: new _M0DTPC14json4Json6String(_p$9) };
    const _p$10 = w.at;
    const _p$11 = undefined;
    const _tmp$8 = { _0: "at", _1: new _M0DTPC14json4Json6Number(_p$10, _p$11) };
    const _p$12 = w.exp;
    const _p$13 = undefined;
    const _bind = [_tmp$6, _tmp$7, _tmp$8, { _0: "exp", _1: new _M0DTPC14json4Json6Number(_p$12, _p$13) }];
    const _p$14 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 4), undefined);
    return new _M0DTPC14json4Json6Object(_p$14);
  }));
  const _bind = [_tmp, _tmp$2, _tmp$3, _tmp$4, _tmp$5, { _0: "webs", _1: new _M0DTPC14json4Json5Array(_p$7) }];
  const _p$8 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 6), undefined);
  return new _M0DTPC14json4Json6Object(_p$8);
}
function _M0FP39stillfail5rules2js16person__fold__js(entries, sub, crypto) {
  let answer;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules2js11entries__of(entries);
      let _tmp;
      if (_bind.$tag === 1) {
        const _ok = _bind;
        _tmp = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      const _bind$2 = _M0FP39stillfail5rules4lock12fold__person(_tmp, sub, { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
      let _tmp$2;
      if (_bind$2.$tag === 1) {
        const _ok = _bind$2;
        _tmp$2 = _ok._0;
      } else {
        const _err = _bind$2;
        _try_err = _err._0;
        break _L$2;
      }
      answer = _M0FP39stillfail5rules2js12person__json(_tmp$2);
      break _L;
    }
    let why;
    _L$3: {
      _L$4: {
        switch (_try_err.$tag) {
          case 2: {
            const _Refused = _try_err;
            const _why = _Refused._0;
            why = _why;
            break _L$4;
          }
          case 1: {
            const _Refusal = _try_err;
            const _why$2 = _Refusal._0;
            why = _why$2;
            break _L$4;
          }
          case 0: {
            const _Invalid = _try_err;
            const _why$3 = _Invalid._0;
            const _bind = [{ _0: "error", _1: new _M0DTPC14json4Json6String(_why$3) }];
            const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
            answer = new _M0DTPC14json4Json6Object(_p);
            break;
          }
          default: {
            const _p$2 = _M0FP15Error10to__string(_try_err);
            const _bind$2 = [{ _0: "error", _1: new _M0DTPC14json4Json6String(_p$2) }];
            const _p$3 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$2, 0, 1), undefined);
            answer = new _M0DTPC14json4Json6Object(_p$3);
          }
        }
        break _L$3;
      }
      const _bind = [{ _0: "error", _1: new _M0DTPC14json4Json6String(why) }];
      const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
      answer = new _M0DTPC14json4Json6Object(_p);
    }
  }
  return _M0FP39stillfail5rules2js6to__js(answer);
}
function _M0FP39stillfail5rules2js17admit__person__js(s, who, entries, crypto) {
  let answer;
  let _try_err;
  _L: {
    _L$2: {
      const _tmp = _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(who, "sub"));
      const _tmp$2 = _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(who, "endpoint"));
      const _tmp$3 = _M0FP39stillfail5rules2js8opt__str(_M0FP39stillfail5rules2js7js__get(who, "base"));
      const _tmp$4 = _M0FP39stillfail5rules2js8opt__str(_M0FP39stillfail5rules2js7js__get(who, "proof"));
      const _bind = _M0FP39stillfail5rules2js11entries__of(entries);
      let _tmp$5;
      if (_bind.$tag === 1) {
        const _ok = _bind;
        _tmp$5 = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      const _bind$2 = _M0FP39stillfail5rules4lock13admit__person(s, _tmp, _tmp$2, _tmp$3, _tmp$4, _tmp$5, { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
      let _bind$3;
      if (_bind$2.$tag === 1) {
        const _ok = _bind$2;
        _bind$3 = _ok._0;
      } else {
        const _err = _bind$2;
        _try_err = _err._0;
        break _L$2;
      }
      const _d = _bind$3._0;
      const _role = _bind$3._1;
      const _person = _bind$3._2;
      const _p = _d.id;
      const _bind$4 = [{ _0: "device", _1: new _M0DTPC14json4Json6String(_p) }, { _0: "role", _1: new _M0DTPC14json4Json6String(_role) }, { _0: "person", _1: _M0FP39stillfail5rules2js12person__json(_person) }];
      const _p$2 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$4, 0, 3), undefined);
      answer = new _M0DTPC14json4Json6Object(_p$2);
      break _L;
    }
    let why;
    _L$3: {
      _L$4: {
        switch (_try_err.$tag) {
          case 1: {
            const _Refusal = _try_err;
            const _why = _Refusal._0;
            why = _why;
            break _L$4;
          }
          case 2: {
            const _Refused = _try_err;
            const _why$2 = _Refused._0;
            why = _why$2;
            break _L$4;
          }
          case 0: {
            const _Invalid = _try_err;
            const _why$3 = _Invalid._0;
            const _bind = [{ _0: "refusal", _1: new _M0DTPC14json4Json6String(_why$3) }];
            const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
            answer = new _M0DTPC14json4Json6Object(_p);
            break;
          }
          default: {
            const _p$2 = _M0FP15Error10to__string(_try_err);
            const _bind$2 = [{ _0: "refusal", _1: new _M0DTPC14json4Json6String(_p$2) }];
            const _p$3 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$2, 0, 1), undefined);
            answer = new _M0DTPC14json4Json6Object(_p$3);
          }
        }
        break _L$3;
      }
      const _bind = [{ _0: "refusal", _1: new _M0DTPC14json4Json6String(why) }];
      const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 1), undefined);
      answer = new _M0DTPC14json4Json6Object(_p);
    }
  }
  return _M0FP39stillfail5rules2js6to__js(answer);
}
function _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules5vault6Crypto18record__sig__valid(self, sig, tag, text) {
  return _M0FP39stillfail5rules2js22js__record__sig__valid(self, _M0FP39stillfail5rules2js6to__js(sig), tag, text);
}
function _M0FP39stillfail5rules2js10lock__view(lock) {
  const _bind = [];
  const members = _M0MPB3Map3MapGsuE(new _M0TPB9ArrayViewGUsuEE(_bind, 0, 0), undefined);
  const ms = _M0FP39stillfail5rules2js11js__entries(_M0FP39stillfail5rules2js7js__get(lock, "members"));
  const _bind$2 = _M0FP39stillfail5rules2js7js__len(ms);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind$2) {
      _M0MPB3Map3setGsuE(members, _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js6js__at(_M0FP39stillfail5rules2js6js__at(ms, i), 0)), undefined);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _bind$3 = [];
  const devices = _M0MPB3Map3MapGsRP39stillfail5rules5vault6DeviceE(new _M0TPB9ArrayViewGUsRP39stillfail5rules5vault6DeviceEE(_bind$3, 0, 0), undefined);
  const ds = _M0FP39stillfail5rules2js11js__entries(_M0FP39stillfail5rules2js7js__get(lock, "devices"));
  const _bind$4 = _M0FP39stillfail5rules2js7js__len(ds);
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp$2;
    if (i < _bind$4) {
      const d = _M0FP39stillfail5rules2js6js__at(_M0FP39stillfail5rules2js6js__at(ds, i), 1);
      _M0MPB3Map3setGsRP39stillfail5rules5vault6DeviceE(devices, _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js6js__at(_M0FP39stillfail5rules2js6js__at(ds, i), 0)), new _M0TP39stillfail5rules5vault6Device(_M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(d, "sub")), _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(d, "kind")), _M0FP39stillfail5rules2js8opt__str(_M0FP39stillfail5rules2js7js__get(d, "sign_key")), _M0FP39stillfail5rules2js8js__kind(_M0FP39stillfail5rules2js7js__get(d, "own")) === 1 && _M0FP39stillfail5rules2js8js__bool(_M0FP39stillfail5rules2js7js__get(d, "own"))));
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _bind$5 = [];
  const sign_keys = _M0MPB3Map3MapGsRPB5ArrayGsEE(new _M0TPB9ArrayViewGUsRPB5ArrayGsEEE(_bind$5, 0, 0), undefined);
  const ks = _M0FP39stillfail5rules2js11js__entries(_M0FP39stillfail5rules2js7js__get(lock, "signKeys"));
  const _bind$6 = _M0FP39stillfail5rules2js7js__len(ks);
  let _tmp$3 = 0;
  while (true) {
    const i = _tmp$3;
    if (i < _bind$6) {
      const had = _M0FP39stillfail5rules2js6js__at(_M0FP39stillfail5rules2js6js__at(ks, i), 1);
      const _tmp$4 = _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js6js__at(_M0FP39stillfail5rules2js6js__at(ks, i), 0));
      const _p = _M0FP39stillfail5rules2js7js__len(had);
      let _tmp$5;
      if (_p <= 0) {
        _tmp$5 = new _M0TPB5ArrayGsE([], 0);
      } else {
        const _p$2 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p);
        let _tmp$6 = 0;
        while (true) {
          const _p$3 = _tmp$6;
          if (_p$3 < _p) {
            const _p$4 = _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js6js__at(had, _p$3));
            _p$2.buf[_p$3] = _p$4;
            _tmp$6 = _p$3 + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        _tmp$5 = _p$2;
      }
      _M0MPB3Map3setGsRPB5ArrayGsEE(sign_keys, _tmp$4, _tmp$5);
      _tmp$3 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return new _M0TP39stillfail5rules5vault8LockView(_M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(lock, "ws")), members, devices, sign_keys);
}
function _M0FP39stillfail5rules2js14record_2einner(v, null_none) {
  if (_M0FP39stillfail5rules2js8js__kind(v) === 6 || null_none && _M0FP39stillfail5rules2js8js__kind(v) === 0) {
    return undefined;
  }
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js8json__of(v);
    if (_bind.$tag === 1) {
      const _ok = _bind;
      return _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
  }
  return undefined;
}
function _M0FP39stillfail5rules2js7why__js(why) {
  if (why === undefined) {
    return _M0FP39stillfail5rules2js8js__null();
  } else {
    const _Some = why;
    const _w = _Some;
    return _M0FP39stillfail5rules2js11js__of__str(_w);
  }
}
function _M0FP39stillfail5rules2js12cert__ok__js(lock, cert, ever, crypto) {
  return _M0FP39stillfail5rules2js7why__js(_M0FP39stillfail5rules5vault8cert__ok(_M0FP39stillfail5rules2js10lock__view(lock), _M0FP39stillfail5rules2js14record_2einner(cert, false), ever, { self: crypto, method_table: _M0FP078stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2fvault_2eCrypto }));
}
function _M0FP39stillfail5rules2js13vault__ok__js(lock, prev, next, copy, crypto) {
  return _M0FP39stillfail5rules2js7why__js(_M0FP39stillfail5rules5vault9vault__ok(_M0FP39stillfail5rules2js10lock__view(lock), _M0FP39stillfail5rules2js14record_2einner(prev, true), _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules2js14record_2einner(next, false), _M0DTPC14json4Json4Null__), copy, { self: crypto, method_table: _M0FP078stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2fvault_2eCrypto }));
}
function _M0FP39stillfail5rules2js12item__ok__js(lock, vault, prev, next, copy, crypto) {
  return _M0FP39stillfail5rules2js7why__js(_M0FP39stillfail5rules5vault8item__ok(_M0FP39stillfail5rules2js10lock__view(lock), _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules2js14record_2einner(vault, false), _M0DTPC14json4Json4Null__), _M0FP39stillfail5rules2js14record_2einner(prev, true), _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(_M0FP39stillfail5rules2js14record_2einner(next, false), _M0DTPC14json4Json4Null__), copy, { self: crypto, method_table: _M0FP078stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2fvault_2eCrypto }));
}
function _M0FP39stillfail5rules2js24browser__listing__ok__js(l) {
  const ms = _M0FP39stillfail5rules2js7js__get(l, "modes");
  const hs = _M0FP39stillfail5rules2js7js__get(l, "hosts");
  const _tmp = _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(l, "kind"));
  const _p = _M0FP39stillfail5rules2js7js__len(ms);
  let _tmp$2;
  if (_p <= 0) {
    _tmp$2 = new _M0TPB5ArrayGsE([], 0);
  } else {
    const _p$2 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p);
    let _tmp$3 = 0;
    while (true) {
      const _p$3 = _tmp$3;
      if (_p$3 < _p) {
        const _p$4 = _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js6js__at(ms, _p$3));
        _p$2.buf[_p$3] = _p$4;
        _tmp$3 = _p$3 + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    _tmp$2 = _p$2;
  }
  const _tmp$3 = _tmp$2;
  const _p$2 = _M0FP39stillfail5rules2js7js__len(hs);
  let _tmp$4;
  if (_p$2 <= 0) {
    _tmp$4 = new _M0TPB5ArrayGsE([], 0);
  } else {
    const _p$3 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$2);
    let _tmp$5 = 0;
    while (true) {
      const _p$4 = _tmp$5;
      if (_p$4 < _p$2) {
        const _p$5 = _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js6js__at(hs, _p$4));
        _p$3.buf[_p$4] = _p$5;
        _tmp$5 = _p$4 + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    _tmp$4 = _p$3;
  }
  return _M0FP39stillfail5rules2js7why__js(_M0FP39stillfail5rules5vault20browser__listing__ok(_tmp, _tmp$3, _tmp$4));
}
function _M0FP39stillfail5rules2js14signer__of__js(lock, key) {
  const _bind = _M0FP39stillfail5rules5vault10signer__of(_M0FP39stillfail5rules2js10lock__view(lock), key);
  if (_bind === undefined) {
    return _M0FP39stillfail5rules2js8js__null();
  } else {
    const _Some = _bind;
    const _x = _Some;
    const _sub = _x._0;
    const _device = _x._1;
    const _bind$2 = [{ _0: "sub", _1: new _M0DTPC14json4Json6String(_sub) }, { _0: "device", _1: new _M0DTPC14json4Json6String(_device) }];
    const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$2, 0, 2), undefined);
    return _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json6Object(_p));
  }
}
function _M0FP39stillfail5rules2js14supersedes__ofN1nS7598(v, k) {
  if (v.$tag === 6) {
    const _Object = v;
    const _m = _Object._0;
    const _bind = _M0MPB3Map3getGsRPC14json4JsonE(_m, k);
    if (_bind === undefined) {
      return 0n;
    } else {
      const _Some = _bind;
      const _x = _Some;
      if (_x.$tag === 3) {
        const _Number = _x;
        const _x$2 = _Number._0;
        return $i64_trunc_f64(_x$2);
      } else {
        return 0n;
      }
    }
  } else {
    return 0n;
  }
}
function _M0FP39stillfail5rules2js14supersedes__ofN7deletedS7599(v) {
  if (v.$tag === 6) {
    const _Object = v;
    const _m = _Object._0;
    const _bind = _M0MPB3Map3getGsRPC14json4JsonE(_m, "deleted");
    if (_bind === undefined) {
      return false;
    } else {
      const _Some = _bind;
      const _x = _Some;
      if (_x.$tag === 1) {
        return true;
      } else {
        return false;
      }
    }
  } else {
    return false;
  }
}
function _M0FP39stillfail5rules2js14supersedes__of(a, b, number) {
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js8json__of(a);
    let a$2;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      a$2 = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules2js8json__of(b);
    let b$2;
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      b$2 = _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
    let text;
    let _try_err$2;
    _L$2: {
      _L$3: {
        const _bind$3 = _M0FP39stillfail5rules4form9canonical(a$2);
        let _tmp;
        if (_bind$3.$tag === 1) {
          const _ok = _bind$3;
          _tmp = _ok._0;
        } else {
          const _err = _bind$3;
          _try_err$2 = _err._0;
          break _L$3;
        }
        const _tmp$2 = _tmp;
        const _bind$4 = _M0FP39stillfail5rules4form9canonical(b$2);
        let _tmp$3;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          _tmp$3 = _ok._0;
        } else {
          const _err = _bind$4;
          _try_err$2 = _err._0;
          break _L$3;
        }
        text = _M0IPC16string6StringPB7Compare7compare(_tmp$2, _tmp$3);
        break _L$2;
      }
      return false;
    }
    return _M0FP39stillfail5rules7history10supersedes(_M0FP39stillfail5rules2js14supersedes__ofN1nS7598(a$2, number), _M0FP39stillfail5rules2js14supersedes__ofN7deletedS7599(a$2), _M0FP39stillfail5rules2js14supersedes__ofN1nS7598(a$2, "epoch"), _M0FP39stillfail5rules2js14supersedes__ofN1nS7598(b$2, number), _M0FP39stillfail5rules2js14supersedes__ofN7deletedS7599(b$2), _M0FP39stillfail5rules2js14supersedes__ofN1nS7598(b$2, "epoch"), text);
  }
  return false;
}
function _M0FP39stillfail5rules2js21vault__supersedes__js(a, b) {
  return _M0FP39stillfail5rules2js14supersedes__of(a, b, "seq");
}
function _M0FP39stillfail5rules2js20item__supersedes__js(a, b) {
  return _M0FP39stillfail5rules2js14supersedes__of(a, b, "version");
}
function _M0FP39stillfail5rules2js11tie__of__js(parent, key, crypto) {
  const _p = { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto };
  return _p.method_table.method_0(_p.self, `${parent}\u0000${key}`);
}
function _M0FP39stillfail5rules2js10step__name(s) {
  switch (s) {
    case 0: {
      return "weight";
    }
    case 1: {
      return "removal";
    }
    case 2: {
      return "tie";
    }
    default: {
      return "hash";
    }
  }
}
function _M0FP39stillfail5rules2js16fork__before__jsN1wS7633(v) {
  return _M0MPC16double6Double7to__int(_M0FP39stillfail5rules2js7js__num(_M0FP39stillfail5rules2js7js__get(v, "weight")));
}
function _M0FP39stillfail5rules2js16fork__before__jsN1rS7634(v) {
  return _M0FP39stillfail5rules2js8js__kind(_M0FP39stillfail5rules2js7js__get(v, "removal")) === 1 && _M0FP39stillfail5rules2js8js__bool(_M0FP39stillfail5rules2js7js__get(v, "removal"));
}
function _M0FP39stillfail5rules2js16fork__before__jsN1sS7635(v, k) {
  return _M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(v, k));
}
function _M0FP39stillfail5rules2js16fork__before__js(a, b) {
  const _bind = _M0FP39stillfail5rules4lock6before(_M0FP39stillfail5rules2js16fork__before__jsN1wS7633(a), _M0FP39stillfail5rules2js16fork__before__jsN1rS7634(a), _M0FP39stillfail5rules2js16fork__before__jsN1sS7635(a, "tie"), _M0FP39stillfail5rules2js16fork__before__jsN1sS7635(a, "hash"), _M0FP39stillfail5rules2js16fork__before__jsN1wS7633(b), _M0FP39stillfail5rules2js16fork__before__jsN1rS7634(b), _M0FP39stillfail5rules2js16fork__before__jsN1sS7635(b, "tie"), _M0FP39stillfail5rules2js16fork__before__jsN1sS7635(b, "hash"));
  if (_bind === undefined) {
    return _M0FP39stillfail5rules2js8js__null();
  } else {
    const _Some = _bind;
    const _step = _Some;
    return _M0FP39stillfail5rules2js11js__of__str(_M0FP39stillfail5rules2js10step__name(_step));
  }
}
function _M0FP39stillfail5rules2js9chain__js(entries, ch) {
  const es = _M0FP39stillfail5rules2js14js__new__array();
  const _bind = ch.at;
  const _bind$2 = _bind.len;
  const _bind$3 = _bind.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind$2) {
      const i = _bind$3[_];
      _M0FP39stillfail5rules2js8js__push(es, _M0FP39stillfail5rules2js6js__at(entries, i));
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p = ch.off;
  const _p$2 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p.len);
  const _p$3 = _p.len;
  const _p$4 = _p.buf;
  let _tmp$2 = 0;
  while (true) {
    const _p$5 = _tmp$2;
    if (_p$5 < _p$3) {
      const _p$6 = _p$4[_p$5];
      const _p$7 = _p$6._0 + 0;
      const _p$8 = undefined;
      const _p$9 = [{ _0: "at", _1: new _M0DTPC14json4Json6Number(_p$7, _p$8) }];
      const _p$10 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_p$9, 0, 1), undefined);
      const _p$11 = _p$6._1;
      switch (_p$11.$tag) {
        case 0: {
          const _p$12 = _p$11;
          const _p$13 = _p$12._0;
          const _p$14 = "refused";
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "why", new _M0DTPC14json4Json6String(_p$14));
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "refusal", new _M0DTPC14json4Json6String(_p$13));
          break;
        }
        case 1: {
          const _p$15 = "no parent";
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "why", new _M0DTPC14json4Json6String(_p$15));
          break;
        }
        case 2: {
          const _p$16 = _p$11;
          const _p$17 = _p$16._0;
          const _p$18 = _p$16._1;
          const _p$19 = "beaten";
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "why", new _M0DTPC14json4Json6String(_p$19));
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "winner", new _M0DTPC14json4Json6String(_p$17));
          const _p$20 = _M0FP39stillfail5rules2js10step__name(_p$18);
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "step", new _M0DTPC14json4Json6String(_p$20));
          break;
        }
        case 3: {
          const _p$21 = _p$11;
          const _p$22 = _p$21._0;
          const _p$23 = "below";
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "why", new _M0DTPC14json4Json6String(_p$23));
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "under", new _M0DTPC14json4Json6String(_p$22));
          break;
        }
        default: {
          const _p$24 = "again";
          _M0MPB3Map3setGsRPC14json4JsonE(_p$10, "why", new _M0DTPC14json4Json6String(_p$24));
        }
      }
      const _p$25 = new _M0DTPC14json4Json6Object(_p$10);
      _p$2.buf[_p$5] = _p$25;
      _tmp$2 = _p$5 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const off = _p$2;
  const o = _M0FP39stillfail5rules2js15js__new__object();
  _M0FP39stillfail5rules2js7js__put(o, "entries", es);
  const _p$5 = ch.at;
  const _p$6 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$5.len);
  const _p$7 = _p$5.len;
  const _p$8 = _p$5.buf;
  let _tmp$3 = 0;
  while (true) {
    const _p$9 = _tmp$3;
    if (_p$9 < _p$7) {
      const _p$10 = _p$8[_p$9];
      const _p$11 = _p$10 + 0;
      const _p$12 = undefined;
      const _p$13 = new _M0DTPC14json4Json6Number(_p$11, _p$12);
      _p$6.buf[_p$9] = _p$13;
      _tmp$3 = _p$9 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$9 = _p$6;
  _M0FP39stillfail5rules2js7js__put(o, "at", _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json5Array(_p$9)));
  const _p$10 = ch.hashes;
  const _p$11 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$10.len);
  const _p$12 = _p$10.len;
  const _p$13 = _p$10.buf;
  let _tmp$4 = 0;
  while (true) {
    const _p$14 = _tmp$4;
    if (_p$14 < _p$12) {
      const _p$15 = _p$13[_p$14];
      const _p$16 = new _M0DTPC14json4Json6String(_p$15);
      _p$11.buf[_p$14] = _p$16;
      _tmp$4 = _p$14 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$14 = _p$11;
  _M0FP39stillfail5rules2js7js__put(o, "hashes", _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json5Array(_p$14)));
  _M0FP39stillfail5rules2js7js__put(o, "off", _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json5Array(off)));
  return o;
}
function _M0FP39stillfail5rules2js15lock__chain__js(entries, genesis, votes, now, crypto) {
  const v = votes === "flat" ? 0 : 1;
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js11entries__of(entries);
    let _tmp;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _tmp = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules4lock11lock__chain(_tmp, genesis, v, _M0FP39stillfail5rules2js8opt__num(now), { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
    let _tmp$2;
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _tmp$2 = _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
    return _M0FP39stillfail5rules2js9chain__js(entries, _tmp$2);
  }
  let why;
  _L$2: {
    switch (_try_err.$tag) {
      case 2: {
        const _Refused = _try_err;
        const _why = _Refused._0;
        why = _why;
        break _L$2;
      }
      case 1: {
        const _Refusal = _try_err;
        const _why$2 = _Refusal._0;
        why = _why$2;
        break _L$2;
      }
      case 0: {
        const _Invalid = _try_err;
        const _why$3 = _Invalid._0;
        return _M0FP39stillfail5rules2js7refused(_why$3);
      }
      default: {
        return _M0FP39stillfail5rules2js7refused(_M0FP15Error10to__string(_try_err));
      }
    }
  }
  return _M0FP39stillfail5rules2js7refused(why);
}
function _M0FP39stillfail5rules2js17person__chain__js(entries, genesis, crypto) {
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js11entries__of(entries);
    let _tmp;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _tmp = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules4lock13person__chain(_tmp, genesis, { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
    let _tmp$2;
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _tmp$2 = _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
    return _M0FP39stillfail5rules2js9chain__js(entries, _tmp$2);
  }
  let why;
  _L$2: {
    switch (_try_err.$tag) {
      case 2: {
        const _Refused = _try_err;
        const _why = _Refused._0;
        why = _why;
        break _L$2;
      }
      case 1: {
        const _Refusal = _try_err;
        const _why$2 = _Refusal._0;
        why = _why$2;
        break _L$2;
      }
      case 0: {
        const _Invalid = _try_err;
        const _why$3 = _Invalid._0;
        return _M0FP39stillfail5rules2js7refused(_why$3);
      }
      default: {
        return _M0FP39stillfail5rules2js7refused(_M0FP15Error10to__string(_try_err));
      }
    }
  }
  return _M0FP39stillfail5rules2js7refused(why);
}
function _M0FP39stillfail5rules2js9opt__json(v) {
  if (v === undefined) {
    return _M0DTPC14json4Json4Null__;
  } else {
    const _Some = v;
    const _s = _Some;
    return new _M0DTPC14json4Json6String(_s);
  }
}
function _M0FP39stillfail5rules2js10bodies__of(v) {
  const out = new _M0TPB5ArrayGRPC14json4JsonE([], 0);
  const _bind = _M0FP39stillfail5rules2js7js__len(v);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      let _bind$2;
      let _try_err;
      _L: {
        _L$2: {
          const _bind$3 = _M0FP39stillfail5rules2js8json__of(_M0FP39stillfail5rules2js6js__at(v, i));
          let _tmp$2;
          if (_bind$3.$tag === 1) {
            const _ok = _bind$3;
            _tmp$2 = _ok._0;
          } else {
            const _err = _bind$3;
            _try_err = _err._0;
            break _L$2;
          }
          _bind$2 = new _M0DTPB6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE2Ok(_tmp$2);
          break _L;
        }
        _bind$2 = new _M0DTPB6ResultGRPC14json4JsonRP39stillfail5rules4form7InvalidE3Err(_try_err);
      }
      if (_bind$2.$tag === 1) {
        const _Ok = _bind$2;
        const _b = _Ok._0;
        _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(out, _b);
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0FP39stillfail5rules2js10chains__of(chains) {
  const cs = new _M0TPB5ArrayGRPB5ArrayGRPC14json4JsonEE([], 0);
  const _bind = _M0FP39stillfail5rules2js7js__len(chains);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      const _bind$2 = _M0FP39stillfail5rules2js11entries__of(_M0FP39stillfail5rules2js6js__at(chains, i));
      let _tmp$2;
      if (_bind$2.$tag === 1) {
        const _ok = _bind$2;
        _tmp$2 = _ok._0;
      } else {
        return _bind$2;
      }
      _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(cs, _tmp$2);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return new _M0DTPC16result6ResultGRPB5ArrayGRPB5ArrayGRPC14json4JsonEERP39stillfail5rules4form7InvalidE2Ok(cs);
}
function _M0FP39stillfail5rules2js10roster__jsN1sS7716(_hole38) {
  return new _M0DTPC14json4Json6String(_hole38);
}
function _M0FP39stillfail5rules2js10roster__js(ws, root, chains, bodies, crypto) {
  let cs;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules2js10chains__of(chains);
      if (_bind.$tag === 1) {
        const _ok = _bind;
        cs = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      break _L;
    }
    const _Invalid = _try_err;
    const _why = _Invalid._0;
    return _M0FP39stillfail5rules2js7refused(_why);
  }
  const _p = _M0FP39stillfail5rules2js10bodies__of(bodies);
  const _p$2 = { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto };
  const r = _M0FP39stillfail5rules4lock10roster__of(ws, root, cs, _p, _p$2)._0;
  const _p$3 = r.rooted;
  const _tmp = { _0: "rooted", _1: _p$3 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ };
  const _p$4 = r.members;
  const _p$5 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$4.len);
  const _p$6 = _p$4.len;
  const _p$7 = _p$4.buf;
  let _tmp$2 = 0;
  while (true) {
    const _p$8 = _tmp$2;
    if (_p$8 < _p$6) {
      const _p$9 = _p$7[_p$8];
      const _tmp$3 = { _0: "sub", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$9.sub) };
      const _tmp$4 = { _0: "role", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$9.role) };
      const _tmp$5 = { _0: "lock", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$9.lock) };
      const _tmp$6 = { _0: "admit", _1: _M0FP39stillfail5rules2js9opt__json(_p$9.admit) };
      const _p$10 = _p$9.keys;
      let _tmp$7;
      if (_p$10 === undefined) {
        _tmp$7 = _M0DTPC14json4Json4Null__;
      } else {
        const _p$11 = _p$10;
        const _p$12 = _p$11;
        const _p$13 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$12.len);
        const _p$14 = _p$12.len;
        const _p$15 = _p$12.buf;
        let _tmp$8 = 0;
        while (true) {
          const _p$16 = _tmp$8;
          if (_p$16 < _p$14) {
            const _p$17 = _p$15[_p$16];
            const _p$18 = _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$17);
            _p$13.buf[_p$16] = _p$18;
            _tmp$8 = _p$16 + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        const _p$16 = _p$13;
        _tmp$7 = new _M0DTPC14json4Json5Array(_p$16);
      }
      const _p$11 = [_tmp$3, _tmp$4, _tmp$5, _tmp$6, { _0: "keys", _1: _tmp$7 }];
      const _p$12 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_p$11, 0, 5), undefined);
      const _p$13 = new _M0DTPC14json4Json6Object(_p$12);
      _p$5.buf[_p$8] = _p$13;
      _tmp$2 = _p$8 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$8 = _p$5;
  const _tmp$3 = { _0: "members", _1: new _M0DTPC14json4Json5Array(_p$8) };
  const _p$9 = r.stations;
  const _p$10 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$9.len);
  const _p$11 = _p$9.len;
  const _p$12 = _p$9.buf;
  let _tmp$4 = 0;
  while (true) {
    const _p$13 = _tmp$4;
    if (_p$13 < _p$11) {
      const _p$14 = _p$12[_p$13];
      const _p$15 = _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$14);
      _p$10.buf[_p$13] = _p$15;
      _tmp$4 = _p$13 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$13 = _p$10;
  const _tmp$5 = { _0: "stations", _1: new _M0DTPC14json4Json5Array(_p$13) };
  const _p$14 = r.pairs;
  const _p$15 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$14.len);
  const _p$16 = _p$14.len;
  const _p$17 = _p$14.buf;
  let _tmp$6 = 0;
  while (true) {
    const _p$18 = _tmp$6;
    if (_p$18 < _p$16) {
      const _p$19 = _p$17[_p$18];
      const _p$20 = [{ _0: "sub", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$19._0) }, { _0: "lock", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$19._1) }, { _0: "role", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$19._2) }];
      const _p$21 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_p$20, 0, 3), undefined);
      const _p$22 = new _M0DTPC14json4Json6Object(_p$21);
      _p$15.buf[_p$18] = _p$22;
      _tmp$6 = _p$18 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$18 = _p$15;
  const _tmp$7 = { _0: "pairs", _1: new _M0DTPC14json4Json5Array(_p$18) };
  const _p$19 = r.undecided;
  const _p$20 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$19.len);
  const _p$21 = _p$19.len;
  const _p$22 = _p$19.buf;
  let _tmp$8 = 0;
  while (true) {
    const _p$23 = _tmp$8;
    if (_p$23 < _p$21) {
      const _p$24 = _p$22[_p$23];
      const _p$25 = [{ _0: "sub", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$24._0) }, { _0: "lock", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$24._1) }];
      const _p$26 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_p$25, 0, 2), undefined);
      const _p$27 = new _M0DTPC14json4Json6Object(_p$26);
      _p$20.buf[_p$23] = _p$27;
      _tmp$8 = _p$23 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$23 = _p$20;
  const _tmp$9 = { _0: "undecided", _1: new _M0DTPC14json4Json5Array(_p$23) };
  const _p$24 = r.cancelled;
  const _p$25 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$24.len);
  const _p$26 = _p$24.len;
  const _p$27 = _p$24.buf;
  let _tmp$10 = 0;
  while (true) {
    const _p$28 = _tmp$10;
    if (_p$28 < _p$26) {
      const _p$29 = _p$27[_p$28];
      const _p$30 = _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$29);
      _p$25.buf[_p$28] = _p$30;
      _tmp$10 = _p$28 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$28 = _p$25;
  const _tmp$11 = { _0: "cancelled", _1: new _M0DTPC14json4Json5Array(_p$28) };
  const _p$29 = r.statements;
  const _p$30 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$29.len);
  const _p$31 = _p$29.len;
  const _p$32 = _p$29.buf;
  let _tmp$12 = 0;
  while (true) {
    const _p$33 = _tmp$12;
    if (_p$33 < _p$31) {
      const _p$34 = _p$32[_p$33];
      const _p$35 = [{ _0: "hash", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$34.hash) }, { _0: "kind", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$34.kind) }, { _0: "log", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$34.log) }, { _0: "by", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$34.by) }, { _0: "label", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$34.label) }, { _0: "why", _1: _M0FP39stillfail5rules2js9opt__json(_p$34.why) }, { _0: "decided", _1: _M0FP39stillfail5rules2js9opt__json(_p$34.decided) }];
      const _p$36 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_p$35, 0, 7), undefined);
      const _p$37 = new _M0DTPC14json4Json6Object(_p$36);
      _p$30.buf[_p$33] = _p$37;
      _tmp$12 = _p$33 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$33 = _p$30;
  const _tmp$13 = { _0: "statements", _1: new _M0DTPC14json4Json5Array(_p$33) };
  const _p$34 = r.labels;
  const _p$35 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$34.len);
  const _p$36 = _p$34.len;
  const _p$37 = _p$34.buf;
  let _tmp$14 = 0;
  while (true) {
    const _p$38 = _tmp$14;
    if (_p$38 < _p$36) {
      const _p$39 = _p$37[_p$38];
      const _p$40 = new _M0TPB5ArrayGRPC14json4JsonE([_M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$39._0), _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$39._1)], 2);
      const _p$41 = new _M0DTPC14json4Json5Array(_p$40);
      _p$35.buf[_p$38] = _p$41;
      _tmp$14 = _p$38 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$38 = _p$35;
  const _tmp$15 = { _0: "labels", _1: new _M0DTPC14json4Json5Array(_p$38) };
  const _p$39 = r.refused;
  const _p$40 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$39.len);
  const _p$41 = _p$39.len;
  const _p$42 = _p$39.buf;
  let _tmp$16 = 0;
  while (true) {
    const _p$43 = _tmp$16;
    if (_p$43 < _p$41) {
      const _p$44 = _p$42[_p$43];
      const _p$45 = [{ _0: "genesis", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$44._0) }, { _0: "why", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$44._1) }];
      const _p$46 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_p$45, 0, 2), undefined);
      const _p$47 = new _M0DTPC14json4Json6Object(_p$46);
      _p$40.buf[_p$43] = _p$47;
      _tmp$16 = _p$43 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$43 = _p$40;
  const _tmp$17 = { _0: "refused", _1: new _M0DTPC14json4Json5Array(_p$43) };
  const _p$44 = r.in_force;
  const _p$45 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$44.len);
  const _p$46 = _p$44.len;
  const _p$47 = _p$44.buf;
  let _tmp$18 = 0;
  while (true) {
    const _p$48 = _tmp$18;
    if (_p$48 < _p$46) {
      const _p$49 = _p$47[_p$48];
      const _p$50 = [{ _0: "entry", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$49._0) }, { _0: "body", _1: _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$49._1) }];
      const _p$51 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_p$50, 0, 2), undefined);
      const _p$52 = new _M0DTPC14json4Json6Object(_p$51);
      _p$45.buf[_p$48] = _p$52;
      _tmp$18 = _p$48 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$48 = _p$45;
  const _tmp$19 = { _0: "in_force", _1: new _M0DTPC14json4Json5Array(_p$48) };
  const _p$49 = r.lacking;
  const _p$50 = _M0MPC15array5Array20unsafe__make__uninitGUssEE(_p$49.len);
  const _p$51 = _p$49.len;
  const _p$52 = _p$49.buf;
  let _tmp$20 = 0;
  while (true) {
    const _p$53 = _tmp$20;
    if (_p$53 < _p$51) {
      const _p$54 = _p$52[_p$53];
      const _p$55 = _M0FP39stillfail5rules2js10roster__jsN1sS7716(_p$54);
      _p$50.buf[_p$53] = _p$55;
      _tmp$20 = _p$53 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$53 = _p$50;
  const _bind = [_tmp, _tmp$3, _tmp$5, _tmp$7, _tmp$9, _tmp$11, _tmp$13, _tmp$15, _tmp$17, _tmp$19, { _0: "lacking", _1: new _M0DTPC14json4Json5Array(_p$53) }, { _0: "newest", _1: _M0FP39stillfail5rules2js9opt__json(r.newest) }, { _0: "settings", _1: _M0MPC16option6Option10unwrap__orGRPB5ArrayGRP39stillfail5rules4lock4NodeGRP39stillfail5rules4lock9LockStateEEE(r.settings, _M0DTPC14json4Json4Null__) }];
  const _p$54 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 13), undefined);
  return _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json6Object(_p$54));
}
function _M0FP39stillfail5rules2js10state4__js(ws, root, chains, bodies, now, crypto) {
  let cs;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules2js10chains__of(chains);
      if (_bind.$tag === 1) {
        const _ok = _bind;
        cs = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      break _L;
    }
    const _Invalid = _try_err;
    const _why = _Invalid._0;
    return _M0FP39stillfail5rules2js7refused(_why);
  }
  const st = _M0FP39stillfail5rules4lock6state4(ws, root, cs, _M0FP39stillfail5rules2js10bodies__of(bodies), now, { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
  const o = _M0FP39stillfail5rules2js4held(st.lock);
  _M0FP39stillfail5rules2js7js__put(o, "on", _M0FP39stillfail5rules2js11js__of__str(st.on));
  return o;
}
function _M0FP39stillfail5rules2js11ws__tag__js(ws, genesis, crypto) {
  const _p = { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto };
  return _p.method_table.method_0(_p.self, `stillfail/ws-tag/1\n${ws}\n${genesis}`);
}
function _M0FP39stillfail5rules2js14body__hash__js(body, crypto) {
  let _try_err;
  _L: {
    const _bind = _M0FP39stillfail5rules2js8json__of(body);
    let _tmp;
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _tmp = _ok._0;
    } else {
      const _err = _bind;
      _try_err = _err._0;
      break _L;
    }
    const _bind$2 = _M0FP39stillfail5rules4lock10body__hash(_tmp, { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto });
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      return _ok._0;
    } else {
      const _err = _bind$2;
      _try_err = _err._0;
      break _L;
    }
  }
  let why;
  _L$2: {
    switch (_try_err.$tag) {
      case 2: {
        const _Refused = _try_err;
        const _why = _Refused._0;
        why = _why;
        break _L$2;
      }
      case 1: {
        const _Refusal = _try_err;
        const _why$2 = _Refusal._0;
        why = _why$2;
        break _L$2;
      }
      case 0: {
        const _Invalid = _try_err;
        const _why$3 = _Invalid._0;
        return `!${_why$3}`;
      }
      default: {
        return `!${_M0FP15Error10to__string(_try_err)}`;
      }
    }
  }
  return `!${why}`;
}
function _M0FP39stillfail5rules2js17body__refusal__js(ws, body, commits, crypto) {
  let b;
  let _try_err;
  _L: {
    _L$2: {
      const _bind = _M0FP39stillfail5rules2js8json__of(body);
      if (_bind.$tag === 1) {
        const _ok = _bind;
        b = _ok._0;
      } else {
        const _err = _bind;
        _try_err = _err._0;
        break _L$2;
      }
      break _L;
    }
    const _Invalid = _try_err;
    const _why = _Invalid._0;
    return _M0FP39stillfail5rules2js11js__of__str(`a body is {ws, kind, …, salt}: ${_why}`);
  }
  const cs = new _M0TPB5ArrayGRP39stillfail5rules4lock6CommitE([], 0);
  const _bind = _M0FP39stillfail5rules2js7js__len(commits);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      _L$2: {
        const x = _M0FP39stillfail5rules2js6js__at(commits, i);
        let chain;
        let _try_err$2;
        _L$3: {
          _L$4: {
            const _bind$2 = _M0FP39stillfail5rules2js11entries__of(_M0FP39stillfail5rules2js7js__get(x, "chain"));
            if (_bind$2.$tag === 1) {
              const _ok = _bind$2;
              chain = _ok._0;
            } else {
              const _err = _bind$2;
              _try_err$2 = _err._0;
              break _L$4;
            }
            break _L$3;
          }
          break _L$2;
        }
        _M0MPC15array5Array4pushGRP39stillfail5rules4lock4StmtE(cs, new _M0TP39stillfail5rules4lock6Commit(_M0FP39stillfail5rules2js7js__str(_M0FP39stillfail5rules2js7js__get(x, "genesis")), chain));
        break _L$2;
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0FP39stillfail5rules2js7why__js(_M0FP39stillfail5rules4lock13body__refusal(ws, b, cs, { self: crypto, method_table: _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto }));
}
export { _M0FP39stillfail5rules2js13canonical__of as canonical_of, _M0FP39stillfail5rules2js15entry__text__of as entry_text_of, _M0FP39stillfail5rules2js11lower__role as lower_role, _M0FP39stillfail5rules2js8fold__js as fold_js, _M0FP39stillfail5rules2js9admit__js as admit_js, _M0FP39stillfail5rules2js11genesis__js as genesis_js, _M0FP39stillfail5rules2js9apply__js as apply_js, _M0FP39stillfail5rules2js10signer__js as signer_js, _M0FP39stillfail5rules2js14admit__one__js as admit_one_js, _M0FP39stillfail5rules2js14fold__held__js as fold_held_js, _M0FP39stillfail5rules2js16person__fold__js as person_fold_js, _M0FP39stillfail5rules2js17admit__person__js as admit_person_js, _M0FP39stillfail5rules2js12cert__ok__js as cert_ok_js, _M0FP39stillfail5rules2js13vault__ok__js as vault_ok_js, _M0FP39stillfail5rules2js12item__ok__js as item_ok_js, _M0FP39stillfail5rules2js24browser__listing__ok__js as browser_listing_ok_js, _M0FP39stillfail5rules2js14signer__of__js as signer_of_js, _M0FP39stillfail5rules2js21vault__supersedes__js as vault_supersedes_js, _M0FP39stillfail5rules2js20item__supersedes__js as item_supersedes_js, _M0FP39stillfail5rules2js11tie__of__js as tie_of_js, _M0FP39stillfail5rules2js16fork__before__js as fork_before_js, _M0FP39stillfail5rules2js15lock__chain__js as lock_chain_js, _M0FP39stillfail5rules2js17person__chain__js as person_chain_js, _M0FP39stillfail5rules2js10roster__js as roster_js, _M0FP39stillfail5rules2js10state4__js as state4_js, _M0FP39stillfail5rules2js11ws__tag__js as ws_tag_js, _M0FP39stillfail5rules2js14body__hash__js as body_hash_js, _M0FP39stillfail5rules2js17body__refusal__js as body_refusal_js }
