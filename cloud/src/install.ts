// ember station's installer, served at /install.sh: `curl -fsSL <origin>/install.sh | sh -s -- <token>` on the machine
// that is to be a station. It gets the release for the machine (scripts/release.sh put it in the releases bucket,
// served at /releases/<file>), puts it in ~/.ember/app (the data around it stays), links `ember` into ~/.local/bin,
// joins the workspace the token is for, and runs the station as a service of the user (launchd), started at login and
// again if it stops. Claude Code and Codex are the machine's own: it says how to get them when they are missing.
// On Linux the service is a systemd user service (lingering, so it runs with no one logged in); with no user systemd
// (a container, another init) the station is started in the background, and said not to come back after a reboot.
// Without a token, on a station already in a workspace, it updates the station (`ember update` runs it so). An update
// does not stop the agents when it can help it: with the service's definition unchanged, the running station hands
// over to the new release in its own process (SIGUSR2, mesh/station/src/main.rs), turns, runtimes and jobs going on;
// else, or if that fails, the station is first drained (SIGUSR1: no new turns, and it says once none runs), then
// restarted. A station older than these says neither (no run/station.json): it is restarted as before.

/** The installer for an ember cloud at `origin`. */
export function installScript(origin: string): string {
  return SCRIPT.replaceAll("__ORIGIN__", origin);
}

/** A release's file, as the bucket keeps it: ember-station-<platform>.tar.gz. */
export const RELEASE_FILE = /^ember-station-(darwin-arm64|linux-x64|linux-arm64)\.tar\.gz$/;

/**
 * The apps' builds, as scripts/release.sh puts them beside the station's: what each app's updater reads for the
 * latest (the desktop app's electron-updater, the Android app's Updates.kt), and the files it names.
 */
const APP_FILES: [RegExp, string][] = [
  [/^desktop\/latest-mac\.yml$/, "text/yaml; charset=utf-8"],
  [/^desktop\/ember-[0-9.]+-arm64-mac\.zip$/, "application/zip"],
  [/^android\/latest\.json$/, "application/json"],
  [/^android\/ember-[0-9]+\.apk$/, "application/vnd.android.package-archive"],
];

/** The content type a file of the releases bucket is served with; null for a name that is not one of its files. */
export function releaseType(file: string): string | null {
  if (RELEASE_FILE.test(file)) return "application/gzip";
  return APP_FILES.find(([name]) => name.test(file))?.[1] ?? null;
}

