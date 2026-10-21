// What the bench needs from the system: the monotonic clock, and its two settings from the environment.
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

// in nanoseconds
double awly_now_ns(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

// AWLY_ONLY: the index of the one workload to run (-1: all)
int32_t awly_only(void) {
  const char *s = getenv("AWLY_ONLY");
  return s ? atoi(s) : -1;
}

// AWLY_PROFILE: seconds to lay that workload out over and over, for a profiler, instead of timing it (0: time it)
double awly_profile(void) {
  const char *s = getenv("AWLY_PROFILE");
  return s ? atof(s) : 0.0;
}
