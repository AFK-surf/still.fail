---
name: stillfail-cron
description: Run something on a schedule or at a set time (每天 9 点、每周一、每 30 分钟、明天提醒我, cron, a daily report, a reminder, a periodic check) with a still.fail job. Read it before setting up any scheduled or recurring task, instead of crontab, launchd, systemd timers or your runtime's own scheduler.
---

# Scheduled tasks

A schedule is one background job (stillfail-jobs) in the chat that asked for it: a shell loop that checks the clock and,
when a run is due, either runs a command itself or wakes you with `stillfail-job notify` to do the work. Set it up in
one turn, without asking how: pick what the request leaves open and say it in the confirmation.

Do not use crontab, launchd, systemd timers, Windows Task Scheduler, or your runtime's scheduler (Claude Code's
CronCreate, /loop, ScheduleWakeup; Codex automations): nobody sees them in still.fail, they cannot wake you in this
chat, they outlive or die apart from it, and a runtime's scheduler lives only as long as your process, which the
station ends when the chat is idle. A `waiting` turn's seconds are not a timer either.

## 1. Write the loop

Write it to `cron/<name>.sh` in the session workspace (`<name>` short, e.g. `daily-report`). The loop compares numbers
made with `date` (same on macOS, Linux and Git's sh on Windows): no `date -d`/`date -j`, no `sleep` until a time.

```sh
#!/bin/sh
# 每天 09:00 (Asia/Shanghai): the daily report for #ops
export TZ=Asia/Shanghai
cd "$(dirname "$0")"
last=daily-report.last
while :; do
  slot=$(date +%F)                                   # this run's period: one a day
  if [ "$(date +%H%M)" -ge 900 ] && [ "$(cat "$last" 2>/dev/null)" != "$slot" ]; then
    echo "$slot" > "$last"
    stillfail-job notify "Scheduled run $slot of daily-report: <what to do, and where to post it>"
  fi
  sleep 30
done
```

The other schedules change only `slot` and the condition:

| Schedule | `slot` | due when |
|---|---|---|
| every day at 09:00 | `$(date +%F)` | `[ "$(date +%H%M)" -ge 900 ]` |
| weekdays at 18:30 | `$(date +%F)` | `[ "$(date +%u)" -le 5 ] && [ "$(date +%H%M)" -ge 1830 ]` |
| Mondays at 10:00 | `$(date +%G-W%V)` | `[ "$(date +%u)" -eq 1 ] && [ "$(date +%H%M)" -ge 1000 ]` |
| 1st of the month at 08:00 | `$(date +%Y-%m)` | `[ "$(date +%d%H%M)" -ge 10800 ]` |
| every hour at :05 | `$(date +%F-%H)` | `[ "$(date +%M)" -ge 5 ]` |
| every 30 minutes | `$(( $(date +%s) / 1800 ))` | always |
| once, 2026-10-20 09:00 | `once` | `[ "$(date +%Y%m%d%H%M)" -ge 202610200900 ]`; then `echo` the instruction and `exit 0` instead of notifying: the job's end wakes you with its output |

Write numbers without leading zeros (`900`, not `0900`). The `.last` file is what makes it safe: the job is started
again after a station or machine restart and a run is never repeated, and one missed while the machine was off or
asleep runs once when it is back within the same period (the same day for a daily one); older ones are not made up.
Created after today's time has passed, a daily schedule would run at once: when the person did not ask for a run now,
write the current slot to `.last` before starting the job, so the first run is the next one.

Time zone: the person's, set with `TZ` (a person writing Chinese is most likely on Asia/Shanghai; the station's own
zone may differ). Name it in the confirmation so they can correct it.

## 2. What a run does

- **A command** (a backup, a sync, fetching a file): run it in the loop in place of the notify line, and tell only
  what matters: `out=$(<command> 2>&1) || stillfail-job notify "daily-backup $slot failed: $(printf '%s' "$out" | tail -5)"`.
  Nothing wakes you on success unless the person wants to hear of each run.
- **Work for you** (a report, a summary, checking something and saying what changed, a reminder): the notify wakes
  you. Make its words a complete instruction: the chat may have been compacted or be in a new session by then, so
  name what to do, where to post (the thread address), and anything to compare against (a file in the workspace).

## 3. Start it and confirm

- `job_start` with `command: "sh cron/<name>.sh"`, `name` (e.g. `定时 · 每天 9:00 日报`) and `watch: true`: the chat is
  then listed under 监控中, is never archived for being idle, and is asked about before archiving by hand (archiving
  stops its jobs, and the schedule with them).
- Post once in the chat: what runs, the schedule with its time zone, when the next run is, and that telling you in
  this chat changes or stops it. Give the post a title naming the schedule (e.g. `定时 · 每天 9:00 日报`). End the
  turn `waiting` (for: the schedule, `watch: true`): only its notify, its end or a message wakes you.
- On each run: do the work, post the result in the chat it is for, and end `waiting` again (`watch: true`). A failed run: say so
  there, fix the script if it is the cause, and restart the job.

## Changing, stopping, several

- `job_list` shows the schedules running; change one by editing its script, `job_stop` and `job_start` again (the
  `.last` file carries over). Stop it with `job_stop` when asked, then end the chat normally.
- Several schedules in one chat are several jobs (at most 20 jobs per chat).
- A schedule runs on this station, and only while its machine is on: a laptop that sleeps runs a missed run when it
  wakes. If it must run on time on another machine, the run can wake you and you use `station_task` there; or open the
  chat on that station.
