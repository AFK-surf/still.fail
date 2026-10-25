# Private chats

A chat begun in a direct message to the bot (Slack `im` and `mpim`, Feishu `p2p`) belongs to the people in that
direct message. Nobody else sees it: not other workspace members, not the workspace's owners and admins, and not
other chats' agents. Decided 2026-10-25 (Peng Xiao): direct messages are visible to their participants only, and
managers do not see them either.

## Who a chat is private to

- `sessions.private_to` (a JSON array of emails, lowercase; `NULL` means not private) is set once, when the hub
  creates the session for the first message of the direct message (`Hub.acceptInTurn`, `directPeople`):
  - Slack `im`, Feishu `p2p`: the sender.
  - Slack `mpim`: the sender and the other members (`conversations.members`, excluding the bot). If the platform
    does not return the members, the chat is private to the sender alone.
  - Each person is matched by the email the platform gives (`users.info`, which needs Slack's `users:read.email`;
    Feishu's contact permission). Anyone whose email is unknown is left out, so without that permission the chat is
    private to no one and nobody sees it in the app. The unverified Slack claim (「这是我」, `PUT /me/slack/:user`)
    is never used for this.
- A single-session connect has one session for every thread, so its direct messages are not private.
- A chat its agent opens with `chat_create` is private to the same people (`NewChat.privateTo`). It can only be
  opened on this station: another station has no private chats, so opening one there is refused.
- A chat from before this change is not private.

## What is hidden

People (`store/rows.ts` `seesChat`, `seesMembers`):
- sidebar rows, `GET /sessions`, `/sessions/:key`, `/threads`, and every path that names the session, its threads
  or jobs (`api/seen.ts` `elsewhere`, answered as a 404);
- the event stream (`services.ts` `seen`), the overview's processes, archive decisions, usage and resources;
- search: chat, message, history and job documents carry `to` (`search/match.ts`), and a person's asker is
  `reader: [their email]`.

A thread is seen only when one of its sessions is in the viewer's workspace and every private session in it is
private to people including the viewer.

Agents (`opensTo(reader, to)`): what an agent reads may be shown to everyone who sees its own chat, so its
`reader` is its chat's `private_to` (`NULL`: everyone). It may read a private chat only when everyone who sees its
own chat is among that chat's people:
- `chat_list` leaves the chat out. `chat_read`, `session_history` and attachments fetched by another station refuse
  it, whether it is named by key, address or link.
- `search` (this station's, and another station's asking here, whose reader is everyone) does not find it.
- `slack_api` and `feishu_api` refuse calls that name the chat's channel.
- Writing to it is allowed: `session_send` delivers a letter into it, and that reveals nothing of the chat.

Notifications already go only to a chat's own people (`read/notices.ts`).

## Limits

- This hides the chat from lists, reads and agents' tools; it is not a sandbox. As with workspaces
  (docs/multi-workspace.md), every agent runs as the same system user, so an agent that reads the station's files
  directly is not stopped.
- What a private chat's agent writes into other chats (`session_send`, relaying to a channel) is visible there. The
  instructions tell it not to carry anything over unless the chat's people ask.
- A direct message the station never turned into a session (one not addressed to it) is not known to be private;
  `slack_api` can still read such a channel, as the bot can.
- Sharing a private chat with another workspace or publishing a snapshot is still possible for the people who see it,
  but reads from other workspaces count as reads by everyone and are refused.
