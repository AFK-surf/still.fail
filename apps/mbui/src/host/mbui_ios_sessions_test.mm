// Standalone deterministic host contract tests: only injectable in-memory callbacks, NO SecItem calls.
// From repository root (macOS, no simulator):
// clang++ -std=c++17 -fobjc-arc -framework Foundation -framework Security \
//   apps/mbui/src/host/mbui_ios_sessions_test.mm -o /tmp/mbui-ios-sessions-test && /tmp/mbui-ios-sessions-test
#include "mbui_ios_sessions.h"
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <vector>
using namespace mbui_ios_sessions;

#define CHECK(condition) do { if (!(condition)) { \
  std::fprintf(stderr, "session contract failed at line %d: %s\n", __LINE__, #condition); std::abort(); \
} } while (false)

struct Fake {
  std::optional<std::string> keychain;
  std::optional<std::string> legacy;
  Status get_status = Status::ok, legacy_status = Status::ok;
  Status update_status = Status::ok, add_status = Status::ok, delete_status = Status::ok, cleanup_status = Status::ok;
  bool race_add = false;
  std::vector<std::string> calls;

  Backend backend() {
    return {
      [this]() -> Read {
        calls.push_back("get");
        if (get_status != Status::ok) return {get_status, {}};
        return keychain ? Read{Status::ok, *keychain} : Read{Status::missing, {}};
      },
      [this](const std::string &value) {
        calls.push_back("update");
        if (update_status != Status::ok) return update_status;
        if (!keychain) return Status::missing;
        keychain = value;
        return Status::ok;
      },
      [this](const std::string &value) {
        calls.push_back("add");
        if (race_add) keychain = "concurrent-winner";
        if (keychain) return Status::duplicate;
        if (add_status != Status::ok) return add_status;
        keychain = value;
        return Status::ok;
      },
      [this]() {
        calls.push_back("delete");
        if (delete_status != Status::ok) return delete_status;
        if (!keychain) return Status::missing;
        keychain.reset();
        return Status::ok;
      },
      [this]() -> Read {
        calls.push_back("legacy-get");
        if (legacy_status != Status::ok) return {legacy_status, {}};
        return legacy ? Read{Status::ok, *legacy} : Read{Status::missing, {}};
      },
      [this]() {
        calls.push_back("cleanup");
        if (cleanup_status != Status::ok) return cleanup_status;
        legacy.reset();
        return Status::ok;
      }
    };
  }
  void expect(std::initializer_list<const char *> names) {
    std::vector<std::string> wanted;
    for (auto name : names) wanted.emplace_back(name);
    CHECK(calls == wanted);
    calls.clear();
  }
};

struct FakeInstallation {
  std::optional<std::string> file;
  std::string generated = "01234567-89ab-4cde-8fab-0123456789ab";
  std::optional<std::string> concurrent_winner;
  Status read_status = Status::ok, create_status = Status::ok;
  int reads = 0, creates = 0, randoms = 0;
  InstallationBackend backend() {
    return {
      [this]() -> Read {
        ++reads;
        if (read_status != Status::ok) return {read_status, {}};
        return file ? Read{Status::ok, *file} : Read{Status::missing, {}};
      },
      [this](const std::string &value) {
        ++creates;
        if (concurrent_winner) file = concurrent_winner;
        if (file) return Status::duplicate;
        if (create_status != Status::ok) return create_status;
        file = value;
        return Status::ok;
      },
      [this]() { ++randoms; return generated; }
    };
  }
};

