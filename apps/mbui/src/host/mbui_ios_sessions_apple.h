// Production adapter for the main iOS core. The explicit test guard exposes ONLY installation filesystem code.
#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <TargetConditionals.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <optional>
#include "mbui_ios_sessions.h"

namespace mbui_ios_sessions {
#if TARGET_OS_IPHONE
inline Status apple_status(OSStatus status) {
  if (status == errSecSuccess) return Status::ok;
  if (status == errSecItemNotFound) return Status::missing;
  if (status == errSecDuplicateItem) return Status::duplicate;
  return Status::unavailable;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
inline NSMutableDictionary *apple_query(NSString *identity) {
  // No access-group override (main app's default group only), no synchronizable/iCloud item, no user/token IDs.
  return [@{(id)kSecClass: (id)kSecClassGenericPassword,
            (id)kSecAttrService: @"fail.still.mbui.sessions",
            (id)kSecAttrAccount: identity,
            (id)kSecAttrSynchronizable: @NO,
            (id)kSecUseAuthenticationUI: (id)kSecUseAuthenticationUIFail} mutableCopy];
}
#pragma clang diagnostic pop
#endif

// Standalone macOS filesystem tests do not compile the Keychain adapter and never override SDK target macros.
#if TARGET_OS_IPHONE || defined(MBUI_IOS_INSTALLATION_FILESYSTEM_TEST)
inline Read apple_installation_read(int dirfd) {
  int fd = openat(dirfd, ".mbui-sessions-installation", O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (fd < 0) return {errno == ENOENT ? Status::missing : Status::unavailable, {}};
  struct stat st{};
  bool ok = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == getuid() &&
            (st.st_mode & 0777) == 0600 && st.st_size == 36;
  std::string value;
  char buffer[37];
  while (ok && value.size() < sizeof buffer) {
    ssize_t count = read(fd, buffer, sizeof buffer - value.size());
    if (count == 0) break;
    if (count < 0) {
      if (errno == EINTR) continue;
      ok = false;
    } else value.append(buffer, size_t(count));
  }
  if (close(fd) != 0) ok = false;
  // Existing/duplicate readers may observe the published link before its creator syncs the directory (or after
  // that sync failed). Make the namespace durable before any caller can commit Keychain/delete legacy bytes.
  if (ok && valid_installation(value) && fsync(dirfd) != 0) ok = false;
  return ok && valid_installation(value) ? Read{Status::ok, std::move(value)} : Read{Status::unavailable, {}};
}

inline Status apple_installation_create(int dirfd, const std::string &value) {
  // Publish a fully written, synced 0600 file using a no-replace hard link. A crash cannot expose a partially
  // written identity or replace another creator's identity. Any abandoned temporary file contains only a UUID.
  std::string temp = ".mbui-sessions-installation." + std::string(NSUUID.UUID.UUIDString.lowercaseString.UTF8String);
  int fd = openat(dirfd, temp.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd < 0) return Status::unavailable;
  bool ok = fchmod(fd, 0600) == 0;
  size_t written = 0;
  while (ok && written < value.size()) {
    ssize_t count = write(fd, value.data() + written, value.size() - written);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) ok = false;
    else written += size_t(count);
  }
  if (ok && fsync(fd) != 0) ok = false;
  if (close(fd) != 0) ok = false;
  Status status = Status::unavailable;
  if (ok) {
    if (linkat(dirfd, temp.c_str(), dirfd, ".mbui-sessions-installation", 0) == 0) status = Status::ok;
    else if (errno == EEXIST) status = Status::duplicate;
  }
  if (unlinkat(dirfd, temp.c_str(), 0) != 0) return Status::unavailable;
  if (status == Status::ok && fsync(dirfd) != 0) return Status::unavailable;
  return status;
}

inline Read apple_installation(NSString *data_dir) {
  int dirfd = open(data_dir.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (dirfd < 0) return {Status::unavailable, {}};
  Read result = installation({
    [dirfd]() { return apple_installation_read(dirfd); },
    [dirfd](const std::string &value) { return apple_installation_create(dirfd, value); },
    []() { return std::string(NSUUID.UUID.UUIDString.lowercaseString.UTF8String); }
  });
  if (close(dirfd) != 0) return {Status::unavailable, {}};
  return result;
}

#endif

#if TARGET_OS_IPHONE
inline std::optional<Backend> apple_backend(NSString *data_dir, NSString *bundle) {
  // The nonsecret installation UUID is stored INSIDE dataDir, not derived from its movable sandbox UUID/path.
  // Container relocation/restoration retains this namespace; reinstall/new container deliberately gets a new
  // namespace and does not recover old sessions. ThisDeviceOnly items never migrate to another device.
  Read installation_id = apple_installation(data_dir);
  if (installation_id.status != Status::ok) {
    // Corrupt/unreadable identity is not a new installation. Do not regenerate it or inspect/migrate sessions.
    return std::nullopt;
  }
  std::string scope = scoped_identity(bundle.UTF8String ?: "", installation_id.bytes);
  NSString *identity = [[NSString alloc] initWithBytes:scope.data() length:scope.size() encoding:NSUTF8StringEncoding];
  std::string path([[data_dir stringByAppendingPathComponent:@"accounts"] fileSystemRepresentation]);
  Backend backend;
  backend.get = [identity]() -> Read {
    NSMutableDictionary *query = apple_query(identity);
    query[(id)kSecReturnData] = @YES;
    query[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
    CFTypeRef out = nullptr;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &out);
    id value = out ? CFBridgingRelease(out) : nil;
    if (status != errSecSuccess) return {apple_status(status), {}};
    if (![value isKindOfClass:NSData.class]) return {Status::unavailable, {}};
    NSData *data = value;
    return {Status::ok, data.length ? std::string(static_cast<const char *>(data.bytes), data.length) : std::string()};
  };
  backend.update = [identity](const std::string &bytes) {
    NSDictionary *attributes = @{
      (id)kSecValueData: [NSData dataWithBytes:bytes.data() length:bytes.size()],
      (id)kSecAttrAccessible: (id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
    return apple_status(SecItemUpdate((__bridge CFDictionaryRef)apple_query(identity), (__bridge CFDictionaryRef)attributes));
  };
  backend.add = [identity](const std::string &bytes) {
    NSMutableDictionary *query = apple_query(identity);
    query[(id)kSecValueData] = [NSData dataWithBytes:bytes.data() length:bytes.size()];
    query[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    return apple_status(SecItemAdd((__bridge CFDictionaryRef)query, nullptr));
  };
  backend.erase = [identity]() { return apple_status(SecItemDelete((__bridge CFDictionaryRef)apple_query(identity))); };
  backend.legacy_get = [path]() -> Read {
    // Read only the exact Rust storage_path(dataDir, "accounts"). Refuse symlinks/non-regular files and errors;
    // no environment or alternate-file fallback, and no JSON parsing/re-encoding of the session bytes.
    int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) return {errno == ENOENT ? Status::missing : Status::unavailable, {}};
    struct stat st{};
    bool ok = fstat(fd, &st) == 0 && S_ISREG(st.st_mode);
    std::string bytes;
    char buffer[8192];
    while (ok) {
      ssize_t count = read(fd, buffer, sizeof buffer);
      if (count == 0) break;
      if (count < 0) {
        if (errno == EINTR) continue;
        ok = false;
      } else {
        bytes.append(buffer, size_t(count));
      }
    }
    if (close(fd) != 0) ok = false;
    return ok ? Read{Status::ok, std::move(bytes)} : Read{Status::unavailable, {}};
  };
  backend.legacy_erase = [path]() {
    return unlink(path.c_str()) == 0 || errno == ENOENT ? Status::ok : Status::unavailable;
  };
  return backend;
}
#endif
}  // namespace mbui_ios_sessions
