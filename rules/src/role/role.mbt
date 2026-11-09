// Who may do what in a workspace's lock (station/src/cloud/lock.ts `apply`'s checks, `lowerRole`), with what is proved
// of it (role.mbtp): the control plane may take rights away, never give them; only owners and admins manage; only
// owners touch owners, the control plane's keys, and the lock's end; a member only their own devices and passkeys.

///|
pub(all) enum Role {
  Viewer
  Member
  Admin
  Owner
}

///|
#proof_pure
pub fn rank(r : Role) -> Int {
  match r {
    Viewer => 0
    Member => 1
    Admin => 2
    Owner => 3
  }
}

///|
/// The lower of two roles: the lock's and the credential's (the control plane may take rights away, never give them).
pub fn lower(a : Role, b : Role) -> Role where {
  proof_ensure: result => lower_post(a, b, result),
} {
  if rank(a) <= rank(b) {
    a
  } else {
    b
  }
}

///|
/// A change an entry makes, as far as who may sign it goes.
pub(all) enum Change {
  /// a member made or changed: whether they were an owner, whether they become one
  MemberSet(Bool, Bool)
  /// a member taken out: whether they are an owner
  MemberRemove(Bool)
  /// a device or a passkey added or taken out: whether it is the signer's own
  Own(Bool)
  /// a station or a gateway added or taken out
  Roster
  /// the control plane's keys changed
  CloudKeys
  /// the lock turned off
  Disable
}

///|
/// Whether a member of role `who` may sign `c`.
pub fn may(who : Role, c : Change) -> Bool where {
  proof_ensure: result => may_post(who, c, result),
} {
  let managing = rank(who) >= 2
  let owning = rank(who) == 3
  match c {
    MemberSet(was, becomes) => managing && (owning || (!was && !becomes))
    MemberRemove(was) => managing && (owning || !was)
    Own(mine) => managing || mine
    Roster => managing
    CloudKeys => owning
    Disable => owning
  }
}

///|
/// Whether a device or passkey put in the lock under a person's name is their own (station/src/cloud/lock.ts
/// `ownOf`), the one whose signatures count: put in by them (`by_them`), or the same device as it stood, own and with
/// its signing key (`kept`), or put in by an owner or admin (`who`) while the person had none of their own (`had_own`:
/// their first, approved face to face). Proved: an owner or admin cannot make one of their own for someone who has one.
pub fn own_device(by_them : Bool, kept : Bool, who : Role, had_own : Bool) -> Bool where {
  proof_ensure: result => own_post(by_them, kept, who, had_own, result),
} {
  if by_them {
    true
  } else if kept {
    true
  } else if had_own {
    false
  } else {
    rank(who) >= 2
  }
}

///|
#proof_pure
pub fn one_if(b : Bool) -> Int {
  if b {
    1
  } else {
    0
  }
}

///|
/// Whether a lock with `owners` owners keeps one when a member who was an owner (`was`) is made one or not
/// (`becomes`; taken out: not). Proved: it does exactly when one is left.
pub fn keeps_owner(owners : Int, was : Bool, becomes : Bool) -> Bool where {
  proof_require: owners >= one_if(was),
  proof_ensure: result => keeps_post(owners, was, becomes, result),
} {
  if becomes {
    true
  } else if was {
    owners >= 2
  } else {
    owners >= 1
  }
}

///|
/// Whether an entry the lock takes changes it: only when its signer's device or passkey is their own (one someone
/// else put in under their name stays in the chain and changes nothing).
pub fn takes_effect(own : Bool) -> Bool where {
  proof_ensure: result => effect_post(own, result),
} {
  if own {
    true
  } else {
    false
  }
}

///|
/// Whether an app device holding the key (`holds`) takes a signer's place over the one found so far (`own_found`: it
/// is its person's own; a key put in again under someone else's device does not take its signatures away): it signs
/// still (`live`) and its person is a member (`member`). Proved: an own signer found is never replaced, and no device
/// that ran out signs.
pub fn replaces(own_found : Bool, holds : Bool, live : Bool, member : Bool) -> Bool where {
  proof_ensure: result => replaces_post(own_found, holds, live, member, result),
} {
  if own_found {
    false
  } else if !holds {
    false
  } else if !live {
    false
  } else {
    member
  }
}

