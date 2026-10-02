#!/usr/bin/env python3
"""The chat list's input as a station's GET /chats gives it (mesh/app/src/admin/views.rs `chats`), made from a copy of a
station's database, for the views bench. Its rows are that station's real chats; the output stays off git (it holds
what was said in them).

make-input.py <stillfail.db copy> <out.json> [rows: repeat them up to this many] [vary]

`vary`: the copies (and every 3rd row) get what this station's chats rarely have, so that both ports' every branch
runs: unread, queued and running agents, watches, Slack origins, failures, waits, needs, dismissed and text cards,
several agents, members with names and pictures, the viewer's Slack user, still.fail's own messages.

Archived chats are listed too (as if not archived): a station's own sidebar is short, the archive is most of it."""
import json, sqlite3, sys

db, out = sys.argv[1], sys.argv[2]
want = int(sys.argv[3]) if len(sys.argv) > 3 else 0
vary = len(sys.argv) > 4 and sys.argv[4] == "vary"
import random
rnd = random.Random(7)
c = sqlite3.connect(db)
c.row_factory = sqlite3.Row
q = lambda sql, *a: c.execute(sql, a).fetchall()

def person(ref):
    if not ref:
        return None
    if ref == "local":
        return {"id": "local", "name": "本机管理页", "email": None, "via": "local"}
    return {"id": ref, "name": ref, "email": ref, "via": "cloud"}

turns = {}
for t in q("select * from turns order by id"):
    turns[t["session_key"]] = t

def turn(key):
    t = turns.get(key)
    if t is None:
        return None
    v = {"kind": t["kind"], "outcome": t["outcome"], "declared": t["declared"], "detail": t["detail"],
         "startedAt": t["started_at"], "endedAt": t["ended_at"]}
    if t["declared"] in ("all_done", "need_help", "need_decision", "waiting"):
        v["ending"] = t["declared"]
    if t["need"]:
        v["need"] = t["need"]
    if t["about_thread"] is not None and t["about_n"] is not None:
        v["about"] = {"thread": t["about_thread"], "seq": t["about_n"], "ts": t["about_ts"]}
    if t["wait_seconds"] is not None:
        v["waitSeconds"] = t["wait_seconds"]
    if t["wait_for"]:
        v["waitFor"] = t["wait_for"]
    return v

pins = {p["session"]: p["at"] for p in q("select * from pins")}
reads = {}
for r in q("select thread, max(n) n from reads group by thread"):
    reads[r["thread"]] = r["n"]
authors = {}
for a in q("select author, count(*) n from entries where author_kind='person' group by author order by n desc"):
    authors[a["author"]] = a["n"]
viewer = next(iter(authors), "someone@example.com")
members = [{"email": e, "name": e.split("@")[0], "picture": None} for e in authors if "@" in (e or "")]

def message(e):
    return {"seq": e["n"], "authorKind": e["author_kind"], "author": e["author"], "authorName": None,
            "text": (e["text"] or "")[:400], "createdAt": e["at"]}

rows = []
for t in q("select * from threads order by id"):
    keys = [s["session"] for s in q("select session from thread_sessions where thread=? order by joined_at", t["id"])]
    sessions = [s for k in keys for s in q("select * from sessions where key=?", k)]
    if not sessions:
        continue
    agents = [{"key": s["key"], "runtime": s["runtime"], "model": s["model"], "effort": s["effort"],
               "process": "running" if s["running"] else "cold", "pending": 0, "lastTurn": turn(s["key"])} for s in sessions]
    entries = q("select * from entries where thread=? order by n", t["id"])
    said = [e for e in entries if e["text"] is not None or e["attachments"]]
    last = said[-1] if said else None
    first = next((e["text"] for e in said if e["author_kind"] == "person" and (e["text"] or "").strip()), None)
    title = next((x.strip() for x in [t["title"], t["auto_title"]] if x and x.strip()), None) or (first or "").strip().split("\n")[0][:80] or "新对话"
    people = []
    for e in said:
        if e["author_kind"] == "person" and e["author"] and e["author"] not in people:
            people.append(e["author"])
    row = {
        "id": agents[0]["key"], "session": agents[0]["key"], "thread": t["id"], "title": title, "agents": agents,
        "last": message(last) if last else None,
        "unread": bool(last) and reads.get(t["id"], 0) < last["n"],
        "mine": True,
        "lastActiveAt": max(t["created_at"] or 0, last["at"] if last else 0),
        "connect": None, "origin": None,
        "creator": person(t["created_by"]),
        "people": [person(p) for p in people],
        "archiveReminderDismissed": False,
        "pinned": pins.get(agents[0]["key"]),
    }
    # The card it waits on: the last post with one, when no person wrote after it.
    for i in range(len(entries) - 1, -1, -1):
        e = entries[i]
        if e["author_kind"] == "person":
            break
        if e["card"]:
            card = json.loads(e["card"])
            m = message(e)
            m["card"] = card
            row["card"] = {"seq": e["n"], "card": card, "message": m, "before": [message(b) for b in entries[max(0, i - 2):i]]}
            if card.get("type") == "options":
                row["decision"] = {"seq": e["n"], "message": m, "before": row["card"]["before"], "options": card.get("options")}
            break
    rows.append(row)

