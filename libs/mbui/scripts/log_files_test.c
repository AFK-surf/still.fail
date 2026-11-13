// src/host/log_files.h's tests: what a line may keep, the queue, which file:
//   cc -Wall -I src/host scripts/log_files_test.c -o out/log_files_test && out/log_files_test
#include <stdio.h>
#include <stdlib.h>
#include "log_files.h"

static int failed;

#define CHECK(c)                                                  \
  do {                                                            \
    if (!(c)) {                                                   \
      fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #c); \
      failed = 1;                                                 \
    }                                                             \
  } while (0)

static char cleaned[LF_LINE_MOST + 1];
static const char *clean(const char *s) {
  size_t n = log_clean(s, strlen(s), cleaned, LF_LINE_MOST);
  cleaned[n] = 0;
  return cleaned;
}
#define SAME(in, want)                                                                  \
  do {                                                                                  \
    const char *got_ = clean(in);                                                       \
    if (strcmp(got_, want) != 0) {                                                      \
      fprintf(stderr, "%s:%d: clean(%s)\n  gave %s\n  want %s\n", __FILE__, __LINE__, in, got_, want); \
      failed = 1;                                                                       \
    }                                                                                   \
  } while (0)

static void test_clean(void) {
  // what goes through as it is: a diagnosis needs these
  SAME("no Direct3D 11 device", "no Direct3D 11 device");
  SAME("shader vs_main: error X3000", "shader vs_main: error X3000");
  SAME("frames: fps=60 work_avg=1.2ms nodes=4021 span=5.0s", "frames: fps=60 work_avg=1.2ms nodes=4021 span=5.0s");
  SAME("win: stream 3: sound 40 ms apart", "win: stream 3: sound 40 ms apart");
  SAME("status=500 exit code: 3", "status=500 exit code: 3");
  SAME("回调失败 token 用尽了", "回调失败 token 用尽了");
  SAME("a_long_snake_case_name_with_no_digit_in_it_at_all", "a_long_snake_case_name_with_no_digit_in_it_at_all");
  // links: what comes through this host's log (mb_host_open_url; "AUTH_URL …", "link opens …", "notice tapped …")
  SAME("AUTH_URL https://accounts.google.com/o/oauth2/auth?client_id=1&state=abc", "AUTH_URL https://accounts.google.com/<cut>");
  SAME("link opens someapp://share/abcd#key=hunter2 (signed out)", "link opens someapp://share/<cut> (signed out)");
  SAME("https://user:pw@host.example/x", "https://host.example/<cut>");
  SAME("https://host.example", "https://host.example");
  SAME("see \"https://a.example/p?x=1\" there", "see \"https://a.example/<cut>\" there");
  // names and their values
  SAME("password=hunter2 next", "password=<cut> next");
  SAME("x PASSWORD : hunter2", "x PASSWORD : <cut>");
  SAME("{\"accessToken\":\"ab c\",\"n\":1}", "{\"accessToken\":<cut>,\"n\":1}");
  SAME("{\\\"token\\\":\\\"abc\\\",\\\"n\\\":1}", "{\\\"token\\\":<cut>,\\\"n\\\":1}");
  SAME("refresh_token=a&b=c", "refresh_token=<cut>&b=c");
  SAME("api_key: sk1", "api_key: <cut>");
  SAME("Authorization: Bearer a b c", "Authorization: <cut>");
  SAME("set-cookie: a=b; c=d", "set-cookie: <cut>");
  SAME("sent Bearer abc123 then", "sent Bearer <cut> then");
  // long runs of what keys are made of, whatever names them
  SAME("failed sk-ant-api03-AbCdEf0123456789AbCdEf0123456789 x", "failed <cut> x");
  SAME("ghp_0123456789abcdefghij0123456789abcdef", "<cut>");
  SAME("a eyJhbGciOi0123456789012345678901234567.eyJzdWIiOi0123456789012345678901234567.c", "a <cut>.<cut>.c");
  SAME("Ab0/Ab0/Ab0/Ab0/Ab0/Ab0/Ab0/Ab0/Ab0/Ab0/Ab0/", "<cut>");
  SAME("page/chat/1/list/row/2/inner/box/item/label/x", "page/chat/1/list/row/2/inner/box/item/label/x");
  // a person's
  SAME("SIGN_IN taken in: ana.b+x@mail.example.com", "SIGN_IN taken in: <email>");
  SAME("AUTH_DONE ana@example.org!", "AUTH_DONE <email>!");
  SAME("a@b not one", "a@b not one");
  SAME("its files in C:\\Users\\ana\\AppData\\x", "its files in C:\\Users\\<cut>\\AppData\\x");
  SAME("\"C:\\\\Users\\\\ana\\\\x\"", "\"C:\\\\Users\\\\<cut>\\\\x\"");
  // not kept at all: a developer's whole messages
  CHECK(log_clean("[core trace] says {}", 20, cleaned, LF_LINE_MOST) == 0);
  CHECK(log_clean("[core debug] x", 14, cleaned, LF_LINE_MOST) == 0);
  // one line, nothing a terminal would act on
  SAME("a\nb\033[2Jc", "a b [2Jc");
  // at most a line's, cut on a character's bound
  size_t big = LF_LINE_MOST + 100;
  char *long_line = malloc(big);
  memset(long_line, ' ', big);
  memcpy(long_line + LF_LINE_MOST - 1, "\xE4\xB8\xAD", 3);
  size_t n = log_clean(long_line, big, cleaned, LF_LINE_MOST);
  CHECK(n == LF_LINE_MOST - 1);
  // a grown line stops at its room
  for (size_t i = 0; i + 3 <= big; i += 3) memcpy(long_line + i, "a=b", 3);
  n = log_clean(long_line, big, cleaned, 16);
  CHECK(n <= 16);
  free(long_line);
}

