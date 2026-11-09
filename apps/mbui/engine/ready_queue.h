// The core's thread takes the oldest ready work, whether it came from the
// host or a timer. All times use the same monotonic clock; calls are made
// while the host holds its queue mutex.
#pragma once

#include <cstdint>
#include <deque>
#include <map>
#include <unordered_map>
#include <utility>

template <typename Task>
class ReadyQueue {
  using Key = std::pair<double, uint64_t>;
  struct Posted {
    Key ready;
    Task task;
  };

 public:
  void post(Task task, double now) { tasks_.push_back({{now, order_++}, std::move(task)}); }

  void setTimer(uint64_t id, double due) {
    Key ready{due, order_++};
    timers_[id] = ready;
    dues_.emplace(ready, id);
  }

  void clearTimer(uint64_t id) { timers_.erase(id); }

  // Returns work when available. Otherwise waitMs is the time to the next
  // timer, or -1 when there is no timer. Equal clock readings retain the
  // order in which work was posted or a timer was set.
  bool take(double now, Task& task, uint64_t& timer, double& waitMs) {
    while (!dues_.empty()) {
      auto first = dues_.begin();
      auto live = timers_.find(first->second);
      if (live != timers_.end() && live->second == first->first) break;
      dues_.erase(first);
    }

    auto first = dues_.begin();
    bool due = first != dues_.end() && first->first.first <= now;
    if (!tasks_.empty() && (!due || tasks_.front().ready < first->first)) {
      task = std::move(tasks_.front().task);
      tasks_.pop_front();
      return true;
    }
    if (due) {
      timer = first->second;
      timers_.erase(timer);
      dues_.erase(first);
      return true;
    }
    waitMs = first == dues_.end() ? -1 : first->first.first - now;
    return false;
  }

  void clear() {
    tasks_.clear();
    timers_.clear();
    dues_.clear();
  }

 private:
  uint64_t order_ = 0;
  std::deque<Posted> tasks_;
  std::unordered_map<uint64_t, Key> timers_;
  std::map<Key, uint64_t> dues_;
};
