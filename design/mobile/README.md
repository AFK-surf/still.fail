# ember mobile · interaction concept

Open `index.html` in a browser: a clickable iPhone with fake data and simulated live work.

Decisions this concept settled:
- The phone is for triage and steering, not heavy reading. Home is an inbox: chats where an agent is **blocked** first (with quick replies), then running ones (one line of what they are doing), then the rest.
- No tab bar. A fixed head (you → settings · workspace switcher · stations); one bottom toolbar (全部 / 我参与的 · new chat), like Mail.
- Agents are shown as their model's maker mark; a chat can have several agents and people. State is a badge on the mark (solid orange = block, hollow ring = running, red = failed; done needs no attention, so no badge); nothing blinks.
- The mascot (station buddy) stands for still.fail itself only: app icon, illustrations, stations.
- Execution history opens from an agent's name, avatar or activity (per agent), never from a generic button; the chat's "…" is the chat's info (agents → their histories, people, notifications, actions).
- Quote by long-press; attachments via ＋; block pushes answer from the notification; a Live Activity shows a running turn on the lock screen.
