# Sharing into still.fail

> chat EMBER/1792193634.353000 (2026-10-17). A person watching a video, reading a page or holding some text in
> another app hands it to one of their chats in a step: the chat's agent does what it is for (downloads the video to
> the station, keeps notes). still.fail is not a browser; it is where things are shared to.

## What a person sees

The system's share sheet (Android), the browser's toolbar button or its context menu (the extension), or an
installed page's share target (web) opens one sheet: what is shared at the top, **发到** a list of chats (the one
a thing from the same site went to last first, saying so; 搜索 from six chats), the last row 新 chat (then which
station it starts on, when there are more than one). No field of its own and no quick actions: a tap opens that chat
with what is shared in its composer, after anything written there already, where the person adds to it and sends it
as anything else (user, 2026-10-17: a field in the sheet would split the composer in two). What the chat does with it
is its agent's business (a chat kept for videos, told once what to do with them).

## The core (client/core-ts/src/share-in.ts)

- `shareIn` view (`scope`, `source`: what is shared as text, `query?`): `ShareInView`. `items` are the scope's
  chats on still.fail's page as the sidebar has them (a Slack chat takes no message from here; a chat still being made
  is left out), newest first, at most 30, those `query` finds when given. `kept`: the chat a thing from the same
  `site` went to last time (`youtube.com`; links from short hosts by the site they are of: `youtu.be`, `b23.tv`,
  `xhslink.com` …; text without a link is a site of its own), listed first, with why (`text`). `stations`: the
  scope's stations up now (`{station, name}`), and `newOn`, the one a new chat starts on unless another is picked.
- `shareIn.open` (`scope`, `source`, `station`, `id?`, `title?` (what the app gave as its subject), `key?` (a new
  chat's composer key on the page that opens it, when not `new:<station>`: the phone web's `new:`)): the title on a
  line of its own when the shared text does not hold it, then what was shared, put after what the chat's composer
  holds (`<station>:<session>`, the row's), once (shared again, it is not put twice); with no `id`, into the new
  chat's composer on `station` (`new:<station>`), which new chats then start on. Nothing is sent. It answers
  `{ station, key, session?, thread?, title? }` for the page to open the chat. The chat is kept as where that site's
  things go (`choice` records `ws:<scope>:shareIn:<site>`); a new chat is not, until a thing is shared into it.

## The clients

- **Android**: `ShareActivity` takes `ACTION_SEND` of `text/plain` (`EXTRA_TEXT`, `EXTRA_SUBJECT`); translucent over
  the app it came from, the app's own sheet (`SheetHost`, solid: there is no page of the app's to frost) with the
  view's rows. A tap opens the app at that chat (or a new chat), the shared thing in its composer.
- **Web** `/share?text=&title=&url=` (the installed page's `share_target`, and what the extension opens): the same
  sheet over the workspace's page, phone and wide screen alike; a tap goes to the chat in that page.
- **Browser extension** (`apps/extension`, Chrome/Edge, Manifest V3): its toolbar button and context menu (a page, a
  link, a video, selected text) open `<cloud>/share?…` in a small window of its own, signed in as the person's
  still.fail page is; a tap there opens the chat in the still.fail tab (a new one if there is none) and the small
  window closes. It reads nothing of the page beyond its address, title and what was clicked.
