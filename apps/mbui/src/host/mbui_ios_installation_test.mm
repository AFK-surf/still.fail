// Bounded production-filesystem contract test: fresh mkdtemp paths ONLY, no app paths or Keychain operations.
// From repository root (macOS, no simulator):
// clang++ -std=c++17 -fobjc-arc -framework Foundation -framework Security \
//   apps/mbui/src/host/mbui_ios_installation_test.mm -o /tmp/mbui-ios-installation-test && /tmp/mbui-ios-installation-test
// The test-only guard exposes actual installation read/create code, NOT the SecItem adapter. No SDK macro spoofing.
#define MBUI_IOS_INSTALLATION_FILESYSTEM_TEST 1
#include "mbui_ios_sessions_apple.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
using namespace mbui_ios_sessions;

#define CHECK(condition) do { if (!(condition)) { \
  std::fprintf(stderr, "installation filesystem contract failed at line %d: %s\n", __LINE__, #condition); std::abort(); \
} } while (false)

static NSString *ns(const std::string &path) { return [NSString stringWithUTF8String:path.c_str()]; }
static std::string file_at(const std::string &dir) { return dir + "/.mbui-sessions-installation"; }

struct Scratch {
  std::string root;
  Scratch() {
    std::string pattern = std::string(NSTemporaryDirectory().fileSystemRepresentation) + "mbui-installation-test.XXXXXX";
    std::vector<char> buffer(pattern.begin(), pattern.end());
    buffer.push_back('\0');
    char *created = mkdtemp(buffer.data());
    CHECK(created != nullptr);
    root = created;
  }
  std::string dir(const char *name) {
    std::string path = root + "/" + name;
    CHECK(mkdir(path.c_str(), 0700) == 0);
    return path;
  }
  ~Scratch() {
    // This path was created by this test's mkdtemp. Never remove anything outside the fresh scratch tree.
    CHECK([[NSFileManager defaultManager] removeItemAtPath:ns(root) error:nil]);
  }
};

struct DirectoryFD {
  int value;
  explicit DirectoryFD(const std::string &path) {
    value = open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    CHECK(value >= 0);
  }
  ~DirectoryFD() { CHECK(close(value) == 0); }
};

static void seed(const std::string &dir, const std::string &bytes) {
  int fd = open(file_at(dir).c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  CHECK(fd >= 0);
  CHECK(fchmod(fd, 0600) == 0);
  size_t written = 0;
  while (written < bytes.size()) {
    ssize_t count = write(fd, bytes.data() + written, bytes.size() - written);
    if (count < 0 && errno == EINTR) continue;
    CHECK(count > 0);
    written += size_t(count);
  }
  CHECK(fsync(fd) == 0);
  CHECK(close(fd) == 0);
}

static std::string contents(const std::string &path) {
  NSData *data = [NSData dataWithContentsOfFile:ns(path)];
  CHECK(data != nil);
  return data.length ? std::string(static_cast<const char *>(data.bytes), data.length) : std::string();
}

static void only_identity_file(const std::string &dir) {
  NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ns(dir) error:nil];
  CHECK(names != nil && names.count == 1);
  CHECK([names.firstObject isEqualToString:@".mbui-sessions-installation"]);
}

