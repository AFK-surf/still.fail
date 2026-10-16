// The drive's folders macOS protects (docs/drive.md): Documents, Desktop, Downloads, removable and network volumes,
// which a station launchd runs may not open, are opened here, by this app, which holds the grants (Files and Folders,
// or Full Disk Access). The station decides what goes through here and checks every path first; this side refuses
// anything outside the roots a request names or in what it protects, and never touches a protected folder it has no
// grant for: macOS would then put up its own prompt and hold the call until someone answers it, so a missing grant is
// answered (`grant`) and asked for in the window (Permissions.swift), where a person clicks Allow.
//
// Each request is one connection (main.swift), its fields: `roots` (absolute paths: what it may reach), `protect`
// (what it may not, even under a root), and the op's own:
//   files.access   {paths}                                     → {access: [{path, grant, state}]} (nothing touched)
//   files.list     {path, most}                                → {entries: [{name, link, real, dir, size, mtime}|{name, link, gone}], more}
//   files.names    {path}                                      → {names}
//   files.stat     {path, follow}                              → {dir, file, link, size, mtime}
//   files.real     {path}                                      → {path}: links followed, as far as it exists
//   files.read     {path, offset, length}                      → {size, mtime, length}, then `length` bytes, then the end
//   files.write    {path, offset, length, create, truncate?, sync?} → {size} (as it was), then the station's `length`
//                  bytes (or the end, to write nothing), then {size}
//   files.mkdir    {path, recursive}, files.rename {from, to}, files.remove {path} (a folder with all it holds, a link
//                  as a link), files.unlink {path}                → {}
// A refusal is {error, code}: an errno's name (ENOENT, EACCES, …), `outside`/`protected` (the roots, what is
// protected), `grant` with {grant, state} (macOS has not let this app open that folder: state `unknown`, never asked,
// or `denied`), `restart` (granted since this process started: it starts again, and the station asks once more).
import AppKit
import Darwin
import Foundation

enum FileGrant: String, CaseIterable {
  case documents, desktop, downloads, removable, network

  var service: String {
    switch self {
    case .documents: "kTCCServiceSystemPolicyDocumentsFolder"
    case .desktop: "kTCCServiceSystemPolicyDesktopFolder"
    case .downloads: "kTCCServiceSystemPolicyDownloadsFolder"
    case .removable: "kTCCServiceSystemPolicyRemovableVolumes"
    case .network: "kTCCServiceSystemPolicyNetworkVolumes"
    }
  }
}

struct FileRefusal: Error {
  let code: String
  let message: String
  var fields: [String: Any] = [:]

  static func errno(_ e: Int32 = Darwin.errno) -> FileRefusal {
    FileRefusal(code: Files.errnoName(e), message: String(cString: strerror(e)))
  }
}

enum Files {
  /// How much of a file one read or write moves at a time over the socket.
  static let CHUNK = 256 * 1024

  // MARK: grants

