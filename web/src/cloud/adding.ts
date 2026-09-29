// Adding people to a workspace: emails as typed or pasted, and the people of the Slack workspaces the workspace's
// stations are connected to (each station reads its own Slack; its tokens never leave it).
import { useCallback, useState } from "react";
import { useStations } from "../api.ts";
import { useCall } from "../core/react.ts";

/** A Slack workspace member, by their email there. */
export interface SlackPerson {
  email: string;
  name: string;
  image: string | null;
  /** A guest of the Slack workspace (single- or multi-channel). */
  guest: boolean;
  team: string | null;
}

/** The emails in what was typed or pasted: separated by commas, spaces, semicolons or lines; "Name <a@b.c>" too. */
export function parseEmails(text: string): string[] {
  const found = text.match(/[^\s<>,;"'()]+@[^\s<>,;"'()]+\.[^\s<>,;"'()]+/g) ?? [];
  return [...new Set(found.map((e) => e.toLowerCase()))];
}

/** The people of the Slack workspaces this workspace's online stations are in, read when asked for. */
export function useSlackPeople(workspace: string) {
  const call = useCall();
  const stations = useStations(workspace).value ?? [];
  const online = stations.filter((s) => s.online);
  const [people, setPeople] = useState<SlackPerson[] | null>(null);
  const [errors, setErrors] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const addresses = online.map((s) => s.station).join(" ");
  const load = useCallback(async () => {
    setBusy(true);
    const seen = new Map<string, SlackPerson>();
    const problems: string[] = [];
    for (const station of addresses.split(" ").filter(Boolean)) {
      try {
        const read = await call("slack.people", { station }) as { people: SlackPerson[]; errors: string[] };
        for (const p of read.people) if (!seen.has(p.email)) seen.set(p.email, p);
        problems.push(...read.errors);
      } catch (error) {
        problems.push(error instanceof Error ? error.message : String(error));
      }
    }
    setPeople([...seen.values()].sort((a, b) => Number(a.guest) - Number(b.guest) || a.name.localeCompare(b.name)));
    setErrors(problems);
    setBusy(false);
  }, [call, addresses]);
  return { people, errors, busy, load, available: online.length > 0 };
}
