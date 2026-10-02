// feedback_send (mesh/app/src/feedback.rs): a bug report about still.fail itself, sent to the still.fail team, for a
// station on the stable channel. The report is made here as the Rust makes it; sending it is still.fail cloud's
// (`send`, the cloud module's signed /v1/stations/feedback, not ported yet): until it is given, the agent is told the
// report cannot be sent, as the Rust station says when it is not connected to cloud.
import { createHash } from "node:crypto";
import type { SessionRow, Store } from "../store/store.ts";
import type { Tool } from "./mcp.ts";

type Json = any;

export const FEEDBACK_SEND = {
  name: "feedback_send",
  description:
    "Send a bug report about still.fail itself (the station, its tools, the still.fail apps, web or cloud, its Slack side) to the still.fail team. Only after the person you work for agreed to it and saw what is sent; the stillfail-feedback skill says when and how. Not for bugs in their own code or other services.",
  inputSchema: {
    "type": "object",
    "properties": {
      "to": {
        "type": "string",
        "description": "CHANNEL/THREAD_TS of the conversation the problem came up in."
      },
      "title": {
        "type": "string",
        "description": "One line: what goes wrong (at most 200 characters)."
      },
      "body": {
        "type": "string",
        "description": "Markdown: what happened, what was expected, how to get there, when, and anything else the team needs to find it. Only what the person agreed to send."
      },
      "area": {
        "type": "string",
        "enum": [
          "station",
          "web",
          "android",
          "desktop",
          "slack",
          "cloud",
          "unknown"
        ],
        "description": "The part of still.fail it is in, as far as you can tell."
      },
      "reporter": {
        "type": "string",
        "description": "Who reports it: their name and where they said it (e.g. \"Ada, Slack #ops\")."
      },
      "logs": {
        "type": "string",
        "description": "Optional: the lines of the station's own logs or tool errors that show the problem (at most 64 KB). No secrets, no people's content."
      }
    },
    "required": [
      "to",
      "title",
      "body"
    ],
    "additionalProperties": false
  },
};

/// What a report is about, as still.fail cloud takes it (cloud/src/feedback.ts).
const AREAS = ["station", "web", "android", "desktop", "slack", "cloud", "unknown"];

/// std::env::consts as Rust names them.
const OS: Record<string, string> = { darwin: "macos", linux: "linux", win32: "windows" };
const ARCH: Record<string, string> = { arm64: "aarch64", x64: "x86_64" };

/// The report still.fail cloud is sent: the agent's words, and what the station adds of the session. `key` is the same
/// for the same report from the same session, so a call tried again is not a second report.
export function report(session: SessionRow, args: Record<string, Json>, link: string | null): Json {
  const text = (k: string) => (typeof args[k] === "string" ? (args[k] as string).trim() : "");
  const [title, body] = [text("title"), text("body")];
  if (title === "" || body === "") throw new Error("title and body are required");
  const area = AREAS.includes(text("area")) ? text("area") : "unknown";
  const key = createHash("sha256").update(`${session.key}\n${title}\n${body}`).digest().subarray(0, 16).toString("hex");
  const context: Json = {
    session: session.key,
    connect: session.connect,
    runtime: session.runtime,
    profile: session.profile,
    os: OS[process.platform] ?? process.platform,
    arch: ARCH[process.arch] ?? process.arch,
  };
  for (const [name, value] of [["model", session.model], ["thread", text("to") === "" ? null : text("to")], ["link", link]] as const) {
    if (value !== null) context[name] = value;
  }
  const out: Json = { key, title, body, area, reporter: text("reporter"), context };
  if (text("logs") !== "") out.logs = text("logs");
  return out;
}

/// `link`: a session's page on still.fail cloud; `send`: the report to cloud, its answer (`{number, duplicate?}`).
export function feedbackTools(store: Store, link: (key: string) => string | null, send: () => ((report: Json) => Promise<Json>) | null): Tool[] {
  return [
    {
      ...FEEDBACK_SEND,
      run: async (key, args) => {
        const session = store.getSession(key);
        if (!session) throw new Error("unknown session");
        const made = report(session, args, link(key));
        const sender = send();
        if (!sender) throw new Error("this station is not connected to still.fail cloud, so the report cannot be sent; give the person the report to pass on themselves");
        let answer: Json;
        try {
          answer = await sender(made);
        } catch (error) {
          throw new Error(`the report was not sent (${(error as Error).message}); give the person the report to pass on themselves`);
        }
        const number = answer?.number;
        if (typeof number !== "number" || !Number.isInteger(number) || number < 0) throw new Error(`still.fail cloud answered without a number: ${JSON.stringify(answer)}`);
        return answer?.duplicate === true ? `This report was already sent as FB-${number}.` : `Sent to the still.fail team as FB-${number}.`;
      },
    },
  ];
}