  private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
  private static let preflightFunction: Preflight? = {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW), let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
    return unsafeBitCast(symbol, to: Preflight.self)
  }()

  /// What macOS says this process may do for `service` without asking: 0 granted, 1 denied, 2 not asked yet (it would
  /// ask), -1 not known (no TCC to ask).
  static func preflight(_ service: String) -> Int32 {
    preflightFunction?(service as CFString, nil) ?? -1
  }

  /// Each folder grant as `status` reports it (granted, denied, unknown), Full Disk Access as `all`.
  static func grants() -> [String: String] {
    var out: [String: String] = ["all": word(preflight("kTCCServiceSystemPolicyAllFiles"))]
    for grant in FileGrant.allCases { out[grant.rawValue] = state(grant) }
    return out
  }

  private static func word(_ value: Int32) -> String {
    value == 0 ? "granted" : value == 1 ? "denied" : "unknown"
  }

  /// Whether this process may open what `grant` keeps: its own grant, or Full Disk Access.
  static func state(_ grant: FileGrant) -> String {
    if preflight("kTCCServiceSystemPolicyAllFiles") == 0 { return "granted" }
    return word(preflight(grant.service))
  }

  // MARK: where macOS protects

  static let home = NSHomeDirectory()

  /// Compared as macOS's disks do by default: case aside.
  static func key(_ path: String) -> String { path.lowercased() }

  static func within(_ path: String, _ dir: String) -> Bool {
    let p = key(path), d = key(dir)
    return d == "/" || p == d || p.hasPrefix(d.hasSuffix("/") ? d : d + "/")
  }

  /// The protected folder `path` is (or is under), by its name (nothing touched), and the grant that opens it: the
  /// home's Documents, Desktop, Downloads; a disk mounted in /Volumes other than the system's own (removable, or network
  /// where the disk is not local).
  static func location(_ path: String) -> (top: String, grant: FileGrant)? {
    for (name, grant) in [("Documents", FileGrant.documents), ("Desktop", .desktop), ("Downloads", .downloads)] {
      let top = (home as NSString).appendingPathComponent(name)
      if within(path, top) { return (top, grant) }
    }
    let parts = components(path)
    guard parts.count >= 2, key(parts[0]) == "volumes" else { return nil }
    let top = "/Volumes/" + parts[1]
    var st = stat()
    // The system's own disk is a link to / there.
    if lstat(top, &st) != 0 || (st.st_mode & S_IFMT) == S_IFLNK { return nil }
    var fs = statfs()
    let local = statfs(top, &fs) != 0 || (fs.f_flags & UInt32(MNT_LOCAL)) != 0
    return (top, local ? .removable : .network)
  }

  /// Refused unless this process may open what keeps `path` (nothing touched when it may not).
  static func guardGrant(_ path: String) throws {
    guard let at = location(path) else { return }
    let state = state(at.grant)
    if state != "granted" {
      throw FileRefusal(code: "grant", message: "macOS has not let still.fail Helper open \(at.top)", fields: ["grant": at.grant.rawValue, "state": state, "top": at.top])
    }
  }

  // MARK: paths

  static func components(_ path: String) -> [String] {
    path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
  }

  static func joined(_ parts: [String]) -> String {
    "/" + parts.joined(separator: "/")
  }

  /// An absolute path with nothing to work out (no `.`, `..`, NUL), or refused.
  static func clean(_ value: Any?) throws -> String {
    guard let path = value as? String, path.hasPrefix("/"), !path.contains("\0") else { throw FileRefusal(code: "EINVAL", message: "an absolute path") }
    let parts = components(path)
    if parts.contains(where: { $0 == "." || $0 == ".." }) { throw FileRefusal(code: "outside", message: "a path is asked as it is, without . or ..") }
    return joined(parts)
  }

  /// `path` with its links followed (the last one too, unless `last` is false), as far as it exists, each step looked at
  /// before it is taken: a protected folder this process has no grant for is never touched.
  static func resolve(_ path: String, last: Bool = true) throws -> String {
    var pending = components(path)
    var done: [String] = []
    var hops = 0
    while !pending.isEmpty {
      let name = pending.removeFirst()
      let next = done + [name]
      let nextPath = joined(next)
      try guardGrant(nextPath)
      var st = stat()
      if lstat(nextPath, &st) != 0 {
        if errno == ENOENT || errno == ENOTDIR { return joined(next + pending) }
        throw FileRefusal.errno()
      }
      if (st.st_mode & S_IFMT) == S_IFLNK && (last || !pending.isEmpty) {
        hops += 1
        if hops > 40 { throw FileRefusal.errno(ELOOP) }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let n = readlink(nextPath, &buffer, Int(PATH_MAX))
        if n < 0 { throw FileRefusal.errno() }
        let target = String(decoding: buffer[0..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let targetParts = components(target).filter { $0 != "." }
        // `..` in a link's target is worked out against where it is, as the system does.
        var base = target.hasPrefix("/") ? [] : done
        var rest: [String] = []
        for part in targetParts {
          if part == ".." && rest.isEmpty { if !base.isEmpty { base.removeLast() } } else if part == ".." { rest.removeLast() } else { rest.append(part) }
        }
        done = base
        pending = rest + pending
        continue
      }
      done = next
    }
    // Its case as the disk has it (every step there is one this process may take).
    return canonical(joined(done))
  }

  /// As the disk names it, as far as it exists.
  private static func canonical(_ path: String) -> String {
    var parts = components(path)
    var rest: [String] = []
    while true {
      if let real = realpath(joined(parts), nil) {
        defer { free(real) }
        let base = String(cString: real)
        return rest.isEmpty ? base : (base == "/" ? "" : base) + "/" + rest.reversed().joined(separator: "/")
      }
      guard let lastPart = parts.popLast() else { return path }
      rest.append(lastPart)
    }
  }

  /// The entry itself: its folder's links followed, not its own (what a rename or a removal acts on).
  static func entry(_ path: String) throws -> String {
    let parts = components(path)
    guard let name = parts.last else { return "/" }
    let folder = try resolve(joined(Array(parts.dropLast())))
    return (folder == "/" ? "" : folder) + "/" + name
  }

  /// What a request may reach and may not.
  struct Scope {
    let roots: [String]
    let realRoots: [String]
    let protect: [String]

    init(_ request: [String: Any]) throws {
      let roots = (request["roots"] as? [Any] ?? []).compactMap { try? Files.clean($0) }
      if roots.isEmpty { throw FileRefusal(code: "outside", message: "no roots named") }
      self.roots = roots
      realRoots = roots.map { (try? Files.resolve($0)) ?? $0 }
      let protect = (request["protect"] as? [Any] ?? []).compactMap { try? Files.clean($0) }
      self.protect = protect + protect.map { (try? Files.resolve($0)) ?? $0 }
    }

    /// `path` as asked (clean), and as found (`entry`: its own link not followed), once both are in a root and neither
    /// in what is protected.
    func place(_ value: Any?, entry: Bool = false) throws -> (asked: String, found: String) {
      let asked = try Files.clean(value)
      guard roots.contains(where: { Files.within(asked, $0) }) else { throw FileRefusal(code: "outside", message: "\(asked) is not under a root it was given") }
      if protect.contains(where: { Files.within(asked, $0) }) { throw FileRefusal(code: "protected", message: "\(asked) is the station's own") }
      let found = entry ? try Files.entry(asked) : try Files.resolve(asked)
      try check(found)
      return (asked, found)
    }

    /// A path as found (links followed): in a root, not protected.
    func check(_ found: String) throws {
      guard realRoots.contains(where: { Files.within(found, $0) }) || roots.contains(where: { Files.within(found, $0) }) else {
        throw FileRefusal(code: "outside", message: "\(found) leads out of its root")
      }
      if protect.contains(where: { Files.within(found, $0) }) { throw FileRefusal(code: "protected", message: "\(found) is the station's own") }
    }
  }

  // MARK: the ops

  /// Answers `op` on `channel`; true when it was one of these.
  static func serve(_ op: String, _ request: [String: Any], _ channel: Channel, daemon: Daemon) -> Bool {
    guard op.hasPrefix("files.") else { return false }
    do {
      if op == "files.access" {
        let paths = (request["paths"] as? [Any] ?? []).compactMap { try? clean($0) }
        channel.line(["access": paths.map { path -> [String: Any] in
          guard let at = location(path) else { return ["path": path, "grant": NSNull(), "state": "granted"] }
          return ["path": path, "top": at.top, "grant": at.grant.rawValue, "state": state(at.grant)]
        }])
        return true
      }
      let scope = try Scope(request)
      do {
        try run(op, request, scope, channel)
      } catch let refusal as FileRefusal where refusal.code == "EPERM" || refusal.code == "EACCES" {
        // Granted since this process started, as macOS says, and still refused: it starts again to have it. One granted
        // from the start refuses for a reason of its own (the file's mode), said as it is.
        let paths = ["path", "from", "to"].compactMap { request[$0] as? String }
        let since = paths.contains { path in location(path).map { state($0.grant) == "granted" && daemon.startedFiles[$0.grant.rawValue] != "granted" } ?? false }
        if since { throw FileRefusal(code: "restart", message: "starting again to have the grant", fields: ["pid": Int(getpid())]) }
        throw refusal
      }
    } catch let refusal as FileRefusal {
      var answer: [String: Any] = ["error": refusal.message, "code": refusal.code]
      for (k, v) in refusal.fields { answer[k] = v }
      channel.line(answer)
      if refusal.code == "restart" { DispatchQueue.main.async { daemon.restart() } }
    } catch {
      channel.line(["error": "\(error)", "code": "EIO"])
    }
    return true
  }

  private static func run(_ op: String, _ request: [String: Any], _ scope: Scope, _ channel: Channel) throws {
    switch op {
    case "files.list":
      let at = try scope.place(request["path"])
      let most = max(0, request["most"] as? Int ?? 50_000)
      guard let dir = opendir(at.found) else { throw FileRefusal.errno() }
      defer { closedir(dir) }
      var entries: [[String: Any]] = []
      var more = false
      while let item = readdir(dir) {
        let name = withUnsafeBytes(of: item.pointee.d_name) { raw in String(cString: raw.bindMemory(to: CChar.self).baseAddress!) }
        if name == "." || name == ".." { continue }
        if entries.count >= most {
          more = true
          break
        }
        entries.append(listed(at.found, name, scope))
      }
      channel.line(["entries": entries, "more": more])
    case "files.names":
      let at = try scope.place(request["path"])
      guard let dir = opendir(at.found) else { throw FileRefusal.errno() }
      defer { closedir(dir) }
      var names: [String] = []
      while let item = readdir(dir) {
        let name = withUnsafeBytes(of: item.pointee.d_name) { raw in String(cString: raw.bindMemory(to: CChar.self).baseAddress!) }
        if name != "." && name != ".." { names.append(name) }
      }
      channel.line(["names": names])
    case "files.stat":
      let follow = request["follow"] as? Bool ?? true
      let at = try scope.place(request["path"], entry: !follow)
      var st = stat()
      if (follow ? stat(at.found, &st) : lstat(at.found, &st)) != 0 { throw FileRefusal.errno() }
      channel.line(described(st))
    case "files.real":
      channel.line(["path": try scope.place(request["path"]).found])
    case "files.read":
      try read(request, scope, channel)
    case "files.write":
      try write(request, scope, channel)
    case "files.mkdir":
      let at = try scope.place(request["path"], entry: true)
      try makeFolder(at.found, recursive: request["recursive"] as? Bool ?? false)
      channel.line([:])
    case "files.rename":
      let from = try scope.place(request["from"], entry: true)
      let to = try scope.place(request["to"], entry: true)
      if rename(from.found, to.found) != 0 { throw FileRefusal.errno() }
      channel.line([:])
    case "files.remove":
      let at = try scope.place(request["path"], entry: true)
      try remove(at.found)
      channel.line([:])
    case "files.unlink":
      let at = try scope.place(request["path"], entry: true)
      if unlink(at.found) != 0 { throw FileRefusal.errno() }
      channel.line([:])
    default:
      throw FileRefusal(code: "EINVAL", message: "unknown op \(op)")
    }
  }

  private static func described(_ st: stat) -> [String: Any] {
    let kind = st.st_mode & S_IFMT
    let dir = kind == S_IFDIR
    return ["dir": dir, "file": kind == S_IFREG, "link": kind == S_IFLNK, "size": dir ? 0 : Int(st.st_size), "mtime": mtime(st)]
  }

  private static func mtime(_ st: stat) -> Double {
    Double(st.st_mtimespec.tv_sec) * 1000 + Double(st.st_mtimespec.tv_nsec) / 1_000_000
  }

  /// An entry of a listing: where it leads (links followed) and what is there; `gone` for a link that leads nowhere it
  /// may go (broken, out of the roots, protected, a folder macOS keeps from this app).
  private static func listed(_ folder: String, _ name: String, _ scope: Scope) -> [String: Any] {
    let path = (folder == "/" ? "" : folder) + "/" + name
    var st = stat()
    if lstat(path, &st) != 0 { return ["name": name, "link": false, "gone": true] }
    var real = path
    if (st.st_mode & S_IFMT) == S_IFLNK {
      guard let found = try? resolve(path), (try? scope.check(found)) != nil, stat(found, &st) == 0 else { return ["name": name, "link": true, "gone": true] }
      real = found
    } else if (try? scope.check(path)) == nil {
      return ["name": name, "link": false, "gone": true]
    }
    var out = described(st)
    out["name"] = name
    out["link"] = real != path
    out["real"] = real
    return out
  }

  private static func read(_ request: [String: Any], _ scope: Scope, _ channel: Channel) throws {
    let at = try scope.place(request["path"])
    guard let offset = request["offset"] as? Int, let length = request["length"] as? Int, offset >= 0, length >= 0 else { throw FileRefusal(code: "EINVAL", message: "offset and length") }
    let fd = open(at.found, O_RDONLY)
    if fd < 0 { throw FileRefusal.errno() }
    defer { close(fd) }
    var st = stat()
    if fstat(fd, &st) != 0 { throw FileRefusal.errno() }
    if (st.st_mode & S_IFMT) == S_IFDIR { throw FileRefusal.errno(EISDIR) }
    let size = Int(st.st_size)
    let want = max(0, min(length, size - offset))
    channel.line(["size": size, "mtime": mtime(st), "length": want])
    var buffer = Data(count: min(CHUNK, max(want, 1)))
    var sent = 0
    while sent < want && !channel.broken {
      let n = min(CHUNK, want - sent)
      let got = buffer.withUnsafeMutableBytes { raw in pread(fd, raw.baseAddress!, n, off_t(offset + sent)) }
      if got < 0 && errno == EINTR { continue }
      // Shorter than it was (changed meanwhile) or unreadable: the station sees the stream end early.
      if got <= 0 { return }
      channel.write(buffer.prefix(got))
      sent += got
    }
  }

  private static func write(_ request: [String: Any], _ scope: Scope, _ channel: Channel) throws {
    let at = try scope.place(request["path"])
    guard let offset = request["offset"] as? Int, let length = request["length"] as? Int, offset >= 0, length >= 0 else { throw FileRefusal(code: "EINVAL", message: "offset and length") }
    let create = request["create"] as? Bool ?? false
    let fd = create ? open(at.found, O_WRONLY | O_CREAT | O_TRUNC, 0o644) : open(at.found, O_RDWR)
    if fd < 0 { throw FileRefusal.errno() }
    defer { close(fd) }
    var st = stat()
    if fstat(fd, &st) != 0 { throw FileRefusal.errno() }
    channel.line(["size": Int(st.st_size)])
    var done = 0
    while done < length {
      // The station sent nothing (it will not write after all) or went: nothing more.
      guard let chunk = channel.read(upTo: min(CHUNK, length - done)) else { return }
      var at = 0
      while at < chunk.count {
        let n = chunk.withUnsafeBytes { raw in pwrite(fd, raw.baseAddress! + at, chunk.count - at, off_t(offset + done + at)) }
        if n < 0 && errno == EINTR { continue }
        if n < 0 { throw FileRefusal.errno() }
        at += n
      }
      done += chunk.count
    }
    if let truncate = request["truncate"] as? Int, ftruncate(fd, off_t(truncate)) != 0 { throw FileRefusal.errno() }
    if request["sync"] as? Bool == true, fsync(fd) != 0 { throw FileRefusal.errno() }
    if fstat(fd, &st) != 0 { throw FileRefusal.errno() }
    channel.line(["size": Int(st.st_size)])
  }

  private static func makeFolder(_ path: String, recursive: Bool) throws {
    if mkdir(path, 0o755) == 0 { return }
    var failure = errno
    guard recursive else { throw FileRefusal.errno(failure) }
    if failure == ENOENT {
      try makeFolder((path as NSString).deletingLastPathComponent, recursive: true)
      if mkdir(path, 0o755) == 0 { return }
      failure = errno
    }
    // There already, as a folder: what a folder made with its parents wants.
    var st = stat()
    if failure == EEXIST && stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR { return }
    throw FileRefusal.errno(failure)
  }

  /// A folder with all it holds; anything else (a link too) itself.
  private static func remove(_ path: String) throws {
    var st = stat()
    if lstat(path, &st) != 0 { throw FileRefusal.errno() }
    guard (st.st_mode & S_IFMT) == S_IFDIR else {
      if unlink(path) != 0 { throw FileRefusal.errno() }
      return
    }
    guard let dir = opendir(path) else { throw FileRefusal.errno() }
    var names: [String] = []
    while let item = readdir(dir) {
      let name = withUnsafeBytes(of: item.pointee.d_name) { raw in String(cString: raw.bindMemory(to: CChar.self).baseAddress!) }
      if name != "." && name != ".." { names.append(name) }
    }
    closedir(dir)
    for name in names { try remove(path + "/" + name) }
    if rmdir(path) != 0 { throw FileRefusal.errno() }
  }

  static func errnoName(_ e: Int32) -> String {
    switch e {
    case ENOENT: "ENOENT"
    case EACCES: "EACCES"
    case EPERM: "EPERM"
    case EEXIST: "EEXIST"
    case ENOTEMPTY: "ENOTEMPTY"
    case EISDIR: "EISDIR"
    case ENOTDIR: "ENOTDIR"
    case ENOSPC: "ENOSPC"
    case ELOOP: "ELOOP"
    case EXDEV: "EXDEV"
    case EINVAL: "EINVAL"
    case ENAMETOOLONG: "ENAMETOOLONG"
    case EROFS: "EROFS"
    case EBUSY: "EBUSY"
    default: "EIO"
    }
  }

  /// The window's Allow for a folder grant: never asked, this app opens the folder, and macOS asks (its own prompt, the
  /// only way a folder is granted; Full Disk Access is the other); refused before, System Settings' Files and Folders,
  /// where this app is listed with a switch for it.
  static func ask(_ grant: FileGrant, path: String?) {
    if state(grant) == "denied" {
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") { NSWorkspace.shared.open(url) }
      return
    }
    let top: String
    switch grant {
    case .documents: top = (home as NSString).appendingPathComponent("Documents")
    case .desktop: top = (home as NSString).appendingPathComponent("Desktop")
    case .downloads: top = (home as NSString).appendingPathComponent("Downloads")
    case .removable, .network: top = path.flatMap { location($0)?.top } ?? "/Volumes"
    }
    // Held until a person answers macOS: off the main thread.
    DispatchQueue.global().async {
      if let dir = opendir(top) { closedir(dir) }
    }
  }
}
