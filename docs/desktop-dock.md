# The desktop dock

On a Mac (14 or later, Apple silicon), the desktop app keeps the chats that want the person on the right edge of the
screen, also with no window open: a half circle of Liquid Glass (macOS 26; a material before it) drawn by a SwiftUI
helper, `apps/desktop/dock`, which the app starts and feeds (`apps/desktop/src/dock.mts`). The app menu's 「桌面浮窗」
turns it off and on (`userData/dock.json`); so does the half circle's own right-click menu.

## What it shows

The chats of every workspace (`chats` with `mine`, and `decisions`, per workspace of the `workspaces` topic):

- a card waiting on the person (the 奏 list, set-aside ones left out), with its question and options;
- a failed chat (the sidebar's red mark);
- a chat with something unread (the blue dot).

Chats at work, and cards waiting on someone else, are not the person's: not shown.

## How it behaves

User-decided (2026-10-08, chat EMBER/1791405826.815000):

- **Collapsed:** a half circle flush with the edge, the marks of the first four inside (blue ring waiting, red failed,
  blue dot unread). It can be dragged along the edge; it stays where it was put.
- **Peek:** something new (a message key the dock had not had) stretches the half circle into a capsule with its title,
  station and one line. It does not go away by itself: only once it has been seen.
- **Card:** the mouse resting on the peek (on the half circle with no peek) pours the card out of it: that one message,
  its question and options when it is a card, and what can be done right there (an option, 打开, 已读, 稍后). Scrolling
  on it goes through the others one by one, the loudest first (waiting, failed, unread; newest first in each).
- **Seen is enough:** once the card has been open, the mouse leaving it (or 稍后) draws everything back into the half
  circle; what it showed stays unread there. 打开 brings the app's window up on the chat. Pushing the peek back to the
  edge (dragging it right, two fingers sideways) also puts it away.

## How it is made

The helper only draws and says which button was pressed; everything else is the app's (`dock.mts`): it holds the
core's topics on its own link, turns them into the dock's items (`dockItems`), and does what the helper asks
(`chat.read`, `decision.answer`, opening `/o/<workspace>/<station>/<session>`). One JSON object a line each way over
the helper's stdin and stdout (the protocol is at the top of `dock/Sources/StillfailDock/main.swift`); the helper quits
when its stdin closes.

The helper is a native part (docs/development.md, "Native parts"): keyed by its sources, built on mini1 only when they
changed, fetched from the release `native-artifacts` otherwise. A change elsewhere in the app compiles no Swift.
