"""Stores the Slack tokens in ~/.ember/config.json (mode 600), keeping the rest of the file.

Reads two lines from stdin: the app-level token (xapp-…), then the bot token (xoxb-…).
Tokens arrive on stdin so they never show up in process arguments or shell history.
"""
import json
import os
import sys

app, bot = ([line.strip() for line in sys.stdin.read().splitlines()] + ["", ""])[:2]
if not (app.startswith("xapp-") and bot.startswith("xoxb-")):
    sys.exit("token prefixes look wrong: expected xapp-… then xoxb-…")

directory = os.path.expanduser(os.environ.get("EMBER_DATA", "~/.ember"))
os.makedirs(directory, mode=0o700, exist_ok=True)
path = os.path.join(directory, "config.json")
config = json.load(open(path)) if os.path.exists(path) else {}
config["slack"] = {"appToken": app, "botToken": bot}
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, (json.dumps(config, indent=2) + "\n").encode())
os.close(fd)
os.chmod(path, 0o600)
print("saved", path)
