---
name: stillfail-feedback
description: Reporting bugs in still.fail itself to the still.fail team (feedback_send). Use when still.fail misbehaves while you work — a station tool fails or acts wrongly (chat_post, chat_history, jobs, files), messages are lost, doubled or land in the wrong thread, a session restarts or a job dies for no reason — or when someone says the still.fail app, web, desktop app or its Slack side is broken. Not for bugs in their own code, other services, or your own mistakes.
---

# Reporting a bug in still.fail

You run on still.fail. When still.fail itself gets in the way, the person you work for can have it reported to the
still.fail team, who read every report. You offer; they decide; you send only what they agreed to.

## Is it still.fail's?

Yes:
- A station tool (chat_post, chat_state, chat_history, chat_read, slack_api, job_*, attached files) errors in a way that
  is not about your arguments, or does something other than it says: a post that never shows, a file that does not
  attach, history that is missing or wrong.
- The station's behaviour: messages that do not reach you or reach you twice, answers that land in another thread, a
  session started over or cut off, a job or web service that dies or does not come back up, a link that does not open.
- Someone tells you the still.fail app, web page, desktop app, notifications or sign-in misbehave.

No: their own code or project, another service (GitHub, a cloud provider, Slack being down for everyone), the model
being wrong, a tool used with wrong arguments, limits the station states (an allowance used up, a file too big). When
unsure, look once more (try again, read the error) before calling it still.fail's.

## Offer, once

Deal with what they asked for first, working around the problem if you can. Then ask, in their language, in one line,
whether you should report it to the still.fail team, e.g. "这看起来是 still.fail 本身的问题，要不要我帮你反馈给开发团队？".
Ask once per problem in a conversation; if they say no, or do not answer, drop it. Do not offer for every hiccup that
went away on a retry.

## Write the report

The team was not there: the report alone has to let them find the problem. Write it in the language of the
conversation:
- title: one line, what goes wrong.
- body (Markdown): what happened (the exact error text), what was expected, the steps that lead there, when it
  happened, and how often. Name the tools, ids and times you saw.
- area: station, web, android, desktop, slack, cloud or unknown.
- reporter: who reports it and where (their name; the Slack channel or "still.fail chat").
- logs, only if they show the problem: the few lines of tool errors or the station's own output, nothing more.

What the station adds by itself: its version, runtime and model, the session, the thread and its link. Do not repeat
those.

Do not put in the conversation's words, file contents, code, names of their customers, or anything secret (tokens,
keys, passwords, private URLs) by default. Judge whether the team can work with what is left: if a short excerpt is
needed to understand the bug (say, the message that went to the wrong thread), quote only that and point it out to
them when you show the report.

## Show it, then send

Show them the report as it will be sent (title, body, logs if any) and ask them to confirm. Send only once they agree;
if they want changes, change it and show it again. Then call feedback_send with the thread you are in as `to`, and
tell them the number it got (FB-…), which they can give the team.

If feedback_send fails, tell them it could not be sent and give them the report to pass on themselves.
