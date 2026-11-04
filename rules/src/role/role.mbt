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