static void test_queue(void) {
  unsigned char ring[64];
  lf_queue q = {ring, sizeof ring, 0, 0, 0};
  char out[LF_LINE_MOST];
  int kind = -1;
  uint64_t when = 0;
  CHECK(lf_pop(&q, &kind, &when, out) == -1);
  // oldest first, kind and time kept, round the ring's end many times
  for (uint64_t i = 0; i < 100; i++) {
    CHECK(lf_push(&q, (int)(i & 1), i * 7, "abcdefghijklmnop", 16));
    CHECK(lf_push(&q, 1, i, "xy", 2));
    CHECK(lf_pop(&q, &kind, &when, out) == 16);
    CHECK(kind == (int)(i & 1) && when == i * 7 && memcmp(out, "abcdefghijklmnop", 16) == 0);
    CHECK(lf_pop(&q, &kind, &when, out) == 2);
    CHECK(kind == 1 && when == i && memcmp(out, "xy", 2) == 0);
  }
  CHECK(q.used == 0 && q.dropped == 0);
  // full: what does not fit goes, counted; what it holds is unharmed, and it never holds more than it can
  int in = 0;
  for (int i = 0; i < 20; i++) {
    in += lf_push(&q, 0, (uint64_t)i, "0123456789", 10);
    CHECK(q.used <= q.cap);
  }
  CHECK(in == 3);
  CHECK(q.dropped == 17);
  for (int i = 0; i < in; i++) {
    CHECK(lf_pop(&q, &kind, &when, out) == 10);
    CHECK(when == (uint64_t)i && memcmp(out, "0123456789", 10) == 0);
  }
  // a line past the most is held as the most
  static unsigned char big_ring[3 * LF_LINE_MOST];
  lf_queue b = {big_ring, sizeof big_ring, 0, 0, 0};
  static char big[LF_LINE_MOST + 50];
  CHECK(lf_push(&b, 0, 0, big, sizeof big));
  CHECK(lf_pop(&b, &kind, &when, out) == LF_LINE_MOST);
}

static void test_files(void) {
  unsigned day, seq;
  char name[LF_NAME_MOST];
  lf_name(name, "perf", 20261104, 2);
  CHECK(strcmp(name, "perf-20261104-002.log") == 0);
  CHECK(lf_parse(name, "perf", &day, &seq) && day == 20261104 && seq == 2);
  CHECK(!lf_parse(name, "log", &day, &seq));
  CHECK(!lf_parse("perf-20261104-002.log.txt", "perf", &day, &seq));
  CHECK(!lf_parse("perf-2026110x-002.log", "perf", &day, &seq));
  CHECK(!lf_parse("perf-on", "perf", &day, &seq));

  // none yet; the day's first; the day's last while it holds what is to come, within the most; the next past it; a
  // new day's first; another stream's, and other files, are not its
  CHECK(lf_pick(NULL, 0, "log", 20261104, 100, 10, name) == 1 && strcmp(name, "log-20261104-001.log") == 0);
  lf_file f[5] = {{"log-20261104-002.log", 90}, {"log-20261104-001.log", 100}, {"perf-20261104-009.log", 1}, {"log-20261103-007.log", 1}, {"perf-on", 0}};
  CHECK(lf_pick(f, 5, "log", 20261104, 100, 10, name) == 0 && strcmp(name, "log-20261104-002.log") == 0);
  CHECK(lf_pick(f, 5, "log", 20261104, 100, 11, name) == 1 && strcmp(name, "log-20261104-003.log") == 0);
  CHECK(lf_pick(f, 5, "log", 20261105, 100, 10, name) == 1 && strcmp(name, "log-20261105-001.log") == 0);

  // those beyond the kept: the oldest by day, then by number, nothing of another stream's; removed one by one, the
  // newest are what is left
  lf_file g[6] = {{"log-20261104-010.log", 1}, {"log-20261104-002.log", 1}, {"log-20261103-099.log", 1}, {"perf-20261001-001.log", 1}, {"log-20261105-001.log", 1}, {"perf-on", 0}};
  int count = 6, i;
  i = lf_oldest(g, count, "log", 3);
  CHECK(i == 2);
  g[i] = g[--count];
  i = lf_oldest(g, count, "log", 3);
  CHECK(i < 0);
  i = lf_oldest(g, count, "log", 2);
  CHECK(i >= 0 && strcmp(g[i].name, "log-20261104-002.log") == 0);
  CHECK(lf_oldest(g, count, "perf", 3) < 0);
}

// What a file comes to as lines go on: over any number of them, at most `kept` files, none past the most.
static void test_bound(void) {
  lf_file disk[LF_FILES_MOST];
  int count = 0;
  const unsigned long long most = 1000;
  const size_t line = 73;
  for (int k = 0; k < 20000; k++) {
    char name[LF_NAME_MOST];
    unsigned day = 20261104 + (unsigned)(k / 5000);
    if (lf_pick(disk, count, "log", day, most, line, name)) {
      CHECK(count < LF_FILES_MOST);
      snprintf(disk[count].name, LF_NAME_MOST, "%s", name);
      disk[count++].bytes = 0;
      for (int i; (i = lf_oldest(disk, count, "log", 3)) >= 0;) disk[i] = disk[--count];
    }
    int found = 0;
    for (int i = 0; i < count; i++)
      if (strcmp(disk[i].name, name) == 0) disk[i].bytes += line, found = 1;
    CHECK(found);
    CHECK(count <= 3);
    for (int i = 0; i < count; i++) CHECK(disk[i].bytes <= most);
  }
}

int main(void) {
  test_clean();
  test_queue();
  test_files();
  test_bound();
  if (failed) return 1;
  printf("log_files: ok\n");
  return 0;
}
