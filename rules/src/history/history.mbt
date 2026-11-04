// How a record's versions may follow one another (the lock's entries, a vault's and an item's versions in
// station/src/vault/crypto.ts), with what is proved of it (history.mbtp): a version follows the one held by one, a copy
// from another station is only ever later; a vault's key changes whenever a member or device is taken out, and never
// goes back; what is deleted stays deleted; an item is written under its vault's key; a device whose time ran out is
// not let in.

///|
/// Whether a version numbered `next` may follow the one held, `held` (`copy`: brought from another station, any later
/// one).
pub fn follows(copy : Bool, held : Int64, next : Int64) -> Bool where {
  proof_require: held >= 0L && held < 9007199254740991L,
  proof_ensure: result => follows_post(copy, held, next, result),
} {
  if copy {
    next > held
  } else {
    next == held + 1L
  }
}

///|
/// Whether a vault's next version may have key epoch `next` after `prev` (`gone`: it takes out a member or a device).
pub fn epoch_ok(gone : Bool, prev : Int64, next : Int64) -> Bool where {
  proof_ensure: result => epoch_post(gone, prev, next, result),
} {
  if next < prev {
    false
  } else if gone && next == prev {
    false
  } else {
    true
  }
}

///|
/// Whether a version deleted or not (`now`) may follow one that was (`was`).
pub fn deletion_ok(was : Bool, now : Bool) -> Bool where {
  proof_ensure: result => deletion_post(was, now, result),
} {
  !was || now
}

///|
/// Whether an item's version may be written under key epoch `epoch` of a vault at `vault` (`deleted`: it deletes the
/// item; `copy`: brought from another station, written under an earlier key maybe).
pub fn item_epoch_ok(deleted : Bool, copy : Bool, epoch : Int64, vault : Int64) -> Bool where {
  proof_ensure: result => item_epoch_post(deleted, copy, epoch, vault, result),
} {
  if epoch > vault {
    false
  } else if !deleted && !copy && epoch != vault {
    false
  } else {
    true
  }
}

///|
/// Whether a device lasting until `exp` (`lasts`: it has an end) is let in at `now`.
pub fn unexpired(lasts : Bool, exp : Int64, now : Int64) -> Bool where {
  proof_ensure: result => unexpired_post(lasts, exp, now, result),
} {
  !lasts || exp > now
}
