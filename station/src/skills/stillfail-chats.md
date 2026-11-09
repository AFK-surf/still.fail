---
name: stillfail-chats
description: Work across chats and services: read another chat by its link, write to another chat's agent (session_send), open a chat with an agent of its own (chat_create), call Slack or Feishu APIs, leave a thread, cards in detail, archive policy. Read it before using any of these.
---

# Other chats, agents and services

## Reading other chats
- chat_history reads your own threads. Another chat's link (…/chats/<key>, …/o/<workspace>/<station>/<key>, ?history=<key>&entry=<n>): chat_read for its conversation, session_history for its agent's work. A chat shared by another workspace lapses after 6 hours unused.
- chat_list finds chats by words; search finds anything in the workspace, on every station at once.
- Point people to a chat by its link (in a still.fail chat as [its title](link)), never its address or session key.

## Other agents
- session_send writes to another chat's agent, here or on another station; people read agents' letters on a page of their own. What they must hear of one, tell them in your chat in your own words, saying where it came from. Send something whole, no acknowledgements or step-by-step progress; a person's decision stays theirs.
- chat_create opens a still.fail chat with an agent of its own, for work that goes on visibly beside yours. Each of its turns that ends all_done or need_human (or fails) comes to you as a notice: end your turn waiting to wait for it. After an uncertain answer, call it again with the same key.
- In a chat opened for you: it is your own conversation, how its turns end reaches its opener by itself (session_send it only to ask something), and it opens no chats itself.

## Slack and Feishu
- slack_api and feishu_api call those APIs as your bot (a Feishu message still goes with chat_post; a still.fail chat's slack_api is the station's Slack bot). slack_api cannot write in another session's thread; a new thread it writes in becomes one of your conversations.
- People who tell you to stop following a thread (stop watching, 别跟了): say in a sentence that you leave it and a mention brings you back, then chat_leave it. Mentioned there again, read what was said meanwhile with chat_history.
- Slack and Feishu show options and text cards. Feishu has no login cards: post the login's link alone there. In
  Slack, a login on this station that takes a pasted code or a device code goes as a login card with its link; any
  other login, its link alone.

## Cards
- Options only for concrete alternatives, each a complete answer by itself; what people would word themselves they type. One option is fine (e.g. 合并).
- A person's next message closes the current card, even if it only clarifies: if a decision is still needed, ask again with a new card. Withdraw a card whose question is resolved: chat_post with to and withdraw=<its ts> alone.
- Without card.assignee a card goes to whoever started the chat.

## Waiting
- waiting needs something that brings you back when the work ends or fails: a background command or agent, a job (skill stillfail-jobs), or a loop polling CI that exits on its first failure (skill stillfail-github-ci). seconds is only a fallback for work that cannot be watched. Waiting on nothing but a watch of yours (a schedule, a monitor): add watch: true.

## Archive
- The station may recommend a chat marked all_done for the archive by its archive policy. When someone says a recommendation is wrong, read archive_policy: change it if the policy caused it, or say the model misjudged.
