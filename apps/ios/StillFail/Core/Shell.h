#pragma once
#include <stdint.h>
#include <stddef.h>
typedef void (*sf_complete)(void*, uint64_t, const uint8_t*, size_t, const uint8_t*, size_t, const uint8_t*, size_t, uint8_t);
void* sf_shell_start(const char* data_dir, sf_complete complete, void* ctx);
void sf_shell_call(const void* shell, uint64_t id, const char* op, const uint8_t* json, size_t json_len, const uint8_t* bytes, size_t bytes_len, uint8_t has_bytes);
uint8_t* sf_shell_call_sync(const void* shell, const char* op, const uint8_t* json, size_t json_len, size_t* out_len);
void sf_free(uint8_t* ptr, size_t len);
void sf_shell_stop(void* shell);