static void installation_contracts() {
  const std::string first = "01234567-89ab-4cde-8fab-0123456789ab";
  const std::string second = "fedcba98-7654-4321-8abc-fedcba987654";
  FakeInstallation original;
  Read a = installation(original.backend());
  CHECK(a.status == Status::ok && a.bytes == first && original.file == first);
  CHECK(original.reads == 1 && original.creates == 1 && original.randoms == 1);
  // Relocation/restore copies the container file, not its old absolute sandbox path. Namespace stays identical.
  FakeInstallation relocated;
  relocated.file = original.file; relocated.generated = second;
  Read b = installation(relocated.backend());
  CHECK(b.status == Status::ok && b.bytes == a.bytes && relocated.creates == 0 && relocated.randoms == 0);
  CHECK(scoped_identity("fail.still.mbui", a.bytes) == scoped_identity("fail.still.mbui", b.bytes));
  CHECK(scoped_identity("fail.still.mbui", a.bytes) != scoped_identity("fail.still.mbui.debug", a.bytes));
  // Reinstall with a NEW container gets a NEW nonsecret installation UUID; no search of prior Keychain scopes.
  FakeInstallation reinstalled; reinstalled.generated = second;
  Read c = installation(reinstalled.backend());
  CHECK(c.status == Status::ok && c.bytes == second && c.bytes != a.bytes);
  CHECK(scoped_identity("fail.still.mbui", c.bytes) != scoped_identity("fail.still.mbui", a.bytes));
  {
    FakeInstallation corrupt; corrupt.file = "not-a-valid-installation";
    CHECK(installation(corrupt.backend()).status == Status::unavailable);
    CHECK(corrupt.creates == 0 && corrupt.randoms == 0 && corrupt.file == "not-a-valid-installation");
  }
  {
    FakeInstallation unreadable; unreadable.file = first; unreadable.read_status = Status::unavailable;
    CHECK(installation(unreadable.backend()).status == Status::unavailable);
    CHECK(unreadable.creates == 0 && unreadable.randoms == 0);
    unreadable.read_status = Status::ok;
    Read recovered = installation(unreadable.backend());
    CHECK(recovered.status == Status::ok && recovered.bytes == first);
    CHECK(unreadable.creates == 0 && unreadable.randoms == 0);
  }
  {
    FakeInstallation failed; failed.create_status = Status::unavailable;
    CHECK(installation(failed.backend()).status == Status::unavailable && !failed.file);
  }
  {
    FakeInstallation race; race.concurrent_winner = second;
    Read winner = installation(race.backend());
    CHECK(winner.status == Status::ok && winner.bytes == second && race.file == second);
    CHECK(race.reads == 2 && race.creates == 1 && race.randoms == 1);
  }
  {
    FakeInstallation race; race.concurrent_winner = "corrupt";
    CHECK(installation(race.backend()).status == Status::unavailable && race.file == "corrupt");
    CHECK(race.creates == 1); // duplicate/corrupt never becomes overwrite
  }
  {
    FakeInstallation bad_random; bad_random.generated = "";
    CHECK(installation(bad_random.backend()).status == Status::unavailable && bad_random.creates == 0);
  }
}

