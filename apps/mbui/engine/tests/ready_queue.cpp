#include "../ready_queue.h"
#include <cassert>

int main() {
  ReadyQueue<int> queue;
  int task = 0;
  uint64_t timer = 0;
  double wait = 0;
  auto next = [&](double now) {
    task = 0;
    timer = 0;
    return queue.take(now, task, timer, wait);
  };

  // At the same clock reading, work already posted precedes a later timer,
  // while a task posted after that timer does not keep the timer waiting.
  queue.post(1, 10);
  queue.setTimer(11, 10);
  queue.post(2, 10);
  assert(next(10) && task == 1);
  assert(next(10) && timer == 11);
  assert(next(10) && task == 2);
  assert(!next(10) && wait == -1);

  // A timer due during an earlier task precedes inputs arriving after its
  // deadline, but not an input that was already waiting.
  queue.post(3, 14);
  queue.setTimer(12, 20);
  queue.post(4, 21);
  assert(next(21) && task == 3);
  assert(next(21) && timer == 12);
  assert(next(21) && task == 4);

  // Clearing and resetting a timer at the same deadline leaves only the new
  // timer, with its new position among equally ready work.
  queue.setTimer(13, 30);
  queue.clearTimer(13);
  queue.post(5, 30);
  queue.setTimer(13, 30);
  assert(next(30) && task == 5);
  assert(next(30) && timer == 13);
  assert(!next(30) && wait == -1);

  // Timers are ordered by their deadline even if set in the other order.
  queue.setTimer(15, 52);
  queue.setTimer(16, 51);
  queue.post(6, 52);
  assert(next(52) && timer == 16);
  assert(next(52) && timer == 15);
  assert(next(52) && task == 6);

  queue.setTimer(14, 40);
  assert(!next(35) && wait == 5);
  queue.clear();
  assert(!next(40) && wait == -1);
}
