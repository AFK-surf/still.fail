# Sharing into still.fail

> chat EMBER/1792193634.353000 (2026-10-17). A person watching a video, reading a page or holding some text in
> another app hands it to one of their chats in a step: the chat's agent does what it is for (downloads the video to
> the station, keeps notes). still.fail is not a browser; it is where things are shared to.

## What a person sees

The system's share sheet (Android), the browser's toolbar button or its context menu (the extension), or an
installed page's share target (web) opens one sheet: what is shared at the top, **发到** a list of chats with the one
picked marked, the last row 新 chat (then which station it starts on, when there are more than one), and a composer
(补一句, optional) with its send button. No quick actions: what the chat does with it is its agent's business (the
person can keep a chat for videos, told once what to do with them). Sent, the sheet closes at once and the app it came
from is in front again; a note says where it went, with 打开.

## The core (client/core-ts/src/share-in.ts)

- `shareIn` view (`scope`, `source`: what is shared as text, `query?`): `ShareInView`. `items` are the scope's
  chats on still.fail's page as the sidebar has them (a Slack chat takes no message from here; a chat still being made
  is left out), newest first, at most 30, those `query` finds when given. `kept`: the chat a thing from the same
  `site` went to last time (`youtube.com`; links from short hosts by the site they are of: `youtu.be`, `b23.tv`,
  `xhslink.com` …; text without a link is a site of its own), listed first, with why (`text`). `picked`: where it goes
  — what `shareIn.pick` picked, else `kept`, else the latest chat, else a new chat on the station new chats last
  started on. `stations`: the scope's stations up now (`{station, name}`), for 新 chat.
- `shareIn.pick` (`scope`, `source`, `station`, `id?`): a chat by its row's `id`, or with no `id` a new chat on
  `station`. Held while a page shows the view, dropped once none does.
- `shareIn.send` (`scope`, `source`, `title?` (what the app gave as its subject), `text?` (what the person added),
  `client?`): the message is what was added, a blank line, the title on a line of its own when the shared text does
  not hold it, and what was shared. It answers `{ station, session, thread?, title }` once the message is in the chat's
  outbox (a new chat: asked for, the message waiting in it): it does not wait on the station, and goes on from there
  as any message does (sent again after a restart). The chat it went to is kept as where that site's things go
  (`choice` records `ws:<scope>:shareIn:<site>`; a new chat by the key it went by while being made, so it is found once
  made).

## The clients

- **Android**: `ShareActivity` takes `ACTION_SEND` of `text/plain` (`EXTRA_TEXT`, `EXTRA_SUBJECT`); translucent over
  the app it came from, the app's own sheet (`SheetHost`) with the view's rows; sent, it finishes and a toast says
  where.
- **Web** `/share?text=&title=&url=` (the installed page's `share_target`, and what the extension opens): the same
  sheet over the workspace's page, phone and wide screen alike; sent, it closes (a window the extension opened closes
  itself) or goes to the chat.
- **Browser extension** (`apps/extension`, Chrome/Edge, Manifest V3): its toolbar button and context menu (a page, a
  link, a video, selected text) open `<cloud>/share?…` in a small window of its own, signed in as the person's
  still.fail page is. It reads nothing of the page beyond its address, title and what was clicked.
