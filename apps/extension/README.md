# still.fail for Chrome and Edge

Sends what is in front of you to one of your still.fail chats (docs/share-in.md): the toolbar button sends the page;
right-click a page, a link, a video or selected words for the same. A small window opens on still.fail's `/share`
(signed in as your still.fail page is, in the same browser) listing your chats (the one the same site's links went to
last is first). Pick one, or a new chat, and it opens in your still.fail tab (a new tab if none is open) with what you
shared already in its composer; add to it and send it there. The small window closes itself.

It reads nothing of the page you share beyond its address and title and what you clicked (`activeTab`). The only pages
it reaches into are still.fail's own (`https://app.still.fail/*`), to take your still.fail tab to the chat you picked.

## Load it unpacked

1. Open `chrome://extensions` (Edge: `edge://extensions`) and turn on Developer mode.
2. Load unpacked → pick this folder (`apps/extension`).
3. Pin it to the toolbar.

Plain JavaScript (Manifest V3), no build step: change a file and press reload on its card.

## Another still.fail

The extension's options (its card → Details → Extension options) say where still.fail is: `https://app.still.fail`
unless you give another (a dev cloud, `http://127.0.0.1:8877`). Saving another asks for access to its tabs; without it
(or on a host other than still.fail's, `localhost` and `127.0.0.1`) a chat picked opens in a new tab.