// A variable is always braced where words follow it ("\${app}（…）"): sh may take the first byte of a non-ASCII
// character for part of its name, and set -u stops the script there.
const SCRIPT = `#!/bin/sh
# Installs ember's station on this machine and joins it to a workspace in ember cloud:
#   curl -fsSL __ORIGIN__/install.sh | sh -s -- <token>
# The token comes from 「添加 station」 in ember. Running it again updates ember and keeps its data (~/.ember).
set -eu
origin="__ORIGIN__"
token="\${1:-}"
data="\${EMBER_DATA:-$HOME/.ember}"
# A station already in a workspace is only updated: no token, and it stays the same station.
if [ -z "$token" ] && [ ! -f "$data/mesh/cloud.json" ]; then
  echo "用法：curl -fsSL $origin/install.sh | sh -s -- <token>（token 在 ember 的「添加 station」里生成）" >&2
  echo "已经加入 workspace 的 station 更新时不需要 token：ember update" >&2
  exit 2
fi
os=$(uname -s)
case "$os-$(uname -m)" in
  Darwin-arm64) platform=darwin-arm64 ;;
  Linux-x86_64) platform=linux-x64 ;;
  Linux-aarch64|Linux-arm64) platform=linux-arm64 ;;
  *) echo "暂时只支持 macOS（Apple 芯片）和 Linux（x64、arm64）的机器，这台是 $(uname -s) $(uname -m)。" >&2; exit 1 ;;
esac
app="$data/app"
label="org.3720.ember.station"
plist="$HOME/Library/LaunchAgents/$label.plist"
unit_dir="\${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit="ember-station.service"
# Whether this Linux has a systemd for the user to run services in (not a container's, not another init).
user_systemd() { command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "下载 ember station…"
curl -fL --progress-bar "$origin/releases/ember-station-$platform.tar.gz" -o "$tmp/ember.tar.gz"
tar -xzf "$tmp/ember.tar.gz" -C "$tmp"

# The agents it starts are found on this PATH (Claude Code, Codex, and what they run).
agent_path="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH:/usr/bin:/bin"
# The service's definition, as this release has it: written below, and compared with the one running now.
if [ "$os" = Darwin ]; then
  service_file="$plist"
  cat > "$tmp/service" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key><array><string>$app/bin/ember</string><string>start</string></array>
    <key>EnvironmentVariables</key><dict><key>PATH</key><string>$agent_path</string><key>EMBER_DATA</key><string>$data</string></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$data/ember.log</string>
    <key>StandardErrorPath</key><string>$data/ember.log</string>
</dict>
</plist>
PLIST
elif user_systemd; then
  service_file="$unit_dir/$unit"
  # KillMode=process: stopping the service stops the station, not the jobs it runs (the next one takes them up).
  cat > "$tmp/service" <<UNIT
[Unit]
Description=ember station
After=network-online.target

[Service]
ExecStart=$app/bin/ember start
Environment=PATH=$agent_path
Environment=EMBER_DATA=$data
Restart=always
RestartSec=5
KillMode=process
StandardOutput=append:$data/ember.log
StandardError=append:$data/ember.log

[Install]
WantedBy=default.target
UNIT
else
  service_file=""
fi

# What the running station says of itself (run/station.json): its pid, when it started, what it can do.
station_json="$data/run/station.json"
said() { sed -n "s/.*\\"$1\\": *\\([0-9]*\\).*/\\1/p" "$station_json" 2>/dev/null | head -1; }
pid=""
if [ -z "$token" ] && [ -f "$station_json" ]; then
  pid=$(said pid)
  # Still that station (a pid is reused once its process is gone): signals go to nothing else.
  case "$(ps -p "\${pid:-0}" -o command= 2>/dev/null)" in
    *ember-station*) ;;
    *) pid="" ;;
  esac
fi
swapped=""
swap_app() {
  mkdir -p "$data"
  rm -rf "$app.old"
  [ -d "$app" ] && mv "$app" "$app.old"
  mv "$tmp/ember" "$app"
  swapped=yes
}

# Handed over without stopping: the new release goes where the old one was, and the running station execs it.
handed=""
if [ -n "$pid" ] && [ -n "$(said handoff)" ] && { [ -z "$service_file" ] || cmp -s "$tmp/service" "$service_file"; }; then
  started=$(said startedAt)
  swap_app
  rm -f "$data/run/handoff-failed"
  echo "把运行中的 station 交接给新版本（agent 不中断）…"
  kill -USR2 "$pid"
  for _ in $(seq 1 120); do
    sleep 1
    if [ "$(said startedAt)" != "$started" ]; then
      [ "$(said pid)" = "$pid" ] && handed=yes
      break
    fi
    [ -f "$data/run/handoff-failed" ] && break
  done
  if [ -n "$handed" ]; then
    rm -rf "$app.old"
  elif [ -f "$data/run/handoff-failed" ]; then
    echo "没能交接（$(cat "$data/run/handoff-failed")），改为重启 station。" >&2
  elif [ "$(said startedAt)" != "$started" ]; then
    # It went down mid-way and its service started the new release: done, the usual way.
    handed=restarted
    rm -rf "$app.old"
  else
    echo "station 没有回应交接，改为重启。" >&2
  fi
fi

if [ -z "$handed" ] && [ -n "$pid" ] && [ -n "$(said drain)" ] && [ -z "\${EMBER_NO_DRAIN:-}" ]; then
  # Restarted: once no turn runs, so none is cut off (at most 10 minutes; it takes no new ones meanwhile).
  rm -f "$data/run/drained"
  kill -USR1 "$pid"
  echo "等 agent 正在跑的这一轮结束再重启（最多 10 分钟；新消息会排队，重启后处理）…"
  for _ in $(seq 1 630); do
    { [ -f "$data/run/drained" ] || ! kill -0 "$pid" 2>/dev/null; } && break
    sleep 1
  done
fi

if [ -z "$handed" ]; then
# One running at a time: the old one stops before the new one takes its place.
if [ "$os" = Darwin ]; then
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  # bootout returns before the service is gone; bootstrapping it again before then fails.
  for _ in 1 2 3 4 5 6 7 8 9 10; do launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || break; sleep 1; done
else
  user_systemd && systemctl --user stop "$unit" 2>/dev/null || true
  [ -f "$data/ember.pid" ] && kill "$(cat "$data/ember.pid")" 2>/dev/null || true
  rm -f "$data/ember.pid"
fi
[ -n "$swapped" ] || swap_app
rm -rf "$app.old"
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$app/bin/ember" "$HOME/.local/bin/ember"

if [ -n "$token" ]; then
  echo "加入 workspace…"
  "$app/bin/ember" station enroll "$origin" "$token"
fi

if [ -n "$handed" ]; then
  :
elif [ "$os" = Darwin ]; then
  mkdir -p "$(dirname "$plist")"
  cp "$tmp/service" "$plist"
  started=""
  for _ in 1 2 3 4 5; do
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null && { started=yes; break; }
    sleep 2
  done
  [ -n "$started" ] || { echo "launchd 没能启动 ember station（launchctl bootstrap gui/$(id -u) \${plist}）" >&2; exit 1; }
else
  if user_systemd; then
    mkdir -p "$unit_dir"
    cp "$tmp/service" "$unit_dir/$unit"
    systemctl --user daemon-reload
    systemctl --user enable "$unit" >/dev/null 2>&1
    systemctl --user restart "$unit"
    # Also with no one logged in (a server): the user's services start with the machine.
    loginctl enable-linger "$(id -un)" 2>/dev/null || lingering="no"
  else
    nohup env PATH="$agent_path" EMBER_DATA="$data" "$app/bin/ember" start >> "$data/ember.log" 2>&1 &
    echo $! > "$data/ember.pid"
    no_service="yes"
  fi
fi

echo
if [ "$handed" = yes ]; then
  echo "ember station 已更新，正在跑的 agent 没有中断。"
else
  echo "ember station 已安装并在后台运行，几秒后会出现在 workspace 里。"
fi
echo "  程序：\${app}（命令 ember 在 ~/.local/bin）"
echo "  数据和日志：$data"
[ "$os" = Linux ] && [ -z "\${no_service:-}" ] && echo "  服务：systemctl --user status $unit"
[ -n "\${lingering:-}" ] && echo "  没人登录时也要运行的话，执行：sudo loginctl enable-linger $(id -un)"
[ -n "\${no_service:-}" ] && echo "  这台机器没有 systemd 用户服务，station 现在在后台运行，但重启后不会自动启动：到时执行 ember start。"
missing=""
command -v claude >/dev/null 2>&1 || missing="$missing Claude Code"
command -v codex >/dev/null 2>&1 || missing="$missing Codex"
if [ -n "$missing" ]; then
  echo
  echo "这台机器上还没有：\${missing}。station 用它们来跑 agent，装一个就能用："
  echo "  Claude Code：curl -fsSL https://claude.ai/install.sh | bash"
  echo "  Codex：      npm install -g @openai/codex（需要 Node）"
  echo "装好之后，在 ember 的「设置 → Profile」里登录账号。"
fi
`;
