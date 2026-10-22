// What mbc asks of the system (io.c): files whole, a directory's names, the environment, stderr, exit.

///|
#borrow(path)
extern "C" fn c_read_file(path : Bytes) -> Bytes = "mbc_read_file"

///|
extern "C" fn c_read_ok() -> Int = "mbc_read_ok"

///|
#borrow(path, data)
extern "C" fn c_write_file(path : Bytes, data : Bytes) -> Int = "mbc_write_file"

///|
#borrow(from, to)
extern "C" fn c_rename(from : Bytes, to : Bytes) -> Int = "mbc_rename"

///|
#borrow(path)
extern "C" fn c_remove(path : Bytes) -> Int = "mbc_remove"

///|
#borrow(path)
extern "C" fn c_mkdir(path : Bytes) -> Int = "mbc_mkdir"

///|
#borrow(path)
extern "C" fn c_list_dir(path : Bytes) -> Bytes = "mbc_list_dir"

///|
#borrow(name)
extern "C" fn c_getenv(name : Bytes) -> Bytes = "mbc_getenv"

///|
extern "C" fn c_env_was_set() -> Int = "mbc_env_was_set"

///|
#borrow(s)
extern "C" fn c_write_err(s : Bytes) -> Unit = "mbc_write_err"

///|
extern "C" fn c_exit(code : Int) -> Unit = "mbc_exit"

///|
/// A file's bytes, None when it cannot be read.
fn read_file(path : Bytes) -> Bytes? {
  let b = c_read_file(path)
  if c_read_ok() != 0 {
    Some(b)
  } else {
    None
  }
}

///|
fn write_file(path : Bytes, data : Bytes) -> Bool {
  c_write_file(path, data) != 0
}

///|
fn list_dir(path : Bytes) -> Array[Bytes] {
  let all = c_list_dir(path)
  let out = []
  let mut s = 0
  for i in 0..<all.length() {
    if all[i] == b'\x00' {
      out.push(all[s:i].to_bytes())
      s = i + 1
    }
  }
  out
}

///|
/// An environment variable's value, None when it is not set.
fn getenv(name : String) -> Bytes? {
  let v = c_getenv(utf8(name))
  if c_env_was_set() != 0 {
    Some(v)
  } else {
    None
  }
}

///|
fn eprint(s : String) -> Unit {
  c_write_err(utf8(s + "\n"))
}

///|
fn utf8(s : String) -> Bytes {
  let buf = @buffer.new()
  buf.write_string_utf8(s)
  buf.to_bytes()
}

///|
/// Bytes as a String for a message (UTF-8; anything else as U+FFFD).
fn str(b : BytesView) -> String {
  let sb = StringBuilder::new()
  let n = b.length()
  let mut i = 0
  while i < n {
    let c = b[i].to_int()
    let (len, init) = if c < 0x80 {
      (1, c)
    } else if c >= 0xC2 && c < 0xE0 {
      (2, c & 0x1F)
    } else if c >= 0xE0 && c < 0xF0 {
      (3, c & 0x0F)
    } else if c >= 0xF0 && c < 0xF5 {
      (4, c & 0x07)
    } else {
      (0, 0)
    }
    let mut cp = init
    let mut ok = len > 0 && i + len <= n
    if ok {
      for k in 1..<len {
        let d = b[i + k].to_int()
        if (d & 0xC0) != 0x80 {
          ok = false
          break
        }
        cp = (cp << 6) | (d & 0x3F)
      }
    }
    if ok {
      sb.write_char(Int::unsafe_to_char(cp))
      i += len
    } else {
      sb.write_char('\u{FFFD}')
      i += 1
    }
  }
  sb.to_string()
}

///|
let tick_on : Bool = getenv("MBC_TIME") is Some(_)

///|
let tick_last : Ref[UInt64] = { val: @env.now() }

