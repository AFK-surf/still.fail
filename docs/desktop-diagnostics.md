# Desktop diagnostics

The primary desktop instance starts local diagnostics after taking its single-instance lock, before creating windows
or utility processes. A second launch cannot overwrite the running instance's marker. This does not change station
logging (`~/.stillfail/stillfail.log`) or the web app's existing error reporting.

Files are under `app.getPath("userData")/diagnostics`. On Windows beta this is
`%APPDATA%/youdid.wtf/diagnostics`; an isolated launch's `STILLFAIL_USER_DATA` also isolates diagnostics.

- `desktop.log`: JSON lines, with UTC timestamp, run ID, PID and app/Electron versions at startup. Rotates at 2 MiB,
  keeping two older files (`.1`, `.2`). Records window close requests, completed closes, quit events, update-driven
  quits, renderer/GPU/utility process exits, core exceptions and main-process uncaught exceptions. Error stacks are
  capped; message content, navigation URLs, command-line arguments and console output are not routinely collected.
- `running.json`: written at startup, removed only on successful Electron `quit`, and retained after a fatal exception.
  A marker left behind produces `previous-run-incomplete` on next launch. It means the previous run did not finish
  normally, not proof of a crash: forced termination, power loss and an interrupted shutdown can also leave it.
- `crashes/`: Electron Crashpad's local minidumps (`uploadToServer: false`). These are not uploaded. Dumps can contain
  process memory; share them deliberately and remove old dumps when no longer needed. File layout is Crashpad's own.

Diagnostics are best effort on an unwritable/full disk. A hard kill or power loss may produce no dump. Normal close
events do not identify who requested the close. Node fatal exceptions are observed with `uncaughtExceptionMonitor`,
without adding a handler that swallows them or changes Node's rejection behavior.

Validation: `node --test apps/desktop/test/diagnostic-log.test.ts`; with desktop dependencies and Electron installed,
`node apps/desktop/test/diagnostics.mjs` runs an isolated hidden app through normal/abrupt quits, a JS exception, and
real renderer/main-process crashes. It starts no station and uses no production app data.
