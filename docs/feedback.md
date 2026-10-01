# Bug reports about still.fail (feedback)

Someone using still.fail runs into still.fail itself misbehaving; the agent working for them offers to report it to the
team, shows them the report, and sends it once they agree. The reports wait in the admin console (admin.still.fail,
「反馈」), where the team picks them up and hands them to an agent on their own station.

- **Skill** `stillfail-feedback` (mesh/app/src/skills/stillfail-feedback.md): when something is still.fail's (a station
  tool failing or acting wrong, lost or doubled messages, the apps misbehaving) and when not (their own code, other
  services, the model); offer once per problem; write the report so the team can find the bug without the
  conversation; leave out the conversation's words, files and secrets unless a short excerpt is needed, pointed out
  when shown; show it, send on a yes, give the FB number.
- **Tool** `feedback_send` (mesh/app/src/feedback.rs): title, body, area, reporter, optional logs. The station adds
  the session, connect, runtime, profile, model, thread, the session's /o/ link, OS and its version, and a key
  (sha256 of session, title and body) so a retried call is not a second report. The station process posts it
  (mesh/station/src/feedback.rs) to `<origin>/v1/feedback`, signed over
  `stillfail-station-feedback-v1:<origin>:<station>:<ts>:<sha256 of the body, hex>`.
- **Not on the test channel**: a station updated on the beta channel (youdid.wtf; the team's own stations) has neither
  the skill nor the tool, decided as it starts (`updates::channel_of`); a skill directory left from before is removed
  unless someone added files to it.
- **API** (cloud/src/feedback.ts): `POST /v1/feedback`, from a station (signed) or a signed-in account (bearer), on
  app.still.fail and app.youdid.wtf alike; each report is marked `channel: stable | beta` by the host it came on (or
  `x-stillfail-channel: beta`). Kept in the Directory's `feedback` table, numbered from 1 (FB-n); the same sender's
  same key answers the report kept (200, `duplicate: true`); 20 per sender a day (429). The console:
  `GET /v1/admin/feedback` (newest 500, with station, workspace and account), `POST /v1/admin/feedback/<id>/status`
  `{ status: new | triaged | fixed | wontfix }`.
- **Old and new together**: an old station has no tool and no skill. A new station on an old cloud gets 404 and the
  agent hands the person the report to pass on. An old console never asks for the list.