base = len(rows)
day = 86_400_000
i = 0
while want and len(rows) < want:
    r = json.loads(json.dumps(rows[i % base]))
    n = len(rows)
    r["id"] = r["session"] = f'{r["id"]}-{n}'
    r["thread"] = r["thread"] + 100000 * (n // base)
    r["lastActiveAt"] -= day * (n // base) * 3
    for a in r["agents"]:
        a["key"] = f'{a["key"]}-{n}'
    if r["last"] and r["last"]["authorKind"] == "agent":
        r["last"]["author"] = r["agents"][0]["key"]
    r["pinned"] = None
    rows.append(r)
    i += 1

def varied(r, n):
    pick = rnd.random
    if pick() < 0.3:
        r["unread"] = True
    for a in r["agents"]:
        t = a.get("lastTurn") or {"kind": "message", "outcome": None, "declared": None, "detail": None, "startedAt": r["lastActiveAt"] - 60000, "endedAt": None}
        roll = pick()
        if roll < 0.1:
            a["process"] = "running"
        elif roll < 0.15:
            a["pending"] = 2
        elif roll < 0.25:
            t.update({"declared": "waiting", "ending": "waiting", "waitFor": "CI 跑完" if pick() < 0.5 else "  ", "waitSeconds": 600, "endedAt": t.get("endedAt") or r["lastActiveAt"]})
            if pick() < 0.3:
                a["watch"] = {"names": ["部署监控", "nightly"]}
        elif roll < 0.35:
            t.update({"outcome": "failed", "declared": None, "detail": rnd.choice(["rate_limit: slow down", "auth: expired", "exited: 137", "weird"])})
            t.pop("ending", None)
        elif roll < 0.45:
            t.update({"declared": "block", "need": rnd.choice(["选统计口径", "", "要 Stripe 的测试 key"])})
            t.pop("ending", None)
        elif roll < 0.5:
            t.update({"declared": "final", "need": "已合并所有代码"})
            t.pop("ending", None)
        if pick() < 0.3:
            t["about"] = {"thread": r["thread"] if pick() < 0.7 else 1, "seq": 3, "ts": "1"}
        a["lastTurn"] = t
        if pick() < 0.2:
            a["model"] = rnd.choice(["claude-opus-5-5", "us.anthropic.claude-sonnet-5-v1:0", "gpt-6-astra", "o4-mini", "deepseek-v4-pro", "glm-4.6", "my/Custom-Model", "claude-sonnet-5[1m]", None])
            a["effort"] = rnd.choice(["high", "", None])
            a["runtime"] = rnd.choice(["claude", "codex"])
    if pick() < 0.15:
        extra = json.loads(json.dumps(r["agents"][0]))
        extra["key"] = extra["key"] + "-b"
        extra["process"] = "running" if pick() < 0.5 else "cold"
        r["agents"].append(extra)
    if pick() < 0.2:
        r["connect"] = "slack-1"
        r["origin"] = {"teamName": rnd.choice(["Cue", None, ""]), "channel": rnd.choice(["C123", "D456"]), "channelName": rnd.choice(["dev", None]), "threadTs": "1.2"}
    if r["last"] and pick() < 0.3:
        r["last"]["text"] = rnd.choice(["<@U12AB> 看一下\n第二行", "", "  多   空格\t文字 ", "<@bad> x"])
        r["last"]["authorKind"] = rnd.choice(["person", "agent", "stillfail", "ember"])
        r["last"]["author"] = rnd.choice([r["agents"][0]["key"], "U999", "zuozijian1994@gmail.com", "someone@x.com"])
        r["last"]["authorName"] = rnd.choice(["老王", "", None])
        if pick() < 0.3:
            r["last"]["agentIdentity"] = {"model": "gpt-6-astra"}
    if pick() < 0.15:
        text = rnd.choice(["# **要不要**合并？\n细节", "", "`部署` 到 __线上__", "> 选一个"])
        card = rnd.choice([{"type": "options", "options": [{"label": " 合并 ", "detail": "推到 main", "recommended": True}, {"label": "不合", "detail": " "}, {"label": ""}]},
                           {"type": "text", "placeholder": " 填个名字 ", "assignee": "someone@x.com"}, {"type": "weird"}])
        m = {"seq": 7, "authorKind": "agent", "author": r["agents"][0]["key"], "text": text, "card": card}
        r["card"] = {"seq": 7, "card": card, "message": m, "before": []}
        if pick() < 0.3:
            r["card"]["dismissed"] = True
        if card["type"] == "options" and pick() < 0.5:
            r["decision"] = {"seq": 7, "message": m, "options": card["options"]}
            if pick() < 0.5:
                del r["card"]
    if pick() < 0.05:
        r["pinned"] = r["lastActiveAt"] - n
    if pick() < 0.1:
        r["archiveReminderDismissed"] = True
    if pick() < 0.1:
        r["people"].append({"id": "slack:c:U777", "name": "U777", "email": None, "via": "slack"})
    if pick() < 0.05:
        r["creator"] = {"id": "local", "name": "本机管理页", "email": None, "via": "local"}

if vary:
    members.extend([{"email": "someone@x.com", "name": "某人", "picture": "https://x/p.png"}, {"email": "U12AB", "name": "", "picture": ""}])
    for n, r in enumerate(rows):
        if n >= base or n % 3 == 0:
            varied(r, n)

now = max(r["lastActiveAt"] for r in rows) + 3_600_000
json.dump({"now": now, "offsetMin": 480, "me": {"id": viewer, "email": viewer}, "members": members, "slackUsers": ["U999"] if vary else [],
           "station": {"address": "ws/station", "name": "ccvm"}, "rows": rows}, open(out, "w"), ensure_ascii=False)
print(f"{len(rows)} rows ({base} of the station's own), viewer {viewer}, {len(members)} members")
