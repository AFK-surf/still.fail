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
function _M0TPB13StringBuilder(param0) {
  this.val = param0;
}
class $PanicError extends Error {}
function $panic() {
  throw new $PanicError();
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
const _M0FPB21int64__to__string__js = (num, radix) => BigInt.asIntN(64, num).toString(radix);
function _M0TPB4IterGUsRPC14json4JsonEE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
const _M0MPB7JSArray4push = (arr, val) => { arr.push(val); };
function _M0TPB4IterGRPC14json4JsonE(param0, param1) {
  this.f = param0;
  this.size_hint = param1;
}
function _M0TPB8MutLocalGiE(param0) {
  this.val = param0;
}
function _M0TPB9ArrayViewGRPC14json4JsonE(param0, param1, param2) {
  this.buf = param0;
  this.start = param1;
  this.end = param2;
}
function $make_array_len_and_init(a, b) {
  const arr = new Array(a);
  arr.fill(b);
  return arr;
}
function _M0TPB3MapGsRPC14json4JsonE(param0, param1, param2, param3, param4, param5, param6) {
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
function _M0TPB3MapGsRPB5ArrayGsEE(param0, param1, param2, param3, param4, param5, param6) {
  this.entries = param0;
  this.size = param1;
  this.capacity = param2;
  this.capacity_mask = param3;
  this.grow_at = param4;
  this.head = param5;
  this.tail = param6;
}
function $oob() {
  throw new Error("Index out of bounds");
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
function _M0TPB5EntryGsuE(param0, param1, param2, param3, param4, param5) {
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
function _M0DTPC16option6OptionGRPB5ArrayGsEE4None() {}
_M0DTPC16option6OptionGRPB5ArrayGsEE4None.prototype.$tag = 0;
const _M0DTPC16option6OptionGRPB5ArrayGsEE4None__ = new _M0DTPC16option6OptionGRPB5ArrayGsEE4None();
function _M0DTPC16option6OptionGRPB5ArrayGsEE4Some(param0) {
  this._0 = param0;
}
_M0DTPC16option6OptionGRPB5ArrayGsEE4Some.prototype.$tag = 1;
function _M0TPB8MutLocalGORPB5EntryGsRPC14json4JsonEE(param0) {
  this.val = param0;
}
function _M0TPB8MutLocalGORPB5EntryGsuEE(param0) {
  this.val = param0;
}
function _M0TPB8MutLocalGORPB5EntryGsRPB5ArrayGsEEE(param0) {
  this.val = param0;
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
function _M0TP39stillfail5rules4lock6Member(param0, param1, param2) {
  this.sub = param0;
  this.email = param1;
  this.role = param2;
}
function _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGRP39stillfail5rules4lock6DeviceRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
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
function _M0TP39stillfail5rules4lock7Station(param0, param1) {
  this.key = param0;
  this.name = param1;
}
function _M0TP39stillfail5rules4lock6Signer(param0, param1, param2, param3) {
  this.sub = param0;
  this.role = param1;
  this.passkey = param2;
  this.own = param3;
}
function _M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE3Err(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE3Err.prototype.$tag = 0;
function _M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok(param0) {
  this._0 = param0;
}
_M0DTPC16result6ResultGsRP39stillfail5rules4lock9LockErrorE2Ok.prototype.$tag = 1;
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
function _M0TP39stillfail5rules4lock9LockState(param0, param1, param2, param3, param4, param5, param6, param7, param8, param9, param10, param11, param12, param13, param14) {
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
  this.disabled = param14;
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
const _M0FP077stillfail_2frules_2fjs_2fJsCrypto_24as_24_40stillfail_2frules_2flock_2eCrypto = { method_0: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto11sha256__hex, method_1: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto10sig__valid, method_2: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto14valid__key__id, method_3: _M0IP39stillfail5rules2js8JsCryptoP39stillfail5rules4lock6Crypto15endpoint__proof };
function _M0FP15Error10to__string(_e) {
  const _f = _M0FP15Error10_2amethods[_e.$tag]._1;
  return _f(_e);
}
const _M0FP15Error13_2amethods__0 = { _0: "stillfail/rules/form.Invalid.Invalid", _1: (_e) => _M0FP15Error10_2amethods[_e.$tag]._0 };
const _M0FP15Error13_2amethods__1 = { _0: "stillfail/rules/lock.LockError.Refusal", _1: (_e) => _M0FP15Error10_2amethods[_e.$tag]._0 };
const _M0FP15Error13_2amethods__2 = { _0: "stillfail/rules/lock.LockError.Refused", _1: (_e) => _M0FP15Error10_2amethods[_e.$tag]._0 };
const _M0FP15Error10_2amethods = [_M0FP15Error13_2amethods__0, _M0FP15Error13_2amethods__1, _M0FP15Error13_2amethods__2];
const _M0MPB4Iter4nextN6constrS22GUsRPB5ArrayGsEEE = 0;
const _M0MPB4Iter4nextN6constrS23GUsRPB5ArrayGsEEE = 0;
const _M0MPB4Iter3newN6constrS96GUsRPC14json4JsonEE = 0;
const _M0FP39stillfail5rules4form11hex__digits = "0123456789abcdef";
const _M0FP39stillfail5rules4lock8role__ofN6constrS1448 = 3;
const _M0FP39stillfail5rules4lock8role__ofN6constrS1449 = 2;
const _M0FP39stillfail5rules4lock8role__ofN6constrS1450 = 1;
const _M0FP39stillfail5rules4lock8role__ofN6constrS1451 = 0;
const _M0FPB4seed = _M0FPB12random__seed();
const _M0FP39stillfail5rules4lock7passkeyN6recordS1506 = new _M0TPC16string10StringView("p256:", 0, 5);
const _M0FP39stillfail5rules4lock5applyN6constrS1751 = new _M0DTPC16option6OptionGdE4Some(1);
const _M0FP39stillfail5rules4lock7genesisN6constrS1659 = "genesis";
const _M0FP39stillfail5rules4lock7genesisN6constrS1660 = new _M0DTPC16option6OptionGdE4Some(0);
const _M0FP39stillfail5rules4lock7genesisN6constrS1661 = new _M0DTPC16option6OptionGdE4Some(1);
function _M0FPB13consume4__acc(acc, input) {
  const _p = (acc >>> 0) + ((Math.imul(input, -1028477379) | 0) >>> 0) | 0;
  const _p$2 = 17;
  return Math.imul(_p << _p$2 | (_p >>> (32 - _p$2 | 0) | 0), 668265263) | 0;
}
function _M0MPB13StringBuilder21StringBuilder_2einner(size_hint) {
  if (size_hint >= 0) {
    return new _M0TPB13StringBuilder("");
  } else {
    console.error("size_hint must be non-negative");
    return $panic();
  }
}
function _M0IPB13StringBuilderPB6Logger11write__char(self, ch) {
  self.val = `${self.val}${String.fromCodePoint(ch)}`;
}
function _M0IPB13StringBuilderPB6Logger13write__string(self, str) {
  self.val = `${self.val}${str}`;
}
function _M0IP016_24default__implPB2Eq10not__equalGOsE(x, y) {
  return !_M0IPC16option6OptionPB2Eq5equalGsE(x, y);
}
function _M0IP016_24default__implPB2Eq10not__equalGOdE(x, y) {
  return !_M0IPC16option6OptionPB2Eq5equalGdE(x, y);
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
function _M0MPB4Iter4nextGUsRPB5ArrayGsEEE(self) {
  const _func = self.f;
  const result = _func();
  const _bind = self.size_hint;
  if (result === undefined) {
    self.size_hint = _M0MPB4Iter4nextN6constrS23GUsRPB5ArrayGsEEE;
  } else {
    if (_bind === undefined) {
    } else {
      const _Some = _bind;
      const _n = _Some;
      self.size_hint = _n > 0 ? _n - 1 | 0 : _M0MPB4Iter4nextN6constrS22GUsRPB5ArrayGsEEE;
    }
  }
  return result;
}
function _M0MPC15int645Int6418to__string_2einner(self, radix) {
  return _M0FPB21int64__to__string__js(self, radix);
}
function _M0MPB4Iter3newGUsRPC14json4JsonEE(f, size_hint) {
  let size_hint$2;
  if (size_hint === undefined) {
    size_hint$2 = undefined;
  } else {
    const _Some = size_hint;
    const _n = _Some;
    size_hint$2 = _n > 0 ? _n : _M0MPB4Iter3newN6constrS96GUsRPC14json4JsonEE;
  }
  return new _M0TPB4IterGUsRPC14json4JsonEE(f, size_hint$2);
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
function _M0MPC16string10StringView11has__prefix(self, str) {
  const str_len = str.end - str.start | 0;
  return str_len <= (self.end - self.start | 0) ? (str_len === 0 || self.str.charCodeAt(self.start) === str.str.charCodeAt(str.start) ? _M0MPC16string6String20unsafe__range__equal(self.str, self.start, str.str, str.start, str_len) : false) : false;
}
function _M0MPC16string6String11has__prefix(self, str) {
  return _M0MPC16string10StringView11has__prefix(new _M0TPC16string10StringView(self, 0, self.length), str);
}
function _M0MPC15array5Array4pushGUsRPC14json4JsonEE(self, value) {
  _M0MPB7JSArray4push(self, value);
}
function _M0MPB4Iter3mapGsRPC14json4JsonE(self, f) {
  return new _M0TPB4IterGRPC14json4JsonE(() => {
    const _bind = _M0MPB4Iter4nextGUsRPB5ArrayGsEEE(self);
    if (_bind === undefined) {
      return undefined;
    } else {
      const _Some = _bind;
      const _x = _Some;
      return f(_x);
    }
  }, self.size_hint);
}
function _M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(self) {
  const _bind = self.size_hint;
  let result;
  if (_bind === undefined) {
    result = [];
  } else {
    result = [];
  }
  while (true) {
    const _bind$2 = _M0MPB4Iter4nextGUsRPB5ArrayGsEEE(self);
    if (_bind$2 === undefined) {
      break;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      _M0MPC15array5Array4pushGUsRPC14json4JsonEE(result, _x);
      continue;
    }
  }
  return result;
}
function _M0MPC15array9ArrayView4iterGRPC14json4JsonE(self) {
  const i = new _M0TPB8MutLocalGiE(0);
  const len = self.end - self.start | 0;
  return _M0MPB4Iter3newGUsRPC14json4JsonEE(() => {
    if (i.val < len) {
      const elem = self.buf[self.start + i.val | 0];
      i.val = i.val + 1 | 0;
      return elem;
    } else {
      return undefined;
    }
  }, len);
}
function _M0MPC15array5Array4iterGRPC14json4JsonE(self) {
  return _M0MPC15array9ArrayView4iterGRPC14json4JsonE(new _M0TPB9ArrayViewGRPC14json4JsonE(self, 0, self.length));
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
function _M0MPC16option6Option10unwrap__orGRPC14json4JsonE(self, default_) {
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
function _M0MPC16option6Option10unwrap__orGRPB5ArrayGsEE(self, default_) {
  if (self.$tag === 1) {
    const _Some = self;
    const _t = _Some._0;
    return _t;
  } else {
    return default_;
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
function _M0FPB8new__mapGsRPC14json4JsonE(capacity) {
  const capacity$2 = _M0MPC13int3Int20next__power__of__two(capacity);
  const _bind = capacity$2 - 1 | 0;
  const _bind$2 = _M0FPB21calc__grow__threshold(capacity$2);
  const _bind$3 = $make_array_len_and_init(capacity$2, undefined);
  const _bind$4 = undefined;
  return new _M0TPB3MapGsRPC14json4JsonE(_bind$3, 0, capacity$2, _bind, _bind$2, _bind$4, -1);
}
function _M0FPB8new__mapGsuE(capacity) {
  const capacity$2 = _M0MPC13int3Int20next__power__of__two(capacity);
  const _bind = capacity$2 - 1 | 0;
  const _bind$2 = _M0FPB21calc__grow__threshold(capacity$2);
  const _bind$3 = $make_array_len_and_init(capacity$2, undefined);
  const _bind$4 = undefined;
  return new _M0TPB3MapGsuE(_bind$3, 0, capacity$2, _bind, _bind$2, _bind$4, -1);
}
function _M0FPB8new__mapGsRPB5ArrayGsEE(capacity) {
  const capacity$2 = _M0MPC13int3Int20next__power__of__two(capacity);
  const _bind = capacity$2 - 1 | 0;
  const _bind$2 = _M0FPB21calc__grow__threshold(capacity$2);
  const _bind$3 = $make_array_len_and_init(capacity$2, undefined);
  const _bind$4 = undefined;
  return new _M0TPB3MapGsRPB5ArrayGsEE(_bind$3, 0, capacity$2, _bind, _bind$2, _bind$4, -1);
}
function _M0FPB21capacity__for__length(length) {
  if (length <= _M0FPB21calc__grow__threshold(1073741824)) {
    let capacity = _M0MPC13int3Int20next__power__of__two(length);
    if (length > _M0FPB21calc__grow__threshold(capacity)) {
      capacity = Math.imul(capacity, 2) | 0;
    }
    return capacity;
  } else {
    console.error("Map capacity overflow");
    return $panic();
  }
}
function _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry) {
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
function _M0MPB3Map20add__entry__to__tailGsRPB5ArrayGsEE(self, idx, entry) {
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
function _M0MPB3Map10set__entryGsRPC14json4JsonE(self, entry, new_idx) {
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
function _M0MPB3Map10set__entryGsRPB5ArrayGsEE(self, entry, new_idx) {
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
function _M0MPB3Map10push__awayGsRPC14json4JsonE(self, idx, entry) {
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
      _M0MPB3Map10set__entryGsRPC14json4JsonE(self, entry$2, idx$2);
      return;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (psl > _curr_entry.psl) {
        entry$2.psl = psl;
        _M0MPB3Map10set__entryGsRPC14json4JsonE(self, entry$2, idx$2);
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
function _M0MPB3Map10push__awayGsRPB5ArrayGsEE(self, idx, entry) {
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
      _M0MPB3Map10set__entryGsRPB5ArrayGsEE(self, entry$2, idx$2);
      return;
    } else {
      const _Some = _bind;
      const _curr_entry = _Some;
      if (psl > _curr_entry.psl) {
        entry$2.psl = psl;
        _M0MPB3Map10set__entryGsRPB5ArrayGsEE(self, entry$2, idx$2);
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
function _M0MPB3Map20rehash__place__entryGsRPC14json4JsonE(self, outer) {
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
      _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, outer);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr = _Some;
      if (psl > _curr.psl) {
        _M0MPB3Map10push__awayGsRPC14json4JsonE(self, idx, _curr);
        outer.psl = psl;
        outer.prev = self.tail;
        _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, outer);
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
function _M0MPB3Map20rehash__place__entryGsRPB5ArrayGsEE(self, outer) {
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
      _M0MPB3Map20add__entry__to__tailGsRPB5ArrayGsEE(self, idx, outer);
      return undefined;
    } else {
      const _Some = _bind;
      const _curr = _Some;
      if (psl > _curr.psl) {
        _M0MPB3Map10push__awayGsRPB5ArrayGsEE(self, idx, _curr);
        outer.psl = psl;
        outer.prev = self.tail;
        _M0MPB3Map20add__entry__to__tailGsRPB5ArrayGsEE(self, idx, outer);
        return undefined;
      } else {
        _tmp = psl + 1 | 0;
        _tmp$2 = idx + 1 & self.capacity_mask;
        continue;
      }
    }
  }
}
function _M0MPB3Map4growGsRPC14json4JsonE(self) {
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
      _M0MPB3Map20rehash__place__entryGsRPC14json4JsonE(self, _e);
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
function _M0MPB3Map4growGsRPB5ArrayGsEE(self) {
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
      _M0MPB3Map20rehash__place__entryGsRPB5ArrayGsEE(self, _e);
      _tmp = next_in_chain;
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
        _M0MPB3Map4growGsRPC14json4JsonE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRPC14json4JsonE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
          _M0MPB3Map4growGsRPC14json4JsonE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsRPC14json4JsonE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRPC14json4JsonE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
        _M0MPB3Map4growGsRPC14json4JsonE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock6DeviceE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
          _M0MPB3Map4growGsRPC14json4JsonE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsRPC14json4JsonE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock6DeviceE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
function _M0MPB3Map15set__with__hashGsRPB5ArrayGsEE(self, key, value, hash) {
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const psl = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      if (self.size >= self.grow_at) {
        _M0MPB3Map4growGsRPB5ArrayGsEE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRPB5ArrayGsEE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsRPB5ArrayGsEE(self, idx, entry);
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
          _M0MPB3Map4growGsRPB5ArrayGsEE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsRPB5ArrayGsEE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRPB5ArrayGsEE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsRPB5ArrayGsEE(self, idx, entry);
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
        _M0MPB3Map4growGsRPC14json4JsonE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock6MemberE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
          _M0MPB3Map4growGsRPC14json4JsonE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsRPC14json4JsonE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock6MemberE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
        _M0MPB3Map4growGsRPC14json4JsonE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock7StationE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
          _M0MPB3Map4growGsRPC14json4JsonE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsRPC14json4JsonE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock7StationE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
        _M0MPB3Map4growGsRPC14json4JsonE(self);
        _tmp = 0;
        _tmp$2 = hash & self.capacity_mask;
        continue;
      }
      const _bind$2 = self.tail;
      const _bind$3 = undefined;
      const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock7PasskeyE(_bind$2, _bind$3, psl, hash, key, value);
      _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
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
          _M0MPB3Map4growGsRPC14json4JsonE(self);
          _tmp = 0;
          _tmp$2 = hash & self.capacity_mask;
          continue;
        }
        _M0MPB3Map10push__awayGsRPC14json4JsonE(self, idx, _curr_entry);
        const _bind$2 = self.tail;
        const _bind$3 = undefined;
        const entry = new _M0TPB5EntryGsRP39stillfail5rules4lock7PasskeyE(_bind$2, _bind$3, psl, hash, key, value);
        _M0MPB3Map20add__entry__to__tailGsRPC14json4JsonE(self, idx, entry);
        return undefined;
      }
      _tmp = psl + 1 | 0;
      _tmp$2 = idx + 1 & self.capacity_mask;
      continue;
    }
  }
}
function _M0MPB3Map3setGsRPC14json4JsonE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRPC14json4JsonE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRP39stillfail5rules4lock6DeviceE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRP39stillfail5rules4lock6DeviceE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsuE(self, key, value) {
  _M0MPB3Map15set__with__hashGsuE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
}
function _M0MPB3Map3setGsRPB5ArrayGsEE(self, key, value) {
  _M0MPB3Map15set__with__hashGsRPB5ArrayGsEE(self, key, value, _M0IPC16string6StringPB4Hash4hash(key));
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
  const m = _M0FPB8new__mapGsRPC14json4JsonE(capacity$2);
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
  const m = _M0FPB8new__mapGsRPC14json4JsonE(capacity$2);
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
  const m = _M0FPB8new__mapGsRPB5ArrayGsEE(capacity$2);
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
  const m = _M0FPB8new__mapGsRPC14json4JsonE(capacity$2);
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
  const m = _M0FPB8new__mapGsRPC14json4JsonE(capacity$2);
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
  const m = _M0FPB8new__mapGsRPC14json4JsonE(capacity$2);
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
function _M0MPB3Map3getGsRPB5ArrayGsEE(self, key) {
  const hash = _M0IPC16string6StringPB4Hash4hash(key);
  let _tmp = 0;
  let _tmp$2 = hash & self.capacity_mask;
  while (true) {
    const i = _tmp;
    const idx = _tmp$2;
    const _bind = self.entries[idx];
    if (_bind === undefined) {
      return _M0DTPC16option6OptionGRPB5ArrayGsEE4None__;
    } else {
      const _Some = _bind;
      const _entry = _Some;
      if (_entry.hash === hash && _entry.key === key) {
        return new _M0DTPC16option6OptionGRPB5ArrayGsEE4Some(_entry.value);
      }
      if (i > _entry.psl) {
        return _M0DTPC16option6OptionGRPB5ArrayGsEE4None__;
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
function _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock6DeviceE(self, entry) {
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
function _M0MPB3Map11shift__backGsRP39stillfail5rules4lock6DeviceE(self, idx) {
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
          _M0MPB3Map10set__entryGsRPC14json4JsonE(self, _x, cur);
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
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock6DeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock6DeviceE(self, idx);
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
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock6DeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock6DeviceE(self, idx);
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
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock6DeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock6DeviceE(self, idx);
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
        _M0MPB3Map13remove__entryGsRP39stillfail5rules4lock6DeviceE(self, _entry);
        _M0MPB3Map11shift__backGsRP39stillfail5rules4lock6DeviceE(self, idx);
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
function _M0MPB3Map4iterGsRPC14json4JsonE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPB5EntryGsRPC14json4JsonEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGUsRPC14json4JsonEE(() => {
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
  return _M0MPB4Iter3newGUsRPC14json4JsonEE(() => {
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
function _M0MPB3Map4iterGsRPB5ArrayGsEE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPB5EntryGsRPB5ArrayGsEEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGUsRPC14json4JsonEE(() => {
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
function _M0MPB3Map5iter2GsRPC14json4JsonE(self) {
  return _M0MPB3Map4iterGsRPC14json4JsonE(self);
}
function _M0MPB3Map5iter2GsuE(self) {
  return _M0MPB3Map4iterGsuE(self);
}
function _M0MPB3Map5iter2GsRPB5ArrayGsEE(self) {
  return _M0MPB3Map4iterGsRPB5ArrayGsEE(self);
}
function _M0MPB3Map4keysGsRPC14json4JsonE(self) {
  const curr_entry = new _M0TPB8MutLocalGORPB5EntryGsRPC14json4JsonEE(self.head);
  const len = self.size;
  const remaining = new _M0TPB8MutLocalGiE(len);
  return _M0MPB4Iter3newGUsRPC14json4JsonEE(() => {
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
  return _M0MPB4Iter3newGUsRPC14json4JsonEE(() => {
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
function _M0MPB5Iter24nextGsRPC14json4JsonE(self) {
  return _M0MPB4Iter4nextGUsRPB5ArrayGsEEE(self);
}
function _M0MPB5Iter24nextGsuE(self) {
  return _M0MPB4Iter4nextGUsRPB5ArrayGsEEE(self);
}
function _M0MPB5Iter24nextGsRPB5ArrayGsEE(self) {
  return _M0MPB4Iter4nextGUsRPB5ArrayGsEEE(self);
}
function _M0IPC16string6StringPB4Hash4hash(self) {
  let acc = (_M0FPB4seed >>> 0) + (374761393 >>> 0) | 0;
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
function _M0MPC16double6Double5floor(_tmp) {
  return Math.floor(_tmp);
}
function _M0MPC15array5Array2atGRPC14json4JsonE(self, index) {
  const len = self.length;
  return index >= 0 && index < len ? self[index] : $panic();
}
function _M0MPC15array12MutArrayView4swapGsE(arr, i, j) {
  const temp = arr.buf[arr.start + i | 0];
  arr.buf[arr.start + i | 0] = arr.buf[arr.start + j | 0];
  arr.buf[arr.start + j | 0] = temp;
}
function _M0MPC15array12MutArrayView5sliceGsE(arr, start, end) {
  const _bind = arr.end - arr.start | 0;
  if (start < 0 || (start > end || end > _bind)) {
    $panic();
  }
  return new _M0TPB12MutArrayViewGsE(arr.buf, start + arr.start | 0, end + arr.start | 0);
}
function _M0MPC15array12MutArrayView14rev__in__placeGsE(arr) {
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
function _M0FPB23fixed__bubble__sort__byGsE(arr, cmp) {
  const _bind = arr.end - arr.start | 0;
  let _tmp = 1;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      let _tmp$2 = i;
      while (true) {
        const j = _tmp$2;
        if (j > 0 && cmp(arr.buf[arr.start + (j - 1 | 0) | 0], arr.buf[arr.start + j | 0]) > 0) {
          _M0MPC15array12MutArrayView4swapGsE(arr, j, j - 1 | 0);
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
function _M0FPB24fixed__choose__pivot__byN7sort__2S1198GsE(_env, a, b) {
  const arr = _env._2;
  const cmp = _env._1;
  const swaps = _env._0;
  if (cmp(arr.buf[arr.start + a | 0], arr.buf[arr.start + b | 0]) > 0) {
    _M0MPC15array12MutArrayView4swapGsE(arr, a, b);
    swaps.val = swaps.val + 1 | 0;
    return;
  } else {
    return;
  }
}
function _M0FPB24fixed__choose__pivot__byN7sort__3S1199GsE(_env, a, b, c) {
  _M0FPB24fixed__choose__pivot__byN7sort__2S1198GsE(_env, a, b);
  _M0FPB24fixed__choose__pivot__byN7sort__2S1198GsE(_env, b, c);
  _M0FPB24fixed__choose__pivot__byN7sort__2S1198GsE(_env, a, b);
}
function _M0FPB24fixed__choose__pivot__byGsE(arr, cmp) {
  const len = arr.end - arr.start | 0;
  const swaps = new _M0TPB8MutLocalGiE(0);
  const b = Math.imul(len / 4 | 0, 2) | 0;
  if (len >= 8) {
    const a = Math.imul(len / 4 | 0, 1) | 0;
    const c = Math.imul(len / 4 | 0, 3) | 0;
    const _env = { _0: swaps, _1: cmp, _2: arr };
    if (len > 50) {
      _M0FPB24fixed__choose__pivot__byN7sort__3S1199GsE(_env, a - 1 | 0, a, a + 1 | 0);
      _M0FPB24fixed__choose__pivot__byN7sort__3S1199GsE(_env, b - 1 | 0, b, b + 1 | 0);
      _M0FPB24fixed__choose__pivot__byN7sort__3S1199GsE(_env, c - 1 | 0, c, c + 1 | 0);
    }
    _M0FPB24fixed__choose__pivot__byN7sort__3S1199GsE(_env, a, b, c);
  }
  if (swaps.val === 12) {
    _M0MPC15array12MutArrayView14rev__in__placeGsE(arr);
    return { _0: (len - b | 0) - 1 | 0, _1: true };
  } else {
    return { _0: b, _1: swaps.val === 0 };
  }
}
function _M0FPB21fixed__sift__down__byGsE(arr, index, cmp) {
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
      _M0MPC15array12MutArrayView4swapGsE(arr, index$2, child$2);
      _tmp = child$2;
      _tmp$2 = (Math.imul(child$2, 2) | 0) + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB21fixed__heap__sort__byGsE(arr, cmp) {
  const len = arr.end - arr.start | 0;
  const _bind = len / 2 | 0;
  let _tmp = _bind - 1 | 0;
  let _tmp$2 = _bind > 0;
  while (true) {
    const i = _tmp;
    const _more = _tmp$2;
    if (_more) {
      _M0FPB21fixed__sift__down__byGsE(arr, i, cmp);
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
      _M0MPC15array12MutArrayView4swapGsE(arr, 0, i);
      _M0FPB21fixed__sift__down__byGsE(_M0MPC15array12MutArrayView5sliceGsE(arr, 0, i), 0, cmp);
      _tmp$3 = i - 1 | 0;
      _tmp$4 = i > 1;
      continue;
    } else {
      return;
    }
  }
}
function _M0FPB20fixed__partition__byGsE(arr, cmp, pivot_index) {
  _M0MPC15array12MutArrayView4swapGsE(arr, pivot_index, (arr.end - arr.start | 0) - 1 | 0);
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
          _M0MPC15array12MutArrayView4swapGsE(arr, i, j);
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
      _M0MPC15array12MutArrayView4swapGsE(arr, i, (arr.end - arr.start | 0) - 1 | 0);
      return { _0: i, _1: partitioned };
    }
  }
}
function _M0FPB28fixed__try__bubble__sort__byGsE(arr, cmp) {
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
          _M0MPC15array12MutArrayView4swapGsE(arr, j, j - 1 | 0);
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
function _M0FPB22fixed__quick__sort__byGsE(arr, cmp, pred, limit) {
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
        _M0FPB23fixed__bubble__sort__byGsE(arr$2, cmp);
      }
      return undefined;
    }
    if (limit$2 === 0) {
      _M0FPB21fixed__heap__sort__byGsE(arr$2, cmp);
      return undefined;
    }
    const _bind = _M0FPB24fixed__choose__pivot__byGsE(arr$2, cmp);
    const _pivot_index = _bind._0;
    const _likely_sorted = _bind._1;
    if (was_partitioned && (balanced && _likely_sorted)) {
      if (_M0FPB28fixed__try__bubble__sort__byGsE(arr$2, cmp)) {
        return undefined;
      }
    }
    const _bind$2 = _M0FPB20fixed__partition__byGsE(arr$2, cmp, _pivot_index);
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
        _tmp$2 = _M0MPC15array12MutArrayView5sliceGsE(arr$2, i, len);
        _tmp$4 = _partitioned;
        _tmp$5 = balanced$2;
        continue;
      }
    }
    const left = _M0MPC15array12MutArrayView5sliceGsE(arr$2, 0, _pivot);
    const right = _M0MPC15array12MutArrayView5sliceGsE(arr$2, _pivot + 1 | 0, len);
    if ((left.end - left.start | 0) < (right.end - right.start | 0)) {
      _M0FPB22fixed__quick__sort__byGsE(left, cmp, pred$2, limit$3);
      _tmp = limit$3;
      _tmp$2 = right;
      _tmp$3 = arr$2.buf[arr$2.start + _pivot | 0];
      _tmp$4 = _partitioned;
      _tmp$5 = balanced$2;
      continue;
    } else {
      _M0FPB22fixed__quick__sort__byGsE(right, cmp, arr$2.buf[arr$2.start + _pivot | 0], limit$3);
      _tmp = limit$3;
      _tmp$2 = left;
      _tmp$4 = _partitioned;
      _tmp$5 = balanced$2;
      continue;
    }
  }
}
function _M0MPC15array12MutArrayView8sort__byGsE(self, cmp) {
  _M0FPB22fixed__quick__sort__byGsE(self, cmp, undefined, _M0FPB17fixed__get__limit(self.end - self.start | 0));
}
function _M0MPC15array5Array8sort__byGsE(self, cmp) {
  const _bind = self.length;
  _M0MPC15array12MutArrayView8sort__byGsE(new _M0TPB12MutArrayViewGsE(self, 0, _bind), cmp);
}
function _M0MPC15array5Array8containsGsE(self, value) {
  const _bind = self.length;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const v = self[_];
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
  }
  while (true) {
    const _bind$2 = _M0MPB4Iter4nextGUsRPB5ArrayGsEEE(iter);
    if (_bind$2 === undefined) {
      return;
    } else {
      const _Some = _bind$2;
      const _x = _Some;
      _M0MPC15array5Array4pushGUsRPC14json4JsonEE(self, _x);
      continue;
    }
  }
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
  const _bind = [12, 8, 4, 0];
  const _bind$2 = _bind.length;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind$2) {
      const shift = _bind[_];
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
      const _bind = _xs.length;
      let _tmp = 0;
      while (true) {
        const i = _tmp;
        if (i < _bind) {
          const x = _xs[i];
          if (i > 0) {
            _M0IPB13StringBuilderPB6Logger11write__char(b, 44);
          }
          const _bind$2 = _M0FP39stillfail5rules4form5write(b, x);
          if (_bind$2.$tag === 1) {
            const _ok = _bind$2;
            _ok._0;
          } else {
            return _bind$2;
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
      const keys = _M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB3Map4keysGsRPC14json4JsonE(_m));
      _M0MPC15array5Array8sort__byGsE(keys, _M0FP39stillfail5rules4form11code__units);
      _M0IPB13StringBuilderPB6Logger11write__char(b, 123);
      const _bind$2 = keys.length;
      let _tmp$2 = 0;
      while (true) {
        const i = _tmp$2;
        if (i < _bind$2) {
          const k = keys[i];
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
          const _bind$3 = _M0FP39stillfail5rules4form5write(b, _tmp$3);
          if (_bind$3.$tag === 1) {
            const _ok = _bind$3;
            _ok._0;
          } else {
            return _bind$3;
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
    const _bind$2 = ["v", "ws", "seq", "prev", "at", "kind", "body"];
    const _bind$3 = _bind$2.length;
    let _tmp = 0;
    while (true) {
      const _ = _tmp;
      if (_ < _bind$3) {
        const k = _bind$2[_];
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
function _M0FP39stillfail5rules4lock6refuse(why) {
  return new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(why));
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
  return [];
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
            return _M0FP39stillfail5rules4lock8role__ofN6constrS1448;
          }
          case "admin": {
            return _M0FP39stillfail5rules4lock8role__ofN6constrS1449;
          }
          case "member": {
            return _M0FP39stillfail5rules4lock8role__ofN6constrS1450;
          }
          case "viewer": {
            return _M0FP39stillfail5rules4lock8role__ofN6constrS1451;
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
function _M0FP39stillfail5rules4lock8managing(role) {
  return _M0FP39stillfail5rules4role4rank(_M0FP39stillfail5rules4lock11role__named(role)) >= 2;
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
  const label = _M0MPC16option6Option10unwrap__orGRPC14json4JsonE(_M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "label"), 200), "");
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
                  endpoints = _M0DTPC16option6OptionGRPB5ArrayGsEE4None__;
                } else {
                  const _Some$3 = _bind$2;
                  const _x = _Some$3;
                  if (_x.$tag === 5) {
                    const _Array = _x;
                    const _xs = _Array._0;
                    let _tmp;
                    if (_xs.length <= 64) {
                      const _p$2 = _M0MPC15array5Array4iterGRPC14json4JsonE(_xs);
                      let _tmp$2;
                      while (true) {
                        const _p$3 = _M0MPB4Iter4nextGUsRPB5ArrayGsEEE(_p$2);
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
                      const _p$2 = new Array(_xs.length);
                      const _p$3 = _xs.length;
                      let _tmp$2 = 0;
                      while (true) {
                        const _p$4 = _tmp$2;
                        if (_p$4 < _p$3) {
                          const _p$5 = _xs[_p$4];
                          const _p$6 = _M0FP39stillfail5rules4lock8text__of(_p$5);
                          let _tmp$3;
                          if (_p$6 === undefined) {
                            _tmp$3 = $panic();
                          } else {
                            const _p$7 = _p$6;
                            _tmp$3 = _p$7;
                          }
                          _p$2[_p$4] = _tmp$3;
                          _tmp$2 = _p$4 + 1 | 0;
                          continue;
                        } else {
                          break;
                        }
                      }
                      endpoints = new _M0DTPC16option6OptionGRPB5ArrayGsEE4Some(_p$2);
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
  const label = _M0MPC16option6Option10unwrap__orGRPC14json4JsonE(_M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "label"), 200), "");
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
              _tmp$2 = _M0MPC16string6String11has__prefix(_key, _M0FP39stillfail5rules4lock7passkeyN6recordS1506) && (_key.length <= 200 && c.method_table.method_2(c.self, _key));
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
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock7StationRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock7Station(_tmp, _M0MPC16option6Option10unwrap__orGRPC14json4JsonE(_M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(v, "name"), 200), "")));
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
  const _it = _M0MPB3Map5iter2GsRPC14json4JsonE(s.passkeys);
  while (true) {
    const _bind = _M0MPB5Iter24nextGsRPC14json4JsonE(_it);
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
  const _it$2 = _M0MPB3Map5iter2GsRPC14json4JsonE(s.devices);
  while (true) {
    const _bind = _M0MPB5Iter24nextGsRPC14json4JsonE(_it$2);
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
      if (_M0IPC16option6OptionPB2Eq5equalGsE(_d.sign_key, key) && (_d.kind === "app" && (live && !own_found))) {
        const _bind$4 = _M0FP39stillfail5rules4lock10with__role(s, _d.sub, false, _d.own);
        if (_bind$4 === undefined) {
        } else {
          const _Some$2 = _bind$4;
          const _w = _Some$2;
          found = _w;
        }
      }
      continue;
    }
  }
  return found;
}
function _M0FP39stillfail5rules4lock7own__of(s, sub, by, was, key) {
  if (by.sub === sub) {
    return true;
  }
  if (was === undefined) {
  } else {
    const _Some = was;
    const _w = _Some;
    if (_w.own) {
      if (_M0IPC16option6OptionPB2Eq5equalGsE(_w.sign_key, key)) {
        return true;
      }
    }
  }
  return _M0FP39stillfail5rules4lock8managing(by.role) && !_M0MPB3Map8containsGsuE(s.signed, sub);
}
function _M0FP39stillfail5rules4lock6owners(s) {
  let n = 0;
  const _it = _M0MPB3Map5iter2GsRPC14json4JsonE(s.members);
  while (true) {
    const _bind = _M0MPB5Iter24nextGsRPC14json4JsonE(_it);
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
    const had = _M0MPC16option6Option10unwrap__orGRPB5ArrayGsEE(_M0MPB3Map3getGsRPB5ArrayGsEE(s.sign_keys, d.id), []);
    if (!_M0MPC15array5Array8containsGsE(had, _k)) {
      const _tmp = s.sign_keys;
      const _tmp$2 = d.id;
      const _self = [];
      _M0MPC15array5Array10push__iterGsE(_self, _M0MPC15array5Array4iterGRPC14json4JsonE(had));
      _M0MPC15array5Array4pushGUsRPC14json4JsonEE(_self, _k);
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
function _M0FP39stillfail5rules4lock8sig__key(e) {
  return _M0MPC16option6Option10unwrap__orGRPC14json4JsonE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(_M0FP39stillfail5rules4lock5field(e, "sig"), "key")), "");
}
function _M0FP39stillfail5rules4lock7sig__of(e) {
  return _M0MPC16option6Option10unwrap__orGRPC14json4JsonE(_M0FP39stillfail5rules4lock5field(e, "sig"), _M0DTPC14json4Json4Null__);
}
function _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock6DeviceE(m) {
  const _bind = [];
  const out = _M0MPB3Map3MapGsRP39stillfail5rules4lock6DeviceE(new _M0TPB9ArrayViewGUsRP39stillfail5rules4lock6DeviceEE(_bind, 0, 0), undefined);
  const _it = _M0MPB3Map5iter2GsRPC14json4JsonE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGsRPC14json4JsonE(_it);
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
  const _it = _M0MPB3Map5iter2GsRPB5ArrayGsEE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGsRPB5ArrayGsEE(_it);
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
  const _it = _M0MPB3Map5iter2GsRPC14json4JsonE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGsRPC14json4JsonE(_it);
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
  const _it = _M0MPB3Map5iter2GsRPC14json4JsonE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGsRPC14json4JsonE(_it);
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
  const _it = _M0MPB3Map5iter2GsRPC14json4JsonE(m);
  while (true) {
    const _bind$2 = _M0MPB5Iter24nextGsRPC14json4JsonE(_it);
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
function _M0FP39stillfail5rules4lock7genesis(e, c) {
  const v = e;
  const ws = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "ws"));
  _L: {
    if (_M0IPC16option6OptionPB2Eq5equalGsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "kind")), _M0FP39stillfail5rules4lock7genesisN6constrS1659)) {
      if (_M0IPC16option6OptionPB2Eq5equalGdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "seq")), _M0FP39stillfail5rules4lock7genesisN6constrS1660)) {
        _L$2: {
          const _bind = _M0FP39stillfail5rules4lock5field(v, "prev");
          if (_bind === undefined) {
            break _L$2;
          } else {
            const _Some = _bind;
            const _x = _Some;
            if (_x.$tag === 0) {
              if (_M0IPC16option6OptionPB2Eq5equalGdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "v")), _M0FP39stillfail5rules4lock7genesisN6constrS1661)) {
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
                    const _p$3 = [];
                    const _p$4 = _p$2.length;
                    let origins;
                    let _tmp = 0;
                    while (true) {
                      const _p$5 = _tmp;
                      if (_p$5 < _p$4) {
                        const _p$6 = _p$2[_p$5];
                        const _p$7 = _M0FP39stillfail5rules4lock8text__of(_p$6);
                        if (_p$7 === undefined) {
                        } else {
                          const _p$8 = _p$7;
                          const _p$9 = _p$8;
                          _M0MPC15array5Array4pushGUsRPC14json4JsonEE(_p$3, _p$9);
                        }
                        _tmp = _p$5 + 1 | 0;
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
                    const _bind$3 = _M0MPC16option6Option10unwrap__orGRPC14json4JsonE(_M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(b, "rp_id"), 200), "");
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
                    const s = new _M0TP39stillfail5rules4lock9LockState(_ws, 0, hash, hash, origins, _bind$3, _bind$5, _bind$7, _bind$9, _bind$11, _bind$13, _bind$15, _bind$17, _bind$19, false);
                    const _bind$20 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "members"));
                    const _bind$21 = _bind$20.length;
                    let _tmp$2 = 0;
                    while (true) {
                      const _ = _tmp$2;
                      if (_ < _bind$21) {
                        const m = _bind$20[_];
                        const _bind$22 = _M0FP39stillfail5rules4lock6member(m);
                        let m$2;
                        if (_bind$22.$tag === 1) {
                          const _ok = _bind$22;
                          m$2 = _ok._0;
                        } else {
                          return _bind$22;
                        }
                        _M0MPB3Map3setGsRP39stillfail5rules4lock6MemberE(_bind$7, m$2.sub, m$2);
                        _tmp$2 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const owner = _M0FP39stillfail5rules4lock11str_2einner(_M0FP39stillfail5rules4lock5field(b, "owner"), 200);
                    const _bind$22 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "devices"));
                    const _bind$23 = _bind$22.length;
                    let _tmp$3 = 0;
                    while (true) {
                      const _ = _tmp$3;
                      if (_ < _bind$23) {
                        const d = _bind$22[_];
                        const _bind$24 = _M0FP39stillfail5rules4lock6device(d, 0, c);
                        let _tmp$4;
                        if (_bind$24.$tag === 1) {
                          const _ok = _bind$24;
                          _tmp$4 = _ok._0;
                        } else {
                          return _bind$24;
                        }
                        const _tmp$5 = _tmp$4;
                        const _bind$25 = _M0FP39stillfail5rules4lock3add(s, new _M0TP39stillfail5rules4lock6Device(_tmp$5.id, _tmp$5.sub, _tmp$5.kind, _tmp$5.label, _tmp$5.sign_key, _tmp$5.endpoints, _tmp$5.exp, owner, true));
                        if (_bind$25.$tag === 1) {
                          const _ok = _bind$25;
                          _ok._0;
                        } else {
                          return _bind$25;
                        }
                        _tmp$3 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const _bind$24 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "passkeys"));
                    const _bind$25 = _bind$24.length;
                    let _tmp$4 = 0;
                    while (true) {
                      const _ = _tmp$4;
                      if (_ < _bind$25) {
                        const p = _bind$24[_];
                        const _bind$26 = _M0FP39stillfail5rules4lock7passkey(p, c);
                        let _bind$27;
                        if (_bind$26.$tag === 1) {
                          const _ok = _bind$26;
                          _bind$27 = _ok._0;
                        } else {
                          return _bind$26;
                        }
                        _M0FP39stillfail5rules4lock12add__passkey(s, new _M0TP39stillfail5rules4lock7Passkey(_bind$27.id, _bind$27.sub, _bind$27.key, _bind$27.label, true));
                        _tmp$4 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const _bind$26 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "stations"));
                    const _bind$27 = _bind$26.length;
                    let _tmp$5 = 0;
                    while (true) {
                      const _ = _tmp$5;
                      if (_ < _bind$27) {
                        const st = _bind$26[_];
                        const _bind$28 = _M0FP39stillfail5rules4lock7station(st);
                        let st$2;
                        if (_bind$28.$tag === 1) {
                          const _ok = _bind$28;
                          st$2 = _ok._0;
                        } else {
                          return _bind$28;
                        }
                        _M0MPB3Map3setGsRP39stillfail5rules4lock7StationE(_bind$17, st$2.key, st$2);
                        _tmp$5 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const _bind$28 = _M0FP39stillfail5rules4lock3arr(_M0FP39stillfail5rules4lock5field(b, "gateways"));
                    const _bind$29 = _bind$28.length;
                    let _tmp$6 = 0;
                    while (true) {
                      const _ = _tmp$6;
                      if (_ < _bind$29) {
                        const g = _bind$28[_];
                        if (_M0FP39stillfail5rules4lock6is__id(g)) {
                          const _p$5 = _M0FP39stillfail5rules4lock8text__of(g);
                          let _tmp$7;
                          if (_p$5 === undefined) {
                            _tmp$7 = $panic();
                          } else {
                            const _p$6 = _p$5;
                            _tmp$7 = _p$6;
                          }
                          _M0MPB3Map3setGsuE(_bind$19, _tmp$7, undefined);
                        }
                        _tmp$6 = _ + 1 | 0;
                        continue;
                      } else {
                        break;
                      }
                    }
                    const _bind$30 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "owner"));
                    let owns;
                    if (_bind$30 === undefined) {
                      owns = false;
                    } else {
                      const _Some$3 = _bind$30;
                      const _o = _Some$3;
                      const _bind$31 = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(_bind$7, _o);
                      if (_bind$31 === undefined) {
                        owns = false;
                      } else {
                        const _Some$4 = _bind$31;
                        const _m = _Some$4;
                        owns = _m.role === "owner";
                      }
                    }
                    if (!owns) {
                      const _bind$31 = _M0FP39stillfail5rules4lock6refuse("the genesis names its owner among its members");
                      if (_bind$31.$tag === 1) {
                        const _ok = _bind$31;
                        _ok._0;
                      } else {
                        return _bind$31;
                      }
                    }
                    const by = _M0FP39stillfail5rules4lock6signer(s, _M0FP39stillfail5rules4lock8sig__key(e), new _M0DTPC16option6OptionGdE4Some(_M0MPC16option6Option10unwrap__orGdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "at")), 1 / 0)));
                    const _bind$31 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "owner"));
                    let signed_by_owner;
                    if (by === undefined) {
                      signed_by_owner = false;
                    } else {
                      const _Some$3 = by;
                      const _by = _Some$3;
                      if (_bind$31 === undefined) {
                        signed_by_owner = false;
                      } else {
                        const _Some$4 = _bind$31;
                        const _o = _Some$4;
                        signed_by_owner = _by.sub === _o && c.method_table.method_1(c.self, _M0FP39stillfail5rules4lock7sig__of(e), hash, origins, _bind$3, _by.passkey);
                      }
                    }
                    if (!signed_by_owner) {
                      const _bind$32 = _M0FP39stillfail5rules4lock6refuse("the genesis is not signed by its owner");
                      if (_bind$32.$tag === 1) {
                        const _ok = _bind$32;
                        _ok._0;
                      } else {
                        return _bind$32;
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
function _M0FP39stillfail5rules4lock5applyN4needS1750(ok, why) {
  if (!ok) {
    return new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused(why));
  } else {
    return new _M0DTPC16result6ResultGuRP39stillfail5rules4lock9LockErrorE2Ok(undefined);
  }
}
function _M0FP39stillfail5rules4lock5apply(prev, e, now, c) {
  const v = e;
  if (prev.disabled) {
    const _bind = _M0FP39stillfail5rules4lock6refuse("the lock is turned off");
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _ok._0;
    } else {
      return _bind;
    }
  }
  if (_M0IP016_24default__implPB2Eq10not__equalGOdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "v")), _M0FP39stillfail5rules4lock5applyN6constrS1751) || _M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "ws")), prev.ws)) {
    const _bind = _M0FP39stillfail5rules4lock6refuse("an entry of another lock");
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _ok._0;
    } else {
      return _bind;
    }
  }
  if (_M0IP016_24default__implPB2Eq10not__equalGOdE(_M0FP39stillfail5rules4lock9safe__num(_M0FP39stillfail5rules4lock5field(v, "seq")), new _M0DTPC16option6OptionGdE4Some(prev.seq + 1)) || _M0IP016_24default__implPB2Eq10not__equalGOsE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "prev")), prev.head)) {
    const _bind = _M0FP39stillfail5rules4lock6refuse("the entry does not follow this lock's head");
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _ok._0;
    } else {
      return _bind;
    }
  }
  const _bind = _M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(v, "at"));
  if (_bind.$tag === 0) {
    const _bind$2 = _M0FP39stillfail5rules4lock6refuse("at is unix seconds");
    if (_bind$2.$tag === 1) {
      const _ok = _bind$2;
      _ok._0;
    } else {
      return _bind$2;
    }
  }
  const at = _M0MPC16option6Option6unwrapGdE(_M0FP39stillfail5rules4lock9safe__int(_M0FP39stillfail5rules4lock5field(v, "at")));
  const _bind$2 = _M0FP39stillfail5rules4lock11entry__hash(e, c);
  let hash;
  if (_bind$2.$tag === 1) {
    const _ok = _bind$2;
    hash = _ok._0;
  } else {
    return _bind$2;
  }
  const _bind$3 = _M0FP39stillfail5rules4lock6signer(prev, _M0FP39stillfail5rules4lock8sig__key(e), now);
  if (_bind$3 === undefined) {
    return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("not signed by a device or passkey in the lock"));
  } else {
    const _Some = _bind$3;
    const _by = _Some;
    if (!c.method_table.method_1(c.self, _M0FP39stillfail5rules4lock7sig__of(e), hash, prev.origins, prev.rp_id, _by.passkey)) {
      const _bind$4 = _M0FP39stillfail5rules4lock6refuse("signature invalid");
      if (_bind$4.$tag === 1) {
        const _ok = _bind$4;
        _ok._0;
      } else {
        return _bind$4;
      }
    }
    const s = new _M0TP39stillfail5rules4lock9LockState(prev.ws, prev.seq + 1, hash, prev.genesis, prev.origins, prev.rp_id, prev.cloud_keys, _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock6MemberE(prev.members), _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock6DeviceE(prev.devices), _M0FP39stillfail5rules4lock4copyGsRPB5ArrayGsEE(prev.sign_keys), _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock7PasskeyE(prev.passkeys), _M0FP39stillfail5rules4lock4copyGsuE(prev.signed), _M0FP39stillfail5rules4lock4copyGsRP39stillfail5rules4lock7StationE(prev.stations), _M0FP39stillfail5rules4lock4copyGsuE(prev.gateways), prev.disabled);
    let b;
    _L: {
      _L$2: {
        const _bind$4 = _M0FP39stillfail5rules4lock5field(v, "body");
        if (_bind$4 === undefined) {
          break _L$2;
        } else {
          const _Some$2 = _bind$4;
          const _x = _Some$2;
          if (_x.$tag === 0) {
            break _L$2;
          } else {
            b = _bind$4;
          }
        }
        break _L;
      }
      const _bind$4 = [];
      const _p = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind$4, 0, 0), undefined);
      b = new _M0DTPC14json4Json6Object(_p);
    }
    const who = _M0FP39stillfail5rules4lock11role__named(_by.role);
    const kind = _M0MPC16option6Option10unwrap__orGRPC14json4JsonE(_M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(v, "kind")), "");
    let out = s;
    switch (kind) {
      case "member": {
        const _bind$4 = _M0FP39stillfail5rules4lock6member(b);
        let m;
        if (_bind$4.$tag === 1) {
          const _ok = _bind$4;
          m = _ok._0;
        } else {
          return _bind$4;
        }
        const _bind$5 = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(s.members, m.sub);
        let was_owner;
        if (_bind$5 === undefined) {
          was_owner = false;
        } else {
          const _Some$2 = _bind$5;
          const _w = _Some$2;
          was_owner = _w.role === "owner";
        }
        const _bind$6 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change9MemberSet(was_owner, m.role === "owner")), _M0FP39stillfail5rules4role4rank(who) >= 2 ? "only owners make or change owners" : "only owners and admins change members");
        if (_bind$6.$tag === 1) {
          const _ok = _bind$6;
          _ok._0;
        } else {
          return _bind$6;
        }
        _M0MPB3Map3setGsRP39stillfail5rules4lock6MemberE(s.members, m.sub, m);
        const _bind$7 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4lock6owners(s) > 0, "a lock keeps an owner");
        if (_bind$7.$tag === 1) {
          const _ok = _bind$7;
          _ok._0;
        } else {
          return _bind$7;
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
                const _p = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(s.members, _sub);
                let _tmp;
                if (_p === undefined) {
                  _tmp = $panic();
                } else {
                  const _p$2 = _p;
                  _tmp = _p$2;
                }
                const _bind$8 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change12MemberRemove(_tmp.role === "owner")), "only owners and admins remove members, owners owners");
                if (_bind$8.$tag === 1) {
                  const _ok = _bind$8;
                  _ok._0;
                } else {
                  return _bind$8;
                }
                _M0MPB3Map6removeGsRP39stillfail5rules4lock6MemberE(s.members, _sub);
                const _bind$9 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4lock6owners(s) > 0, "a lock keeps an owner");
                if (_bind$9.$tag === 1) {
                  const _ok = _bind$9;
                  _ok._0;
                } else {
                  return _bind$9;
                }
                const _bind$10 = _M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB3Map4keysGsRPC14json4JsonE(s.devices));
                const _bind$11 = _bind$10.length;
                let _tmp$2 = 0;
                while (true) {
                  const _ = _tmp$2;
                  if (_ < _bind$11) {
                    const k = _bind$10[_];
                    const _p$2 = _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(s.devices, k);
                    let _tmp$3;
                    if (_p$2 === undefined) {
                      _tmp$3 = $panic();
                    } else {
                      const _p$3 = _p$2;
                      _tmp$3 = _p$3;
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
                const _bind$12 = _M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB3Map4keysGsRPC14json4JsonE(s.passkeys));
                const _bind$13 = _bind$12.length;
                let _tmp$3 = 0;
                while (true) {
                  const _ = _tmp$3;
                  if (_ < _bind$13) {
                    const k = _bind$12[_];
                    const _p$2 = _M0MPB3Map3getGsRP39stillfail5rules4lock7PasskeyE(s.passkeys, k);
                    let _tmp$4;
                    if (_p$2 === undefined) {
                      _tmp$4 = $panic();
                    } else {
                      const _p$3 = _p$2;
                      _tmp$4 = _p$3;
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
        const _bind$8 = _M0FP39stillfail5rules4lock6device(b, at, c);
        let d;
        if (_bind$8.$tag === 1) {
          const _ok = _bind$8;
          d = _ok._0;
        } else {
          return _bind$8;
        }
        const _bind$9 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change3Own(d.sub === _by.sub)), "members add only their own devices");
        if (_bind$9.$tag === 1) {
          const _ok = _bind$9;
          _ok._0;
        } else {
          return _bind$9;
        }
        const _bind$10 = _M0FP39stillfail5rules4lock3add(s, new _M0TP39stillfail5rules4lock6Device(d.id, d.sub, d.kind, d.label, d.sign_key, d.endpoints, d.exp, _by.sub, _M0FP39stillfail5rules4lock7own__of(prev, d.sub, _by, _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(prev.devices, d.id), d.sign_key)));
        if (_bind$10.$tag === 1) {
          const _ok = _bind$10;
          _ok._0;
        } else {
          return _bind$10;
        }
        break;
      }
      case "device.remove": {
        const _bind$11 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "id"));
        let d$2;
        if (_bind$11 === undefined) {
          d$2 = undefined;
        } else {
          const _Some$2 = _bind$11;
          const _id = _Some$2;
          d$2 = _M0MPB3Map3getGsRP39stillfail5rules4lock6DeviceE(s.devices, _id);
        }
        if (d$2 === undefined) {
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no such device"));
        } else {
          const _Some$2 = d$2;
          const _d = _Some$2;
          const _bind$12 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change3Own(_d.sub === _by.sub)), "members remove only their own devices");
          if (_bind$12.$tag === 1) {
            const _ok = _bind$12;
            _ok._0;
          } else {
            return _bind$12;
          }
          _M0MPB3Map6removeGsRP39stillfail5rules4lock6DeviceE(s.devices, _d.id);
        }
        break;
      }
      case "passkey": {
        const _bind$12 = _M0FP39stillfail5rules4lock7passkey(b, c);
        let p;
        if (_bind$12.$tag === 1) {
          const _ok = _bind$12;
          p = _ok._0;
        } else {
          return _bind$12;
        }
        const _bind$13 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0MPB3Map8containsGsRP39stillfail5rules4lock6MemberE(s.members, p.sub), "a passkey is a member's");
        if (_bind$13.$tag === 1) {
          const _ok = _bind$13;
          _ok._0;
        } else {
          return _bind$13;
        }
        const _bind$14 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change3Own(p.sub === _by.sub)), "members add only their own passkeys");
        if (_bind$14.$tag === 1) {
          const _ok = _bind$14;
          _ok._0;
        } else {
          return _bind$14;
        }
        _M0FP39stillfail5rules4lock12add__passkey(s, new _M0TP39stillfail5rules4lock7Passkey(p.id, p.sub, p.key, p.label, _M0FP39stillfail5rules4lock7own__of(prev, p.sub, _by, undefined, undefined)));
        break;
      }
      case "passkey.remove": {
        const _bind$15 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
        let p$2;
        if (_bind$15 === undefined) {
          p$2 = undefined;
        } else {
          const _Some$2 = _bind$15;
          const _k = _Some$2;
          p$2 = _M0MPB3Map3getGsRP39stillfail5rules4lock7PasskeyE(s.passkeys, _k);
        }
        if (p$2 === undefined) {
          return new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefused("no such passkey"));
        } else {
          const _Some$2 = p$2;
          const _p = _Some$2;
          const _bind$16 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, new _M0DTP39stillfail5rules4role6Change3Own(_p.sub === _by.sub)), "members remove only their own passkeys");
          if (_bind$16.$tag === 1) {
            const _ok = _bind$16;
            _ok._0;
          } else {
            return _bind$16;
          }
          _M0MPB3Map6removeGsRP39stillfail5rules4lock7PasskeyE(s.passkeys, _p.key);
        }
        break;
      }
      case "station": {
        const _bind$16 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change6Roster__), "only owners and admins add stations");
        if (_bind$16.$tag === 1) {
          const _ok = _bind$16;
          _ok._0;
        } else {
          return _bind$16;
        }
        const _bind$17 = _M0FP39stillfail5rules4lock7station(b);
        let st;
        if (_bind$17.$tag === 1) {
          const _ok = _bind$17;
          st = _ok._0;
        } else {
          return _bind$17;
        }
        _M0MPB3Map3setGsRP39stillfail5rules4lock7StationE(s.stations, st.key, st);
        break;
      }
      case "station.remove": {
        const _bind$18 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change6Roster__), "only owners and admins remove stations");
        if (_bind$18.$tag === 1) {
          const _ok = _bind$18;
          _ok._0;
        } else {
          return _bind$18;
        }
        const _bind$19 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
        if (_bind$19 === undefined) {
        } else {
          const _Some$2 = _bind$19;
          const _k = _Some$2;
          _M0MPB3Map6removeGsRP39stillfail5rules4lock7StationE(s.stations, _k);
        }
        break;
      }
      case "gateway": {
        const _bind$20 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change6Roster__) && _M0FP39stillfail5rules4lock6is__id(_M0FP39stillfail5rules4lock5field(b, "key")), "only owners and admins add gateways, by iroh id");
        if (_bind$20.$tag === 1) {
          const _ok = _bind$20;
          _ok._0;
        } else {
          return _bind$20;
        }
        const _tmp = s.gateways;
        const _p = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
        let _tmp$2;
        if (_p === undefined) {
          _tmp$2 = $panic();
        } else {
          const _p$2 = _p;
          _tmp$2 = _p$2;
        }
        _M0MPB3Map3setGsuE(_tmp, _tmp$2, undefined);
        break;
      }
      case "gateway.remove": {
        const _bind$21 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change6Roster__), "only owners and admins remove gateways");
        if (_bind$21.$tag === 1) {
          const _ok = _bind$21;
          _ok._0;
        } else {
          return _bind$21;
        }
        const _bind$22 = _M0FP39stillfail5rules4lock8text__of(_M0FP39stillfail5rules4lock5field(b, "key"));
        if (_bind$22 === undefined) {
        } else {
          const _Some$2 = _bind$22;
          const _k = _Some$2;
          _M0MPB3Map6removeGsuE(s.gateways, _k);
        }
        break;
      }
      case "cloud_keys": {
        let _tmp$3;
        if (_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change9CloudKeys__)) {
          const _bind$23 = _M0FP39stillfail5rules4lock5field(b, "keys");
          _tmp$3 = !(_bind$23 === undefined);
        } else {
          _tmp$3 = false;
        }
        const _bind$23 = _M0FP39stillfail5rules4lock5applyN4needS1750(_tmp$3, "only owners change the control plane's keys");
        if (_bind$23.$tag === 1) {
          const _ok = _bind$23;
          _ok._0;
        } else {
          return _bind$23;
        }
        const _p$2 = _M0FP39stillfail5rules4lock5field(b, "keys");
        let _tmp$4;
        if (_p$2 === undefined) {
          _tmp$4 = $panic();
        } else {
          const _p$3 = _p$2;
          _tmp$4 = _p$3;
        }
        out = new _M0TP39stillfail5rules4lock9LockState(s.ws, s.seq, s.head, s.genesis, s.origins, s.rp_id, _tmp$4, s.members, s.devices, s.sign_keys, s.passkeys, s.signed, s.stations, s.gateways, s.disabled);
        break;
      }
      case "disable": {
        const _bind$24 = _M0FP39stillfail5rules4lock5applyN4needS1750(_M0FP39stillfail5rules4role3may(who, _M0DTP39stillfail5rules4role6Change7Disable__), "only owners turn the lock off");
        if (_bind$24.$tag === 1) {
          const _ok = _bind$24;
          _ok._0;
        } else {
          return _bind$24;
        }
        out = new _M0TP39stillfail5rules4lock9LockState(s.ws, s.seq, s.head, s.genesis, s.origins, s.rp_id, s.cloud_keys, s.members, s.devices, s.sign_keys, s.passkeys, s.signed, s.stations, s.gateways, true);
        break;
      }
      default: {
        const _bind$25 = _M0FP39stillfail5rules4lock6refuse(`unknown entry kind ${_M0FP39stillfail5rules4lock10kind__text(_M0FP39stillfail5rules4lock5field(v, "kind"))}`);
        if (_bind$25.$tag === 1) {
          const _ok = _bind$25;
          _ok._0;
        } else {
          return _bind$25;
        }
      }
    }
    return _by.own ? new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(out) : new _M0DTPC16result6ResultGRP39stillfail5rules4lock9LockStateRP39stillfail5rules4lock9LockErrorE2Ok(new _M0TP39stillfail5rules4lock9LockState(prev.ws, prev.seq + 1, hash, prev.genesis, prev.origins, prev.rp_id, prev.cloud_keys, prev.members, prev.devices, prev.sign_keys, prev.passkeys, prev.signed, prev.stations, prev.gateways, prev.disabled));
  }
}
function _M0FP39stillfail5rules4lock4fold(entries, now, c) {
  if (entries.length === 0) {
    const _bind = _M0FP39stillfail5rules4lock6refuse("no lock");
    if (_bind.$tag === 1) {
      const _ok = _bind;
      _ok._0;
    } else {
      return _bind;
    }
  }
  const _bind = _M0FP39stillfail5rules4lock7genesis(_M0MPC15array5Array2atGRPC14json4JsonE(entries, 0), c);
  let s;
  if (_bind.$tag === 1) {
    const _ok = _bind;
    s = _ok._0;
  } else {
    return _bind;
  }
  const _bind$2 = entries.length;
  let _tmp = 1;
  while (true) {
    const i = _tmp;
    if (i < _bind$2) {
      const _bind$3 = _M0FP39stillfail5rules4lock5apply(s, _M0MPC15array5Array2atGRPC14json4JsonE(entries, i), now, c);
      let _tmp$2;
      if (_bind$3.$tag === 1) {
        const _ok = _bind$3;
        _tmp$2 = _ok._0;
      } else {
        return _bind$3;
      }
      s = _tmp$2;
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
    const _it = _M0MPB3Map5iter2GsRPC14json4JsonE(s.devices);
    while (true) {
      const _bind$3 = _M0MPB5Iter24nextGsRPC14json4JsonE(_it);
      if (_bind$3 === undefined) {
        break;
      } else {
        const _Some = _bind$3;
        const _x = _Some;
        const _x$2 = _x._1;
        const _bind$4 = _x$2.endpoints;
        if (_bind$4.$tag === 1) {
          const _Some$2 = _bind$4;
          const _es = _Some$2._0;
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
  if (_bind$3 === undefined) {
    return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("this device is not confirmed in the workspace's lock"));
  } else {
    const _Some = _bind$3;
    const _d = _Some;
    const _p = _d.sub;
    if (!(_p === sub)) {
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("this device is someone else's in the workspace's lock"));
    }
    const _bind$4 = _d.exp;
    if (_bind$4.$tag === 1) {
      const _Some$2 = _bind$4;
      const _exp = _Some$2._0;
      if (_exp <= now) {
        return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("this device's confirmation ran out"));
      }
    }
    const _bind$5 = _M0MPB3Map3getGsRP39stillfail5rules4lock6MemberE(s.members, _d.sub);
    if (_bind$5 === undefined) {
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE3Err(new _M0DTPC15error5Error46stillfail_2frules_2flock_2eLockError_2eRefusal("not a member in the workspace's lock"));
    } else {
      const _Some$2 = _bind$5;
      const _m = _Some$2;
      return new _M0DTPC16result6ResultGURP39stillfail5rules4lock6DevicesERP39stillfail5rules4lock9LockErrorE2Ok({ _0: _d, _1: _m.role });
    }
  }
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
      const xs = [];
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
          _M0MPC15array5Array4pushGUsRPC14json4JsonEE(xs, _tmp$2);
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
      const _bind = _xs.length;
      let _tmp = 0;
      while (true) {
        const _ = _tmp;
        if (_ < _bind) {
          const x = _xs[_];
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
      const _it = _M0MPB3Map5iter2GsRPC14json4JsonE(_m);
      while (true) {
        const _bind$2 = _M0MPB5Iter24nextGsRPC14json4JsonE(_it);
        if (_bind$2 === undefined) {
          break;
        } else {
          const _Some = _bind$2;
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
  const _p = new Array(origins.length);
  const _p$2 = origins.length;
  let _tmp$2 = 0;
  while (true) {
    const _p$3 = _tmp$2;
    if (_p$3 < _p$2) {
      const _p$4 = origins[_p$3];
      _p[_p$3] = new _M0DTPC14json4Json6String(_p$4);
      _tmp$2 = _p$3 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$3 = _p;
  return _M0FP39stillfail5rules2js14js__sig__valid(self, _tmp, hash, _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json5Array(_p$3)), rp_id, passkey);
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
function _M0FP39stillfail5rules2js11state__jsonN5pairsS1922(xs) {
  const _p = new Array(xs.length);
  const _p$2 = xs.length;
  let _tmp = 0;
  while (true) {
    const _p$3 = _tmp;
    if (_p$3 < _p$2) {
      const _p$4 = xs[_p$3];
      const _p$5 = _p$4._0;
      const _p$6 = [new _M0DTPC14json4Json6String(_p$5), _p$4._1];
      _p[_p$3] = new _M0DTPC14json4Json5Array(_p$6);
      _tmp = _p$3 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$3 = _p;
  return new _M0DTPC14json4Json5Array(_p$3);
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
  const _p$7 = new Array(_p$6.length);
  const _p$8 = _p$6.length;
  let _tmp$5 = 0;
  while (true) {
    const _p$9 = _tmp$5;
    if (_p$9 < _p$8) {
      const _p$10 = _p$6[_p$9];
      _p$7[_p$9] = new _M0DTPC14json4Json6String(_p$10);
      _tmp$5 = _p$9 + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p$9 = _p$7;
  const _tmp$6 = { _0: "origins", _1: new _M0DTPC14json4Json5Array(_p$9) };
  const _p$10 = s.rp_id;
  const _tmp$7 = { _0: "rp_id", _1: new _M0DTPC14json4Json6String(_p$10) };
  const _tmp$8 = { _0: "cloud_keys", _1: s.cloud_keys };
  const _tmp$9 = { _0: "members", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS1922(_M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB4Iter3mapGsRPC14json4JsonE(_M0MPB3Map4iterGsRPC14json4JsonE(s.members), (p) => {
    const _tmp$10 = p._0;
    const _p$11 = p._1.sub;
    const _tmp$11 = { _0: "sub", _1: new _M0DTPC14json4Json6String(_p$11) };
    const _p$12 = p._1.email;
    const _tmp$12 = { _0: "email", _1: new _M0DTPC14json4Json6String(_p$12) };
    const _p$13 = p._1.role;
    const _bind = [_tmp$11, _tmp$12, { _0: "role", _1: new _M0DTPC14json4Json6String(_p$13) }];
    const _p$14 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 3), undefined);
    return { _0: _tmp$10, _1: new _M0DTPC14json4Json6Object(_p$14) };
  }))) };
  const _tmp$10 = { _0: "devices", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS1922(_M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB4Iter3mapGsRPC14json4JsonE(_M0MPB3Map4iterGsRPC14json4JsonE(s.devices), (p) => {
    const _tmp$11 = p._0;
    const d = p._1;
    const _p$11 = d.id;
    const _tmp$12 = { _0: "id", _1: new _M0DTPC14json4Json6String(_p$11) };
    const _p$12 = d.sub;
    const _tmp$13 = { _0: "sub", _1: new _M0DTPC14json4Json6String(_p$12) };
    const _p$13 = d.kind;
    const _tmp$14 = { _0: "kind", _1: new _M0DTPC14json4Json6String(_p$13) };
    const _p$14 = d.label;
    const _tmp$15 = { _0: "label", _1: new _M0DTPC14json4Json6String(_p$14) };
    const _p$15 = d.own;
    const _bind = [_tmp$12, _tmp$13, _tmp$14, _tmp$15, { _0: "own", _1: _p$15 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ }];
    const m = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 5), undefined);
    const _bind$2 = d.sign_key;
    if (_bind$2 === undefined) {
    } else {
      const _Some = _bind$2;
      const _k = _Some;
      _M0MPB3Map3setGsRPC14json4JsonE(m, "sign_key", new _M0DTPC14json4Json6String(_k));
    }
    const _bind$3 = d.endpoints;
    if (_bind$3.$tag === 1) {
      const _Some = _bind$3;
      const _es = _Some._0;
      const _p$16 = new Array(_es.length);
      const _p$17 = _es.length;
      let _tmp$16 = 0;
      while (true) {
        const _p$18 = _tmp$16;
        if (_p$18 < _p$17) {
          const _p$19 = _es[_p$18];
          _p$16[_p$18] = new _M0DTPC14json4Json6String(_p$19);
          _tmp$16 = _p$18 + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      const _p$18 = _p$16;
      _M0MPB3Map3setGsRPC14json4JsonE(m, "endpoints", new _M0DTPC14json4Json5Array(_p$18));
    }
    const _bind$4 = d.exp;
    if (_bind$4.$tag === 1) {
      const _Some = _bind$4;
      const _x = _Some._0;
      const _p$16 = undefined;
      _M0MPB3Map3setGsRPC14json4JsonE(m, "exp", new _M0DTPC14json4Json6Number(_x, _p$16));
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
  const _tmp$11 = { _0: "signKeys", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS1922(_M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB4Iter3mapGsRPC14json4JsonE(_M0MPB3Map4iterGsRPB5ArrayGsEE(s.sign_keys), (p) => {
    const _tmp$12 = p._0;
    const _p$11 = p._1;
    const _p$12 = new Array(_p$11.length);
    const _p$13 = _p$11.length;
    let _tmp$13 = 0;
    while (true) {
      const _p$14 = _tmp$13;
      if (_p$14 < _p$13) {
        const _p$15 = _p$11[_p$14];
        _p$12[_p$14] = new _M0DTPC14json4Json6String(_p$15);
        _tmp$13 = _p$14 + 1 | 0;
        continue;
      } else {
        break;
      }
    }
    const _p$14 = _p$12;
    return { _0: _tmp$12, _1: new _M0DTPC14json4Json5Array(_p$14) };
  }))) };
  const _tmp$12 = { _0: "passkeys", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS1922(_M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB4Iter3mapGsRPC14json4JsonE(_M0MPB3Map4iterGsRPC14json4JsonE(s.passkeys), (p) => {
    const _tmp$13 = p._0;
    const _p$11 = p._1.id;
    const _tmp$14 = { _0: "id", _1: new _M0DTPC14json4Json6String(_p$11) };
    const _p$12 = p._1.sub;
    const _tmp$15 = { _0: "sub", _1: new _M0DTPC14json4Json6String(_p$12) };
    const _p$13 = p._1.key;
    const _tmp$16 = { _0: "key", _1: new _M0DTPC14json4Json6String(_p$13) };
    const _p$14 = p._1.label;
    const _tmp$17 = { _0: "label", _1: new _M0DTPC14json4Json6String(_p$14) };
    const _p$15 = p._1.own;
    const _bind = [_tmp$14, _tmp$15, _tmp$16, _tmp$17, { _0: "own", _1: _p$15 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ }];
    const _p$16 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 5), undefined);
    return { _0: _tmp$13, _1: new _M0DTPC14json4Json6Object(_p$16) };
  }))) };
  const _p$11 = _M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB4Iter3mapGsRPC14json4JsonE(_M0MPB3Map4keysGsuE(s.signed), (_hole51) => new _M0DTPC14json4Json6String(_hole51)));
  const _tmp$13 = { _0: "signed", _1: new _M0DTPC14json4Json5Array(_p$11) };
  const _tmp$14 = { _0: "stations", _1: _M0FP39stillfail5rules2js11state__jsonN5pairsS1922(_M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB4Iter3mapGsRPC14json4JsonE(_M0MPB3Map4iterGsRPC14json4JsonE(s.stations), (p) => {
    const _tmp$15 = p._0;
    const _p$12 = p._1.key;
    const _tmp$16 = { _0: "key", _1: new _M0DTPC14json4Json6String(_p$12) };
    const _p$13 = p._1.name;
    const _bind = [_tmp$16, { _0: "name", _1: new _M0DTPC14json4Json6String(_p$13) }];
    const _p$14 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 2), undefined);
    return { _0: _tmp$15, _1: new _M0DTPC14json4Json6Object(_p$14) };
  }))) };
  const _p$12 = _M0MPB4Iter9to__arrayGUsRPC14json4JsonEE(_M0MPB4Iter3mapGsRPC14json4JsonE(_M0MPB3Map4keysGsuE(s.gateways), (_hole54) => new _M0DTPC14json4Json6String(_hole54)));
  const _tmp$15 = { _0: "gateways", _1: new _M0DTPC14json4Json5Array(_p$12) };
  const _p$13 = s.disabled;
  const _bind = [_tmp, _tmp$2, _tmp$3, _tmp$4, _tmp$6, _tmp$7, _tmp$8, _tmp$9, _tmp$10, _tmp$11, _tmp$12, _tmp$13, _tmp$14, _tmp$15, { _0: "disabled", _1: _p$13 ? _M0DTPC14json4Json4True__ : _M0DTPC14json4Json5False__ }];
  const _p$14 = _M0MPB3Map3MapGsRPC14json4JsonE(new _M0TPB9ArrayViewGUsRPC14json4JsonEE(_bind, 0, 15), undefined);
  return new _M0DTPC14json4Json6Object(_p$14);
}
function _M0FP39stillfail5rules2js11entries__of(v) {
  const out = [];
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
      _M0MPC15array5Array4pushGUsRPC14json4JsonEE(out, _tmp$2);
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
  const out = [];
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
      _M0MPC15array5Array4pushGUsRPC14json4JsonEE(out, answer);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0FP39stillfail5rules2js6to__js(new _M0DTPC14json4Json5Array(out));
}
export { _M0FP39stillfail5rules2js13canonical__of as canonical_of, _M0FP39stillfail5rules2js15entry__text__of as entry_text_of, _M0FP39stillfail5rules2js11lower__role as lower_role, _M0FP39stillfail5rules2js8fold__js as fold_js, _M0FP39stillfail5rules2js9admit__js as admit_js }