int main() {
  installation_contracts();
  CHECK(main_bundle("fail.still.mbui", false));
  CHECK(main_bundle("fail.still.mbui.debug", false));
  CHECK(!main_bundle("fail.still.mbui.share", true));
  CHECK(!main_bundle("fail.still.mbui.debug.share", false));
  CHECK(!main_bundle("fail.still.mbui", true));
  CHECK(!main_bundle("fail.still.mbui.other", false));
  CHECK(handles("storage.get", "accounts") && handles("storage.set", "accounts") && handles("storage.delete", "accounts"));
  CHECK(!handles("secure.get", "accounts") && !handles("storage.get", "accounts/") && !handles("storage.get", "Accounts"));
  {
    Fake f; Store s(f.backend());
    CHECK(!s.set("blocked").ok && !s.erase().ok);
    f.expect({});
    Answer a = s.get();
    CHECK(a.ok && !a.has_bytes);
    f.expect({"get", "legacy-get"});
    CHECK(s.set("new").ok && f.keychain == "new");
    f.expect({"cleanup", "update", "add"});
  }
  {
    Fake f; f.legacy = "old"; f.get_status = Status::unavailable; Store s(f.backend());
    CHECK(!s.get().ok && !s.set("new").ok && !s.erase().ok);
    CHECK(f.legacy == "old" && !f.keychain);
    f.expect({"get"}); // unavailable is NEVER none or permission to inspect the legacy file
  }
  {
    Fake f; f.legacy_status = Status::unavailable; Store s(f.backend());
    CHECK(!s.get().ok && !s.set("new").ok && !s.erase().ok);
    f.expect({"get", "legacy-get"});
  }
  {
    Fake f;
    const char raw[] = " \n{\"fixture\":true}\0\xff";
    const std::string verbatim(raw, sizeof(raw) - 1);
    f.legacy = verbatim; Store s(f.backend());
    Answer a = s.get();
    CHECK(a.ok && a.has_bytes && a.bytes == verbatim && f.keychain == verbatim && !f.legacy);
    f.expect({"get", "legacy-get", "add", "cleanup"}); // Keychain commit BEFORE legacy unlink
  }
  {
    Fake f; f.legacy = "old"; f.add_status = Status::unavailable; Store s(f.backend());
    CHECK(!s.get().ok && f.legacy == "old" && !f.keychain);
    CHECK(!s.set("new").ok && !s.erase().ok);
    f.expect({"get", "legacy-get", "add"});
  }
  {
    Fake f; f.legacy = "old"; f.race_add = true; Store s(f.backend());
    CHECK(!s.get().ok && f.keychain == "concurrent-winner" && f.legacy == "old");
    CHECK(!s.set("clobber").ok);
    f.expect({"get", "legacy-get", "add"}); // duplicate never becomes update/delete/retry
    Answer a = s.get();
    CHECK(a.ok && a.bytes == "concurrent-winner" && !f.legacy);
    f.expect({"get", "cleanup"});
  }
  {
    Fake f; f.keychain = "new-after-crash"; f.legacy = "stale"; Store restarted(f.backend());
    Answer a = restarted.get();
    CHECK(a.ok && a.bytes == "new-after-crash" && !f.legacy);
    f.expect({"get", "cleanup"}); // no legacy read; no re-add of stale bytes
  }
  {
    Fake f; f.legacy = "old"; f.cleanup_status = Status::unavailable; Store s(f.backend());
    CHECK(!s.get().ok && f.keychain == "old" && f.legacy == "old");
    CHECK(!s.set("new").ok && !s.erase().ok);
    f.expect({"get", "legacy-get", "add", "cleanup"});
    // Model recovery after a post-commit cleanup error/crash, with a newer authoritative value.
    f.keychain = "newer"; f.cleanup_status = Status::ok;
    Answer a = s.get(); CHECK(a.ok && a.bytes == "newer" && !f.legacy);
    f.expect({"get", "cleanup"});
  }
  {
    Fake f; f.keychain = "account-before"; Store s(f.backend());
    CHECK(s.get().ok); f.expect({"get", "cleanup"});
    f.update_status = Status::unavailable;
    CHECK(!s.set("replacement").ok && f.keychain == "account-before" && !f.legacy);
    CHECK(!s.set("again").ok && !s.erase().ok);
    f.expect({"cleanup", "update"}); // failed update preserves authoritative account, never delete-before-add
  }
  {
    Fake f; Store s(f.backend()); CHECK(s.get().ok); f.calls.clear();
    f.add_status = Status::unavailable;
    CHECK(!s.set("new").ok && !f.keychain && !f.legacy);
    CHECK(!s.erase().ok); f.expect({"cleanup", "update", "add"});
  }
  {
    Fake f; Store s(f.backend()); CHECK(s.get().ok); f.calls.clear();
    f.race_add = true; f.legacy = "stale";
    CHECK(!s.set("loser").ok && f.keychain == "concurrent-winner" && !f.legacy);
    CHECK(!s.set("clobber").ok); f.expect({"cleanup", "update", "add"});
  }
  {
    Fake f; f.keychain = "original"; Store s(f.backend()); CHECK(s.get().ok); f.calls.clear();
    f.get_status = Status::unavailable;
    CHECK(!s.get().ok && !s.erase().ok && !s.set("new").ok && f.keychain == "original");
    f.expect({"get"}); // even after an earlier successful read, a later read error closes the gate
    f.get_status = Status::ok; CHECK(s.get().ok); f.calls.clear();
    f.legacy = "stale"; CHECK(s.set("updated").ok && f.keychain == "updated" && !f.legacy);
    f.expect({"cleanup", "update"});
    f.keychain.reset(); // genuine later absence must not resurrect the stale file
    Answer a = s.get(); CHECK(a.ok && !a.has_bytes); f.expect({"get", "legacy-get"});
  }
  {
    Fake f; f.keychain = "original"; Store s(f.backend()); CHECK(s.get().ok); f.calls.clear();
    f.legacy = "stale"; f.cleanup_status = Status::unavailable;
    CHECK(!s.set("uncommitted").ok && f.keychain == "original" && f.legacy == "stale");
    CHECK(!s.set("blocked").ok && !s.erase().ok); f.expect({"cleanup"});
    // Recovery must reload the unchanged authoritative account before another mutation is allowed.
    f.cleanup_status = Status::ok;
    Answer a = s.get(); CHECK(a.ok && a.bytes == "original" && !f.legacy);
    f.expect({"get", "cleanup"});
    CHECK(s.set("committed").ok && f.keychain == "committed");
    f.expect({"cleanup", "update"});
  }
  {
    Fake f; f.keychain = "original"; Store s(f.backend()); CHECK(s.get().ok); f.calls.clear();
    f.legacy = "stale"; f.cleanup_status = Status::unavailable;
    CHECK(!s.erase().ok && f.keychain == "original" && f.legacy == "stale");
    f.expect({"cleanup"}); // do not delete the authority while a resurrection source remains
  }
  {
    Fake f; f.keychain = "original"; Store s(f.backend()); CHECK(s.get().ok); f.calls.clear();
    f.delete_status = Status::unavailable;
    CHECK(!s.erase().ok && f.keychain == "original");
    CHECK(!s.erase().ok && !s.set("new").ok); f.expect({"cleanup", "delete"});
  }
  {
    Fake f; f.keychain = "original"; Store s(f.backend()); CHECK(s.get().ok); f.calls.clear();
    f.legacy = "stale";
    CHECK(s.erase().ok && !f.keychain && !f.legacy); f.expect({"cleanup", "delete"});
    Answer a = s.get(); CHECK(a.ok && !a.has_bytes); f.calls.clear();
    CHECK(s.erase().ok); f.expect({"cleanup", "delete"}); // genuine not-found delete is idempotent
  }
  {
    Fake f; f.keychain = std::string(); Store s(f.backend());
    Answer a = s.get(); CHECK(a.ok && a.has_bytes && a.bytes.empty());
    CHECK(s.set(std::string("a\0b", 3)).ok && f.keychain->size() == 3);
  }
  std::puts("iOS sessions fake-backend contracts passed");
}
