#include <time.h>

// a monotonic clock in milliseconds (performance.now()'s counterpart)
double sb_now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
  return (double)ts.tv_sec * 1e3 + (double)ts.tv_nsec / 1e6;
}

#include <mach/mach.h>

// the process's resident memory in MB (what Activity Monitor's memory column follows)
double sb_rss_mb(void) {
  mach_task_basic_info_data_t info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
  return (double)info.resident_size / 1048576.0;
}