///|
/// With MBC_TIME set: how long since the last tick, on stderr
fn tick(label : String) -> Unit {
  if tick_on {
    let now = @env.now()
    eprint("  \{label}: \{now - tick_last.val} ms")
    tick_last.val = now
  }
}

///|
extern "C" fn c_cpu_count() -> Int = "mbc_cpu_count"

///|
/// fork(2): 0 in the child, -1 where there is none (Windows)
extern "C" fn c_fork() -> Int = "mbc_fork"

///|
/// Waits for every child: nonzero when one failed
extern "C" fn c_wait_all() -> Int = "mbc_wait_all"

///|
extern "C" fn c_child_exit(code : Int) -> Unit = "mbc_child_exit"

///|
extern "C" fn c_is_windows() -> Int = "mbc_is_windows"

///|
extern "C" fn c_is_linux() -> Int = "mbc_is_linux"

///|
#borrow(s)
extern "C" fn c_write_out(s : Bytes) -> Unit = "mbc_write_out"

///|
#borrow(name, value)
extern "C" fn c_setenv(name : Bytes, value : Bytes) -> Int = "mbc_setenv"

///|
#borrow(path)
extern "C" fn c_stat(path : Bytes) -> Int = "mbc_stat"

///|
extern "C" fn c_stat_size() -> Int64 = "mbc_stat_size"

///|
extern "C" fn c_stat_mtime() -> Int64 = "mbc_stat_mtime"

///|
#borrow(path)
extern "C" fn c_touch(path : Bytes) -> Int = "mbc_touch"

///|
#borrow(path)
extern "C" fn c_rmdir(path : Bytes) -> Int = "mbc_rmdir"

///|
#borrow(target, link)
extern "C" fn c_symlink(target : Bytes, link : Bytes) -> Int = "mbc_symlink"

///|
#borrow(path)
extern "C" fn c_chmod(path : Bytes, mode : Int) -> Int = "mbc_chmod"

///|
#borrow(path)
extern "C" fn c_executable(path : Bytes) -> Int = "mbc_executable"

///|
extern "C" fn c_getcwd() -> Bytes = "mbc_getcwd"

///|
#borrow(path)
extern "C" fn c_realpath(path : Bytes) -> Bytes = "mbc_realpath"

///|
extern "C" fn c_getpid() -> Int = "mbc_getpid"

///|
#borrow(path)
extern "C" fn c_lock(path : Bytes, wait : Int) -> Int = "mbc_lock"

///|
extern "C" fn c_unlock(fd : Int) -> Unit = "mbc_unlock"

///|
#borrow(words, cmdline, out)
extern "C" fn c_spawn(words : Bytes, cmdline : Bytes, out : Bytes) -> Int = "mbc_spawn"

///|
extern "C" fn c_wait_any() -> Int = "mbc_wait_any"

///|
extern "C" fn c_status() -> Int = "mbc_status"

///|
let windows : Bool = c_is_windows() != 0

///|
/// A file's kind (0 none, 1 file, 2 directory, 3 other)
fn kind_of_path(p : Bytes) -> Int {
  c_stat(p)
}

///|
fn is_file(p : Bytes) -> Bool {
  c_stat(p) == 1
}

///|
fn is_dir(p : Bytes) -> Bool {
  c_stat(p) == 2
}

///|
fn exists(p : Bytes) -> Bool {
  c_stat(p) != 0
}

///|
/// (size, mtime in ns), None when it is not there
fn stat(p : Bytes) -> (Int64, Int64)? {
  if c_stat(p) == 0 {
    None
  } else {
    Some((c_stat_size(), c_stat_mtime()))
  }
}

///|
fn out_line(s : Bytes) -> Unit {
  c_write_out(cat([s, b"\n"]))
}

///|
#borrow(path, data)
extern "C" fn c_append(path : Bytes, data : Bytes) -> Int = "mbc_append"

///|
#borrow(path)
extern "C" fn c_chdir(path : Bytes) -> Int = "mbc_chdir"
