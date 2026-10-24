// Device-local storage for the existing accounts bytes, not an identity/schema migration.
// Header-only so the Apple core's existing compilation unit owns the implementation.
#pragma once
#include <functional>
#include <string>
#include <utility>

namespace mbui_ios_sessions {

enum class Status { ok, missing, duplicate, unavailable };
struct Read {
  Status status;
  std::string bytes;
};
// Nonsecret installation identity travels with this data container across sandbox-path relocation/backups.
// A fresh container gets a fresh identity: reinstall deliberately cannot recover orphaned device-local sessions.
struct InstallationBackend {
  std::function<Read()> get;
  std::function<Status(const std::string &)> create;  // atomic create-only; duplicate must not replace existing
  std::function<std::string()> random_uuid;
};
inline bool valid_installation(const std::string &value) {
  if (value.size() != 36) return false;
  for (size_t i = 0; i < value.size(); ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (value[i] != '-') return false;
    } else if (!((value[i] >= '0' && value[i] <= '9') || (value[i] >= 'a' && value[i] <= 'f'))) return false;
  }
  return true;
}
inline Read installation(InstallationBackend backend) {
  Read current = backend.get();
  if (current.status == Status::ok)
    return valid_installation(current.bytes) ? current : Read{Status::unavailable, {}};
  if (current.status != Status::missing) return {Status::unavailable, {}};
  std::string candidate = backend.random_uuid();
  if (!valid_installation(candidate)) return {Status::unavailable, {}};
  Status status = backend.create(candidate);
  if (status == Status::ok) return {Status::ok, std::move(candidate)};
  if (status != Status::duplicate) return {Status::unavailable, {}};
  // Another creator won. Read it rather than overwriting it or using our losing candidate.
  current = backend.get();
  return current.status == Status::ok && valid_installation(current.bytes) ? current : Read{Status::unavailable, {}};
}
inline std::string scoped_identity(const std::string &bundle, const std::string &installation_id) {
  return bundle + "\n" + installation_id;
}

struct Backend {
  std::function<Read()> get;
  std::function<Status(const std::string &)> update;
  std::function<Status(const std::string &)> add;
  std::function<Status()> erase;
  std::function<Read()> legacy_get;
  // Removing a nonexistent legacy file is success. Never writes a plaintext file.
  std::function<Status()> legacy_erase;
};
struct Answer {
  bool ok = false;
  bool has_bytes = false;
  std::string bytes;
};

inline bool main_bundle(const std::string &bundle, bool extension) {
  return !extension && (bundle == "fail.still.mbui" || bundle == "fail.still.mbui.debug");
}
inline bool handles(const std::string &op, const std::string &key) {
  return key == "accounts" && (op == "storage.get" || op == "storage.set" || op == "storage.delete");
}

// All methods are synchronous and confined to the ONE Hermes core thread. No background migrator and no share
// extension may use this store. A failure closes the mutation gate until another complete, successful get.
class Store {
 public:
  explicit Store(Backend backend) : backend_(std::move(backend)) {}

  Answer get() {
    ready_ = false;
    Read found = backend_.get();
    if (found.status == Status::ok) {
      // Keychain is authoritative, including after a crash between commit and legacy cleanup. Never read the
      // stale file here. Cleanup is explicit and must succeed before callers can mutate the loaded state.
      if (backend_.legacy_erase() != Status::ok) return {};
      ready_ = true;
      return {true, true, std::move(found.bytes)};
    }
    // Locked, inaccessible, missing entitlement, malformed result, etc. are NOT absence.
    if (found.status != Status::missing) return {};
    Read old = backend_.legacy_get();
    if (old.status == Status::missing) {
      ready_ = true;
      return {true, false, {}};
    }
    if (old.status != Status::ok) return {};
    // Migration uses add ONLY: a competing/newer writer must never be overwritten. Duplicate means error;
    // the next explicit get will load the winning Keychain bytes. No fallback to the legacy value on failure.
    if (backend_.add(old.bytes) != Status::ok) return {};
    if (backend_.legacy_erase() != Status::ok) return {};
    ready_ = true;
    return {true, true, std::move(old.bytes)};
  }

  Answer set(const std::string &bytes) {
    if (!ready_) return {};
    ready_ = false;
    // A successful initial get has already migrated/removed the legacy source (or proved it absent). Any file
    // here is stale, never the sole authoritative account. Clean BEFORE the mutation so cleanup errors cannot
    // report a failed set after committing a new identity. Failed migration still preserves its file and keeps
    // ready_ false, so it cannot reach this path. No other supported process writes the legacy accounts file.
    if (backend_.legacy_erase() != Status::ok) return {};
    Status status = backend_.update(bytes);
    if (status == Status::missing) status = backend_.add(bytes);
    if (status != Status::ok) return {};
    ready_ = true;
    return {true, false, {}};
  }

  Answer erase() {
    if (!ready_) return {};
    ready_ = false;
    // Remove the resurrection source BEFORE deleting the authoritative item. On cleanup failure Keychain stays;
    // on Keychain deletion failure it stays too. Never return false success or leave stale-file-only credentials.
    if (backend_.legacy_erase() != Status::ok) return {};
    Status status = backend_.erase();
    if (status != Status::ok && status != Status::missing) return {};
    ready_ = true;
    return {true, false, {}};
  }

 private:
  Backend backend_;
  bool ready_ = false;
};
}  // namespace mbui_ios_sessions
