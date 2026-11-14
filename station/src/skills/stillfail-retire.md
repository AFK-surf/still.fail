---
name: stillfail-retire
description: Retire a still.fail station (move its chats, jobs, memory, accounts and connects to another station of the workspace, 迁移/废弃一台 station) with station_retire. Read before preview, start or hand_over.
---

# Retire a station with an agent

`station_retire` moves everything of one station's chats in this workspace to another station. You prepare and
check; a person confirms two cards in the still.fail app. The tool's description says the actions.

## Before start

1. `station_retire {action: "preview", station, to}`: what moves, what stays, whether `to` is reached, has git and
   room. Never start against a station that is not reached or has too little room.
2. Check `to` with `station_task` (small tasks) against what the chats here use: look at their worktrees and jobs
   (`job_list`), then on `to`: `git --version`, the package managers and toolchains they run (node/pnpm, python/uv,
   cargo, moon…), logins (`gh auth status`, cloud CLIs), free disk where the station's data is.
3. Fix what you can there yourself (install a tool with a task). Ask the person only for what you cannot: a login
   through the login tool, a credential through the vault (stillfail-vault), never pasted.
4. What never moves by itself: tools installed on the machine, and config.json's machine settings (`sandboxes`,
   `agentEnv`). Say so and set them up on `to` before the hand-over if the chats need them.

## The two cards

- `start {to}` posts 开始迁移. Nothing happens until an owner or admin of the workspace chooses it in the app; a
  member's choice, a Slack reply or a message saying yes does not count. A later message ends the card: call `start`
  again to ask again.
- Once confirmed, files are sent while chats still work; you are told when it reaches `sent`, with the numbers.
- `hand_over` posts 暂停聊天并交接 with those numbers. Confirmed, every chat of the station in this workspace pauses
  (yours too, if you are on it) until the other station took them.
- A hand-over that fails puts the chats back to work by itself and waits at `sent`; you are told why. Fix it, then
  `hand_over` again (confirmed again): only what changed is sent. `again` never pauses the chats.
- Only drive this from a still.fail chat: the cards are confirmed in the app.

## After the chats were taken

You are told on the station they went to (your own chat moved too, if it was on the retired one). Check there:
- a moved chat goes on (its first reply), its directory under the new data directory;
- a worktree: `git status`, `git worktree list` in it (`git worktree repair` where it names the old place);
- jobs: `job_list` shows those started again; start what was refused (a port taken, a directory that stayed);
- logins the chats use (`gh auth status` and the like) and the accounts the retired station could not move
  (`status` lists them: sign them in there with the login tool).

At `done`, taking the retired station out of the workspace is the person's own step in the app (its station page).
Tell them; do not try to do it.
