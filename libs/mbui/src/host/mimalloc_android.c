// mimalloc for the Android app (scripts/android.sh's mimalloc_obj compiles this, -I<mimalloc>/include -I<mimalloc>/src):
// its one-file build, src/static.c, as it is, with no raw system call left in what it reaches.
//
// Where <sys/syscall.h> names them, mimalloc's src/prim/unix/prim.c makes some calls as syscall(SYS_…) rather than
// libc's (open, read, close and access: "to allow for libraries that override open/read/close", its issue #713).
// Android's seccomp filter for apps does not take all of them: x86_64 has SYS_open and SYS_access, bionic itself
// calls openat and faccessat, and a raw access(2) killed kitdemo on CI's x86_64 emulator as mimalloc counted the NUMA
// nodes from the GL thread ("Fatal signal 31 (SIGSYS), code 1 (SYS_SECCOMP), syscall 21", mbui-host-android run
// 42940454386). arm64 never had SYS_open or SYS_access, so it took libc's all along. Without the names here,
// prim.c takes libc's on every ABI (open, read, close, access), and its stubs for the rest: the current thread's
// NUMA node 0 (SYS_getcpu; asked only where more than one node shows) and no NUMA binding of huge OS pages
// (SYS_mbind; huge OS pages are reserved only when asked, and nothing asks). Its random bytes are arc4random_buf on
// Android, never SYS_getrandom. <sys/syscall.h> is guarded, so prim.c's own include of it brings none back.
#include <sys/syscall.h>
#undef SYS_open
#undef SYS_read
#undef SYS_close
#undef SYS_access
#undef SYS_getcpu
#undef SYS_mbind
#undef SYS_getrandom

#include "static.c"
