// SQLite's C API as station/mb's `@sql` calls it: the SQLite client/shell links (rusqlite's, bundled, in the shell's
// static library every program of station/mb is linked with), asked directly, with no JSON between (sql.mbt).
#include <stdint.h>
#include <string.h>
#include "moonbit.h"

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs);
int sqlite3_close_v2(sqlite3 *db);
int sqlite3_busy_timeout(sqlite3 *db, int ms);
int sqlite3_exec(sqlite3 *db, const char *sql, void *callback, void *arg, char **errmsg);
const char *sqlite3_errmsg(sqlite3 *db);
const char *sqlite3_errstr(int rc);
int sqlite3_changes(sqlite3 *db);
int sqlite3_get_autocommit(sqlite3 *db);
int sqlite3_stmt_readonly(sqlite3_stmt *stmt);
int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int bytes, sqlite3_stmt **stmt, const char **tail);
int sqlite3_finalize(sqlite3_stmt *stmt);
int sqlite3_reset(sqlite3_stmt *stmt);
int sqlite3_clear_bindings(sqlite3_stmt *stmt);
int sqlite3_step(sqlite3_stmt *stmt);
int sqlite3_bind_parameter_count(sqlite3_stmt *stmt);
int sqlite3_bind_null(sqlite3_stmt *stmt, int i);
int sqlite3_bind_int64(sqlite3_stmt *stmt, int i, int64_t v);
int sqlite3_bind_double(sqlite3_stmt *stmt, int i, double v);
int sqlite3_bind_text(sqlite3_stmt *stmt, int i, const char *v, int n, void (*destructor)(void *));
int sqlite3_bind_blob(sqlite3_stmt *stmt, int i, const void *v, int n, void (*destructor)(void *));
int sqlite3_column_count(sqlite3_stmt *stmt);
const char *sqlite3_column_name(sqlite3_stmt *stmt, int i);
int sqlite3_column_type(sqlite3_stmt *stmt, int i);
int64_t sqlite3_column_int64(sqlite3_stmt *stmt, int i);
double sqlite3_column_double(sqlite3_stmt *stmt, int i);
const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int i);
const void *sqlite3_column_blob(sqlite3_stmt *stmt, int i);
int sqlite3_column_bytes(sqlite3_stmt *stmt, int i);
#define SQLITE_TRANSIENT ((void (*)(void *))-1)

static moonbit_bytes_t bytes_of(const void *p, int n) {
  moonbit_bytes_t out = moonbit_make_bytes(n < 0 ? 0 : n, 0);
  if (n > 0 && p != NULL) memcpy(out, p, (size_t)n);
  return out;
}

static moonbit_bytes_t text_of(const char *s) { return bytes_of(s, s == NULL ? 0 : (int)strlen(s)); }

/// The connection to `path` (NUL-terminated) opened with `flags`, waited for `wait` ms when busy; 0 where it failed,
/// `failed` then saying why (sqlite3_errmsg of what it made, or the code's).
int64_t sfq_open(moonbit_bytes_t path, int32_t flags, int32_t wait) {
  sqlite3 *db = NULL;
  int rc = sqlite3_open_v2((const char *)path, &db, flags, NULL);
  if (rc != 0) {
    if (db != NULL) sqlite3_close_v2(db);
    return -(int64_t)rc;
  }
  sqlite3_busy_timeout(db, wait);
  return (int64_t)(intptr_t)db;
}

moonbit_bytes_t sfq_errstr(int32_t rc) { return text_of(sqlite3_errstr(rc)); }
moonbit_bytes_t sfq_errmsg(int64_t db) { return text_of(sqlite3_errmsg((sqlite3 *)(intptr_t)db)); }
void sfq_close(int64_t db) { sqlite3_close_v2((sqlite3 *)(intptr_t)db); }
int32_t sfq_changes(int64_t db) { return sqlite3_changes((sqlite3 *)(intptr_t)db); }
int32_t sfq_autocommit(int64_t db) { return sqlite3_get_autocommit((sqlite3 *)(intptr_t)db); }
int32_t sfq_exec(int64_t db, moonbit_bytes_t sql) { return sqlite3_exec((sqlite3 *)(intptr_t)db, (const char *)sql, NULL, NULL, NULL); }

/// `sql` (its first `n` bytes) prepared on `db`; 0 where it failed (sqlite3_errmsg says why).
int64_t sfq_prepare(int64_t db, moonbit_bytes_t sql, int32_t n) {
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2((sqlite3 *)(intptr_t)db, (const char *)sql, n, &stmt, NULL) != 0) return 0;
  return (int64_t)(intptr_t)stmt;
}

#define S(s) ((sqlite3_stmt *)(intptr_t)(s))
void sfq_finalize(int64_t s) { sqlite3_finalize(S(s)); }
void sfq_reset(int64_t s) { sqlite3_reset(S(s)); sqlite3_clear_bindings(S(s)); }
int32_t sfq_readonly(int64_t s) { return sqlite3_stmt_readonly(S(s)); }
int32_t sfq_params(int64_t s) { return sqlite3_bind_parameter_count(S(s)); }
int32_t sfq_bind_null(int64_t s, int32_t i) { return sqlite3_bind_null(S(s), i); }
int32_t sfq_bind_int(int64_t s, int32_t i, int64_t v) { return sqlite3_bind_int64(S(s), i, v); }
int32_t sfq_bind_double(int64_t s, int32_t i, double v) { return sqlite3_bind_double(S(s), i, v); }
int32_t sfq_bind_text(int64_t s, int32_t i, moonbit_bytes_t v) {
  return sqlite3_bind_text(S(s), i, (const char *)v, (int)Moonbit_array_length(v), SQLITE_TRANSIENT);
}
int32_t sfq_bind_blob(int64_t s, int32_t i, moonbit_bytes_t v) {
  return sqlite3_bind_blob(S(s), i, (const void *)v, (int)Moonbit_array_length(v), SQLITE_TRANSIENT);
}
int32_t sfq_step(int64_t s) { return sqlite3_step(S(s)); }
int32_t sfq_columns(int64_t s) { return sqlite3_column_count(S(s)); }
moonbit_bytes_t sfq_column_name(int64_t s, int32_t i) { return text_of(sqlite3_column_name(S(s), i)); }
int32_t sfq_type(int64_t s, int32_t i) { return sqlite3_column_type(S(s), i); }
int64_t sfq_int(int64_t s, int32_t i) { return sqlite3_column_int64(S(s), i); }
double sfq_double(int64_t s, int32_t i) { return sqlite3_column_double(S(s), i); }
/// A text's bytes (UTF-8) or a blob's.
moonbit_bytes_t sfq_text(int64_t s, int32_t i) {
  const unsigned char *p = sqlite3_column_text(S(s), i);
  return bytes_of(p, sqlite3_column_bytes(S(s), i));
}
moonbit_bytes_t sfq_blob(int64_t s, int32_t i) {
  const void *p = sqlite3_column_blob(S(s), i);
  return bytes_of(p, sqlite3_column_bytes(S(s), i));
}
