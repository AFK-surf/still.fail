# still.fail for Chrome and Edge

Sends what is in front of you to one of your still.fail chats (docs/share-in.md): the toolbar button sends the page;
right-click a page, a link, a video or selected words for the same. A small window opens on still.fail's `/share`
(signed in as your still.fail page is, in the same browser): pick the chat (the one the same site's links went to last
is first), add a line if you like, send. The window closes itself once it is sent.

It reads nothing of the page beyond its address and title and what you clicked (`activeTab`, no host permissions).

## Load it unpacked

1. Open `chrome://extensions` (Edge: `edge://extensions`) and turn on Developer mode.
2. Load unpacked → pick this folder (`apps/extension`).
3. Pin it to the toolbar.

Plain JavaScript (Manifest V3), no build step: change a file and press reload on its card.

## Another still.fail

The extension's options (its card → Details → Extension options) say where still.fail is: `https://app.still.fail`
unless you give another (a dev cloud, `http://127.0.0.1:8877`).