int main() {
  @autoreleasepool {
    Scratch scratch;
    const std::string known = "01234567-89ab-4cde-8fab-0123456789ab";
    const std::string other = "fedcba98-7654-4321-8abc-fedcba987654";
    std::string original = scratch.dir("original");
    {
      DirectoryFD fd(original);
      CHECK(apple_installation_read(fd.value).status == Status::missing);
      CHECK(apple_installation_create(fd.value, known) == Status::ok);
      Read a = apple_installation_read(fd.value);
      CHECK(a.status == Status::ok && a.bytes == known);
      CHECK(apple_installation_create(fd.value, other) == Status::duplicate);
      Read winner = apple_installation_read(fd.value);
      CHECK(winner.status == Status::ok && winner.bytes == known);
    }
    Read reread = apple_installation(ns(original));
    CHECK(reread.status == Status::ok && reread.bytes == known);
    CHECK(contents(file_at(original)) == known);
    struct stat st{};
    CHECK(lstat(file_at(original).c_str(), &st) == 0);
    CHECK(S_ISREG(st.st_mode) && (st.st_mode & 0777) == 0600 && st.st_size == 36 && st.st_uid == getuid());
    only_identity_file(original); // no temp file left by successful/duplicate publication

    std::string relocated = scratch.root + "/relocated";
    CHECK(rename(original.c_str(), relocated.c_str()) == 0);
    Read moved = apple_installation(ns(relocated));
    CHECK(moved.status == Status::ok && moved.bytes == known);
    CHECK(scoped_identity("fail.still.mbui", moved.bytes) == scoped_identity("fail.still.mbui", reread.bytes));
    CHECK(scoped_identity("fail.still.mbui", moved.bytes) != scoped_identity("fail.still.mbui.debug", moved.bytes));

    // Real NSUUID generation and filesystem publication in two NEW containers. Never print the generated UUIDs.
    std::string fresh = scratch.dir("fresh"), reinstall = scratch.dir("reinstall");
    Read generated = apple_installation(ns(fresh));
    CHECK(generated.status == Status::ok && valid_installation(generated.bytes));
    Read generated_again = apple_installation(ns(fresh));
    CHECK(generated_again.status == Status::ok && generated_again.bytes == generated.bytes);
    CHECK(contents(file_at(fresh)) == generated.bytes);
    Read new_container = apple_installation(ns(reinstall));
    CHECK(new_container.status == Status::ok && valid_installation(new_container.bytes));
    CHECK(new_container.bytes != generated.bytes);
    only_identity_file(fresh); only_identity_file(reinstall);

    // Strict byte length and format: failures must not generate/publish a replacement identity.
    std::vector<std::string> malformed = {std::string(), known.substr(0, 35), known + "x", known + "\n", std::string(36, 'z')};
    for (size_t i = 0; i < malformed.size(); ++i) {
      std::string name = "malformed-" + std::to_string(i);
      std::string dir = scratch.dir(name.c_str());
      seed(dir, malformed[i]);
      DirectoryFD fd(dir);
      CHECK(apple_installation_read(fd.value).status == Status::unavailable);
      CHECK(apple_installation(ns(dir)).status == Status::unavailable);
      CHECK(contents(file_at(dir)) == malformed[i]);
      only_identity_file(dir);
    }

    std::string permissions = scratch.dir("permissions");
    seed(permissions, known);
    CHECK(chmod(file_at(permissions).c_str(), 0644) == 0);
    CHECK(apple_installation(ns(permissions)).status == Status::unavailable);
    CHECK(contents(file_at(permissions)) == known);
    CHECK(lstat(file_at(permissions).c_str(), &st) == 0 && (st.st_mode & 0777) == 0644);
    CHECK(chmod(file_at(permissions).c_str(), 0400) == 0);
    CHECK(apple_installation(ns(permissions)).status == Status::unavailable);
    CHECK(contents(file_at(permissions)) == known);
    CHECK(chmod(file_at(permissions).c_str(), 0600) == 0);
    Read repaired = apple_installation(ns(permissions));
    CHECK(repaired.status == Status::ok && repaired.bytes == known); // no hidden replacement on previous errors
    only_identity_file(permissions);

    std::string symlink_dir = scratch.dir("symlink-file");
    CHECK(symlink(file_at(relocated).c_str(), file_at(symlink_dir).c_str()) == 0);
    {
      DirectoryFD fd(symlink_dir);
      CHECK(apple_installation_read(fd.value).status == Status::unavailable);
      CHECK(apple_installation_create(fd.value, other) == Status::duplicate);
    }
    CHECK(apple_installation(ns(symlink_dir)).status == Status::unavailable);
    CHECK(lstat(file_at(symlink_dir).c_str(), &st) == 0 && S_ISLNK(st.st_mode));
    CHECK(contents(file_at(relocated)) == known);
    only_identity_file(symlink_dir);
    std::string directory_link = scratch.root + "/symlink-directory";
    CHECK(symlink(relocated.c_str(), directory_link.c_str()) == 0);
    CHECK(apple_installation(ns(directory_link)).status == Status::unavailable);
    CHECK(contents(file_at(relocated)) == known);
  }
  std::puts("iOS installation production-filesystem contracts passed (no Keychain operations)");
}
