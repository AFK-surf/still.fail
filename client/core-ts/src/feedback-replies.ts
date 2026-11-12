// The still.fail team's replies on a bug report sent from a chat, as that chat shows them (the `chatFeedback` topic,
// {station, session}): only to people, beside the chat, never to its agents. still.fail cloud keeps them and gives them
// to the members of the chat's workspace alone (GET /v1/workspaces/<id>/feedback, with the person's sign-in: no station
// asks for them, none holds them); the sync reads them as the account's events socket opens and as it says they changed
// (`{type: "feedback", workspace}`: sync/cloud.ts), and keeps them in the workspace's record `feedback`. A person answers
// with `workspace.feedbackReply`, as themselves; what reaches an agent is only what a person hands it (quoted in what
// they send).
import type { Data } from "./data.ts";
import * as format from "./format.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import type { Owner } from "./core/routing.ts";
import type { Topic } from "./protocol.ts";
import type { Value } from "./store.ts";
import { arr as arrU, get as getU, isObject } from "./util.ts";
import { ofAddress } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string => (typeof v === "string" ? v : "");

/// What a workspace's record `feedback` keeps: still.fail cloud's answer, as it gave it.
export const FEEDBACK_RECORD = "feedback";
/// The latest reply of the team's dismissed on this device for each report of the workspace, by report id.
export const FEEDBACK_DISMISSED = "feedbackDismissed";
const DISMISSED_KEPT = 200;

/// The first line of a reply, as the chat's card shows it under its title.
function firstLine(text: string): string {
  const line = text.split("\n").map((l) => l.trim()).find((l) => l !== "") ?? "";
  return line.length > 140 ? `${line.slice(0, 139)}…` : line;
}

/// Who wrote a reply, as the chat says it: the still.fail team, a person by their name, or an agent of the chat's.
function who(reply: J): string {
  if (reply.from === "team") return t("core-misc.feedback.team");
  if (reply.from === "agent") return t("core-misc.feedback.agent");
  return str(reply.name) || t("core-misc.feedback.someone");
}

/// The reports of chat `session` on station `station` (`<workspace>/<id>`) with the team's replies, newest first, as
/// its card and panel show them; `kept`: the workspace's record, `dismissed`: the replies dismissed here by report id.
/// (`account`: the account that reaches the workspace, which answers as the person)
export function chatFeedback(kept: unknown, station: string, session: string, now: number, offsetMin: number, account = "", dismissed: unknown = undefined): J {
  const id = station.slice(station.indexOf("/") + 1);
  const workspace = ofAddress(station);
  const gone = isObject(dismissed) ? dismissed : {};
  const reports = arr(get(kept, "feedback"))
    .filter((f) => str(f?.station) === id && str(f?.session) === session && typeof f?.number === "number")
    .map((f) => {
      const replies = arr(f.replies).filter((r) => typeof r?.id === "string" && typeof r?.text === "string").map((r) => ({
        id: r.id as string,
        from: r.from === "team" ? "team" : r.from === "agent" ? "agent" : "person",
        who: who(r),
        text: r.text as string,
        when: typeof r.created_at === "number" ? format.dayClock(r.created_at * 1000, now, offsetMin) : "",
      }));
      const team = replies.filter((r) => r.from === "team");
      const last = team[team.length - 1];
      const reportId = str(f.id);
      const latestId = last ? last.id : "";
      return {
        id: reportId,
        workspace,
        account,
        number: f.number as number,
        label: `FB-${f.number}`,
        title: str(f.title),
        heading: t("core-misc.feedback.heading", { number: String(f.number) }),
        latest: last ? firstLine(last.text) : "",
        latestId,
        dismissed: latestId !== "" && gone[reportId] === latestId,
        replies,
      };
    })
    .filter((f) => f.replies.some((r) => r.from === "team"));
  return { reports };
}

export class FeedbackReplies implements Owner {
  readonly #host: Host;
  readonly #data: Data;
  readonly #owner: (workspace: string) => string | null;

  constructor(host: Host, data: Data, owner: (workspace: string) => string | null) {
    this.#host = host;
    this.#data = data;
    this.#owner = owner;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "chatFeedback";
  }

  compute(topic: Topic): Value {
    const station = String(topic.station);
    const now = this.#host.nowMs();
    const workspace = ofAddress(station);
    return {
      ok: chatFeedback(
        this.#data.record(FEEDBACK_RECORD, workspace),
        station,
        String(topic.session),
        now,
        this.#host.utcOffsetMin(now),
        this.#owner(workspace) ?? "",
        this.#data.record(FEEDBACK_DISMISSED, workspace),
      ),
    };
  }

  /// Dismisses report `id`'s notice on this device up to the team's reply `reply`: a newer reply brings it back.
  dismiss(workspace: string, id: string, reply: string): void {
    if (workspace === "" || id === "" || reply === "") return;
    const cur = this.#data.record(FEEDBACK_DISMISSED, workspace);
    const prev = isObject(cur) ? cur : {};
    if (prev[id] === reply) return;
    const entries = Object.entries(prev).filter(([k, v]) => k !== id && typeof v === "string");
    entries.push([id, reply]);
    const kept = entries.length > DISMISSED_KEPT ? entries.slice(entries.length - DISMISSED_KEPT) : entries;
    this.#data.put(FEEDBACK_DISMISSED, workspace, Object.fromEntries(kept), false);
  }
}
