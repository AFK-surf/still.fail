// src/host/win_collate.h: the order people read names in, as the core asks it (text.collate), on Windows. Built and run
// by `scripts/win.sh collate` (mbui.yml's windows job). Exit 0 when Chinese names come in pinyin's order in Chinese,
// case aside, numbers by their value, equal names one place, and an ask with a name that is no string is said to be
// wrong.
#include "win_collate.h"

static int check(const char *what, const int *got, const int *want, int n) {
  for (int i = 0; i < n; i++) {
    if (got[i] == want[i]) continue;
    printf("collate: %s:", what);
    for (int k = 0; k < n; k++) printf(" %d", got[k]);
    printf(", not");
    for (int k = 0; k < n; k++) printf(" %d", want[k]);
    printf("\n");
    return 1;
  }
  return 0;
}

static int said(const char *what, const char *ask, const char *want) {
  char *got = win_collate_answer(ask, strlen(ask), L"en-US");
  int bad = !got || strcmp(got, want) != 0;
  if (bad) printf("collate: %s: %s, not %s\n", what, got ? got : "(none)", want);
  free(got);
  return bad;
}

int main(void) {
  int bad = 0, place[8];
  // 张 zhāng, 李 lǐ, 阿 ā: by pinyin, not by their codes (张 U+5F20 < 李 U+674E < 阿 U+963F)
  const WCHAR *zh[] = {L"\x5f20\x4e09", L"\x674e\x56db", L"\x963f"};
  win_collate(zh, 3, L"zh-CN", place);
  bad |= check("pinyin", place, (int[]){2, 1, 0}, 3);
  // A and a one place; a2 before a10
  const WCHAR *en[] = {L"a10", L"A", L"a2", L"a", L"b"};
  win_collate(en, 5, L"en-US", place);
  bad |= check("case and numbers", place, (int[]){3, 0, 2, 0, 4}, 5);
  bad |= said("the ask answered", "{\"names\":[\"b\",\"a\"]}", "{\"value\":[1,0]}");
  bad |= said("its escapes read", "{\"names\": [\"\\u0062\", \"z\", \"a\\\"b\"]}", "{\"value\":[1,2,0]}");
  bad |= said("none", "{\"names\":[]}", "{\"value\":[]}");
  bad |= said("a name that is no string", "{\"names\":[\"a\",1]}", "{\"error\":\"text.collate: names are strings\"}");
  if (!bad) printf("collate: names in the order people read them\n");
  return bad;
}
