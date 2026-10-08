# The desktop dock

On a Mac (14 or later, Apple silicon), the desktop app keeps the chats that want the person on the right edge of the
screen, also with no window open: a half circle of Liquid Glass (macOS 26; a material before it) drawn by a SwiftUI
helper, `apps/desktop/dock`, which the app starts and feeds (`apps/desktop/src/dock.mts`). The app menu's 「桌面浮窗」
turns it off and on; so does the sliver's own right-click menu. Settings → 通知 has its settings (2026-10-08 「缺了设置」):
shown at all, new ones peeking out (off: they only wait at the edge), plain unread chats in it (off: only what waits on
the person and what failed); kept in `userData/dock.json` (main.ts `dock:get`, `dock:set`).

## What it shows

The chats of every workspace (`chats` with `mine`, and `decisions`, per workspace of the `workspaces` topic):

- a card waiting on the person (the 奏 list, set-aside ones left out), with its question and options;
- a chat with something unread (the blue dot; red when it failed).

Chats read, at work, and cards waiting on someone else are not shown: the sidebar has them.

## How it behaves

User-decided (2026-10-08, chat EMBER/1791405826.815000):

- **Collapsed:** nothing on the screen while nothing waits. With something waiting, a thin sliver of glass on the
  edge, tinted as the loudest mark (red failed, else blue); it can be dragged along the edge and stays where it was
  put. The mouse touching the screen's right edge anywhere along it opens what waits (2026-10-08: the always-there half
  circle was 「不太合理」).
- **Peek:** something new (a message key the dock had not had) stretches the sliver into a capsule with its title,
  station and one line. It does not go away by itself: only once it has been seen.
- **Card:** the mouse resting on the peek (or on the edge with no peek) pours the card out of it: the messages one
  under another, the loudest first (waiting, failed, unread; newest first in each), opened at the peek's. It scrolls
  as any list does and settles on one message at a time (the system's scrolling; the card as tall as that one; a
  jump a scroll at a time was 「切换消息太怪了」). Each has what can be done right there: an option, 打开, 已读, 稍后.
- **Seen is enough:** once the card has been open, the mouse leaving it (or 稍后) draws everything back into the sliver;
  what it showed stays unread there. 打开 brings the app's window up on the chat. Pushing the peek back to the
  edge (dragging it right, two fingers sideways) also puts it away.

## How it is made

The helper only draws and says which button was pressed; everything else is the app's (`dock.mts`): it holds the
core's topics on its own link, turns them into the dock's items (`dockItems`), and does what the helper asks
(`chat.read`, `decision.answer`, opening `/o/<workspace>/<station>/<session>`). One JSON object a line each way over
the helper's stdin and stdout (the protocol is at the top of `dock/Sources/StillfailDock/main.swift`); the helper quits
when its stdin closes.

The helper is a native part (docs/development.md, "Native parts"): keyed by its sources, built on mini1 only when they
changed, fetched from the release `native-artifacts` otherwise. A change elsewhere in the app compiles no Swift.
