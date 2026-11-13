// src/host/linux_station.c as the app's native call answers it (scripts/linux_station_test.sh runs it in a home of its
// own): `read` says this machine's station (`STATIONCHECK read <json>`); `stop` the same, then stops it and, once
// nothing is being done to it (told by what it posts as it changes, never a wait of a time), says it again
// (`STATIONCHECK after <json>`).
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// what the station's file posts as it changes (mbui's post.h in the app): counted, each one told to the waiting main
static pthread_mutex_t posted_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t posted_cond = PTHREAD_COND_INITIALIZER;
static int posted;
void mb_post(const char *channel, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  (void)channel, (void)json, (void)len, (void)bytes, (void)blen;
  pthread_mutex_lock(&posted_lock);
  posted++;
  pthread_cond_broadcast(&posted_cond);
  pthread_mutex_unlock(&posted_lock);
}

#include "../src/host/linux_station.c"

// (the runtime's way out, which a MoonBit program's own C gives it; here none comes)
_Noreturn void moonbit_panic(void) { abort(); }

static char *said(void) { return station_utf8(sf_station_said()); }

int main(int argc, char **argv) {
  const char *how = argc > 1 ? argv[1] : "read";
  char *now = said();
  printf("STATIONCHECK read %s\n", now);
  if (strcmp(how, "stop") != 0) return 0;
  pthread_mutex_lock(&posted_lock);
  int seen = posted;
  pthread_mutex_unlock(&posted_lock);
  sf_station_act(station_mstr("stop"));
  for (;;) {
    g_free(now);
    now = said();
    if (!strstr(now, "\"doing\"")) break;
    pthread_mutex_lock(&posted_lock);
    while (posted == seen) pthread_cond_wait(&posted_cond, &posted_lock);
    seen = posted;
    pthread_mutex_unlock(&posted_lock);
  }
  printf("STATIONCHECK after %s\n", now);
  g_free(now);
  return 0;
}