///|
/// Why a connection is turned away, or not.
pub(all) enum Admission {
  Admitted
  /// no device in the lock is it
  Unknown
  /// the device is someone else's
  Others
  /// the device's confirmation ran out
  RanOut
  /// its person is no member
  NoMember
}

///|
/// Whether a connection is let in (`found`: a device in the lock is it; `theirs`: that device is the connecting
/// person's; `live`: it has not run out; `member`: its person is in the lock), and if not, the first reason why.
/// Proved: let in exactly when all four hold.
pub fn admission(found : Bool, theirs : Bool, live : Bool, member : Bool) -> Admission where {
  proof_ensure: result => admission_post(found, theirs, live, member, result),
} {
  if !found {
    Unknown
  } else if !theirs {
    Others
  } else if !live {
    RanOut
  } else if !member {
    NoMember
  } else {
    Admitted
  }
}

// ── vaults (station/src/vault/crypto.ts) ──────────────────────────────────────────────────────────────────────────

///|
/// Whether a lock device's signatures count for a vault (`signerOf`): an app device (`app`) holding the key (`holds`),
/// its person's own (`own`), and its person a member of the lock (`member`).
pub fn device_signs(app : Bool, holds : Bool, own : Bool, member : Bool) -> Bool where {
  proof_ensure: result => device_signs_post(app, holds, own, member, result),
} {
  if !app {
    false
  } else if !holds {
    false
  } else if !own {
    false
  } else {
    member
  }
}

///|
/// Whether a version is signed by whom it must be (`found`: a lock device whose signatures count signed it; `whose`:
/// that device's person is the one it must be, a vault's owner, an item's vault's member).
pub fn signed_by(found : Bool, whose : Bool) -> Bool where {
  proof_ensure: result => signed_by_post(found, whose, result),
} {
  if found {
    whose
  } else {
    false
  }
}

///|
/// Whether a box certificate's device counts (`certOk`): its person's own (`own`), or, reading a version already held
/// (`ever`), one that was. Proved: a device someone else put in under a person's name never gets new vault keys.
pub fn cert_device_ok(own : Bool, ever : Bool) -> Bool where {
  proof_ensure: result => cert_device_post(own, ever, result),
} {
  if own {
    true
  } else {
    ever
  }
}

///|
/// Whether a box certificate is signed with the key it must be: its device's now (`current`), or, reading a version
/// already held (`ever`), one the device has had (`had`).
pub fn cert_key_ok(current : Bool, ever : Bool, had : Bool) -> Bool where {
  proof_ensure: result => cert_key_post(current, ever, had, result),
} {
  if current {
    true
  } else if ever {
    had
  } else {
    false
  }
}

///|
/// Whether a vault's key may go to a lock device: none went to it already in this version (`seen`) and it is one of a
/// vault member's (`member`).
pub fn key_ok(seen : Bool, member : Bool) -> Bool where {
  proof_ensure: result => key_post(seen, member, result),
} {
  if seen {
    false
  } else {
    member
  }
}

///|
/// Whether a `person` entry binds a member to a lock of their own: signed by that member (`mine`), from a device or
/// passkey that is their own (`own`). Proved: exactly then. A manager's signature binds no one, so no one but the person
/// says which lock is theirs.
pub fn binds(mine : Bool, own : Bool) -> Bool where {
  proof_ensure: result => binds_post(mine, own, result),
} {
  if !mine {
    false
  } else {
    own
  }
}

///|
/// Whether an entry of a person's own lock may change it: signed by a key on it (`held`), and not taking away its last
/// (`lone`: a lock with no device is no one's). Proved: exactly then.
pub fn person_changes(held : Bool, lone : Bool) -> Bool where {
  proof_ensure: result => person_changes_post(held, lone, result),
} {
  if !held {
    false
  } else {
    !lone
  }
}

///|
/// Whether a connection is let in by a person's own lock: the lock it brought is the one its member bound (`pinned`),
/// the device's proof holds for its endpoint (`proved`), and the device is on that lock (`held`). Proved: exactly then.
pub fn person_admits(pinned : Bool, proved : Bool, held : Bool) -> Bool where {
  proof_ensure: result => person_admits_post(pinned, proved, held, result),
} {
  if !pinned {
    false
  } else if !proved {
    false
  } else {
    held
  }
}
