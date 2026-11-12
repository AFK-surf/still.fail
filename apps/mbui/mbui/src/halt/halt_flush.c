// What was printed and still waits in the process's buffers, written out before a halt stops it (halt_native.mbt).
// A stub of its own, not libc's fflush declared from MoonBit: moonc writes its own prototype for that name,
// int32_t fflush(uint64_t), and where a unit of the program also has <stdio.h> (mbc's Android demos, by the host's
// headers) the two conflict and it does not compile (mbui-ci's day's run, 8a03ff2d 43150293224, 2026-11-12).
#include <stdio.h>

int mbui_halt_flush(void) { return fflush(NULL); }
