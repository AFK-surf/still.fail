---
name: stillfail-jobs
description: Background jobs and web services on the still.fail station (job_start, job_list, job_log, job_stop, stillfail-job notify). Use when work outlives a turn (long builds, test suites, data jobs, watchers) or when people should see or use something in a browser (a page, prototype, chart, report, dashboard, tool UI) — instead of blocking a turn, pasting walls of output, or describing a UI in words.
---

# Background jobs and web services

The station runs jobs for you apart from your turns: each in its own process group, its output in a log, kept across your
turns and across restarts of the station (one that did not survive, say the machine restarted, is started again). You
hear when one ends, and whatever it says on the way. A job with a
port is a web service: kept up (started again if it ends) and opened by the workspace's members through its link.

## Background jobs: when

Use `job_start` (no port) for work that takes longer than a turn should, or that you want to keep an eye on:

- builds, full test suites, benchmarks, migrations, data processing, downloads, anything over a minute or two;
- watchers and loops (poll something, retry until it works, re-run on change);
- several independent pieces of work at once.

Not for quick commands: run those directly. Not for work that must finish before you can answer: wait for it in the turn.

## Background jobs: how

- `job_start` with `command` (run by `sh -c`), a short `name`, and `cwd` (default: this session's workspace). Keep the
  workspace as the place for clones and outputs.
- Tell the people waiting that it runs and what you will tell them, then end the turn (`chat_state` "waiting", or
  `chat_post` kind "need_help" only if they must act). You do not need to stay in the turn: you are woken when the job ends.
- For a long job, have it report milestones or trouble with `stillfail-job notify "<words>"` from inside the command (for
  example `make all && stillfail-job notify "build done, running tests" && make test`; `ember-job` is the same command). Each notice reaches you as a message
  via="ember"; act on it (relay what matters to people, fix and restart on failure). Do not notify for every line.
- When it ends you get its exit code and last lines. Read more with `job_log` (`lines` up to 1000). `job_list` shows this
  session's jobs and their states; `job_stop` ends one.
- A job's end is not the people's news unless it matters to them: tell them results, failures they must know about, and
  what happens next.

## Long-running watches

When someone asks you to keep an eye on something for a long while (a CI run, a deploy, a metric, a review queue), start
it with `job_start` and `watch: true`: a loop that checks and `stillfail-job notify`s on changes. While the watch runs:

- its chat is a watching chat: listed under the chat list's 监控中 filter, never archived for being idle, and asked about
  before someone archives it by hand;
- end your turn with `chat_state` waiting (or a post that ends it): you are not asked again when the wait runs out, only when the
  watch notifies, ends, or someone writes;
- name the chat for it: give your next `chat_post` a title that says what it watches (e.g. 「监控 · PR #482 的 CI」); a
  chat with a watch running may be renamed so at once.

Stop the watch (`job_stop`) when it is no longer needed; the chat is then an ordinary one again.

## Web services: when

Use `job_start` with a `port` when what you made should be looked at or used in a browser, rather than read as text:

- a front-end page, prototype or design you built or changed;
- interactive charts, reports, dashboards or data explorers;
- a docs site, a storybook, a preview build;
- a small tool with a UI, or the admin/debug page of a service you are running;
- something people will open again or keep watching.

Not for a one-off answer (reply with text or a file), a single static image (send the image file), or a service only you
need to reach (a plain background job is enough).

## Web services: how

- `job_start` with `command`, `name`, `port` (1024–65535). The command must listen on that port; `$PORT` holds it, and
  127.0.0.1 is enough (for example `python3 -m http.server $PORT`, `npm run dev -- --port $PORT --host 127.0.0.1`).
- Check it answers before telling anyone: `curl -sf http://127.0.0.1:<port>/` (retry a few seconds while it starts);
  look at `job_log` if it does not.
- Give it a name people will recognise (`name`): the pages show services by their names, never their ports. When you
  speak of it, use that name and the link; the port is the station's business, not theirs.
- Post the returned `link` where people asked, saying what it is (in Slack: `<link|what it is>`). The link opens the
  service beside this session in still.fail, for the workspace's members only: it is not a public URL; do not hand it out as
  one.
- One service per port. To restart after changes, `job_stop` it and start it again (or use a dev server that reloads by
  itself). If it keeps crashing, the station restarts it with growing pauses and tells you each time: read `job_log`,
  fix, restart.
- Stop services nobody needs any more with `job_stop`.
- How people see it: in a frame beside the chat, on an origin of its own, with requests relayed through the station
  (each answer passed on whole). So the service must work at its own root paths (`/`, not under a prefix), and
  WebSockets (a dev server's live reload) and streamed answers (server-sent events, long polls) do not get through:
  turn hot reload off, and expect a page that relies on a live stream to show only what it reads.

## Work on another station

When a task needs another machine's tools or resources, use `station_list` to discover stations in this workspace and
`station_list {station}` to check a target's capabilities and whether it accepts tasks from here. Permission belongs to
the target administrator; do not enable `remoteTasks.allow` yourself just to get a task through.

Use `station_task` to prepare a named shell task with a stable `key`, upload input files with `station_file`, then start
it with the same key. Commands run as the target station's OS user in a task directory, not in a sandbox. Include exact
versions in the inputs and command (for Git, upload a bundle or archive and check out the intended revision).

`station_task` can list, inspect, tail or stop this session's remote tasks. After start, completion and job notices come
back to this session even across reconnects and station restarts; you do not need a local polling job. While it runs,
end the turn with `chat_state` waiting, naming the remote task. Download artifacts with `station_file` after it ends,
and post them in the conversation that asked for the work.

After a timeout, query or retry the **same** key: the command may already have run. A task with a lost process is not
started again automatically; `failed` with no exit code can mean an uncertain result. Inspect before choosing a new
key. Uploads can be repeated before starting; downloads create new files and never overwrite existing local files.
