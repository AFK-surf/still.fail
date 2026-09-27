// ember station's installer, served at /install.sh: `curl -fsSL <origin>/install.sh | sh -s -- <token>` on the machine
// that is to be a station. It gets the release for the machine (scripts/release.sh put it in the releases bucket,
// served at /releases/<file>), puts it in ~/.ember/app (the data around it stays), links `ember` into ~/.local/bin,
// joins the workspace the token is for, and runs the station as a service of the user (launchd), started at login and
// again if it stops. Claude Code and Codex are the machine's own: it says how to get them when they are missing.

/** The installer for an ember cloud at `origin`. */
export function installScript(origin: string): string {
  return SCRIPT.replaceAll("__ORIGIN__", origin);
}

/** A release's file, as the bucket keeps it: ember-station-<platform>.tar.gz. */
export const RELEASE_FILE = /^ember-station-(darwin-arm64|linux-x64)\.tar\.gz$/;

// A variable is always braced where words follow it ("\${app}（…）"): sh may take the first byte of a non-ASCII
// character for part of its name, and set -u stops the script there.
const SCRIPT = `#!/bin/sh
# Installs ember's station on this machine and joins it to a workspace in ember cloud:
#   curl -fsSL __ORIGIN__/install.sh | sh -s -- <token>
# The token comes from 「添加 station」 in ember. Running it again updates ember and keeps its data (~/.ember).
set -eu
origin="__ORIGIN__"
token="\${1:-}"
if [ -z "$token" ]; then
  echo "用法：curl -fsSL $origin/install.sh | sh -s -- <token>（token 在 ember 的「添加 station」里生成）" >&2
  exit 2
fi
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=darwin-arm64 ;;
  *) echo "暂时只支持 macOS（Apple 芯片）的机器，这台是 $(uname -s) $(uname -m)。" >&2; exit 1 ;;
esac
data="\${EMBER_DATA:-$HOME/.ember}"
app="$data/app"
label="org.3720.ember.station"
plist="$HOME/Library/LaunchAgents/$label.plist"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "下载 ember station…"
curl -fL --progress-bar "$origin/releases/ember-station-$platform.tar.gz" -o "$tmp/ember.tar.gz"
tar -xzf "$tmp/ember.tar.gz" -C "$tmp"

# One running at a time: the old one stops before the new one takes its place.
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
mkdir -p "$data"
rm -rf "$app.old"
[ -d "$app" ] && mv "$app" "$app.old"
mv "$tmp/ember" "$app"
rm -rf "$app.old"
mkdir -p "$HOME/.local/bin"
ln -sf "$app/bin/ember" "$HOME/.local/bin/ember"

echo "加入 workspace…"
"$app/bin/ember" station enroll "$origin" "$token"

# The agents it starts are found on this PATH (Claude Code, Codex, and what they run).
agent_path="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH:/usr/bin:/bin"
mkdir -p "$(dirname "$plist")"
cat > "$plist" <<PLIST
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
launchctl bootstrap "gui/$(id -u)" "$plist"

echo
echo "ember station 已安装并在后台运行，几秒后会出现在 workspace 里。"
echo "  程序：\${app}（命令 ember 在 ~/.local/bin）"
echo "  数据和日志：$data"
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
