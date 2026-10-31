// The channels a station has (channels/channels.ts): a thread's entries, and a session's transcript. Each says how its
// station is asked for it; where their items are held is the core's database (`heldIn`). What is done with a channel is
// the same for both.
import type { Channel, Held, Kind, Read } from "../channels/channels.ts";
import type { Data } from "../data.ts";
import { nOf } from "../entries.ts";
import { encode } from "../ops.ts";
import { get } from "../util.ts";

/// Entries per page of a thread, and items per page of a transcript.
export const PAGE = 50;
export const TRANSCRIPT_PAGE = 200;

const u64 = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);
const list = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);

/// A thread's entries (GET /threads/:id/entries): numbered from 1, each saying its number (`n`), all of them brought
/// onto the device. How far a thread goes is its summary's `last`.
export const ENTRIES: Kind = {
  name: "entry",
  first: 1,
  page: PAGE,
  whole: true,
  cost: 1,
  task: (id) => `entries/${id}`,
  path: (id, read) => {
    const entries = `/threads/${id}/entries`;
    if ("latest" in read) return `${entries}?limit=${PAGE}`;
    if ("after" in read) return `${entries}?after=${read.after}`;
    if ("before" in read) return `${entries}?before=${read.before}&limit=${PAGE}`;
    return `${entries}?from=${read.from}&to=${read.to}`;
  },
  items: (answer) =>
    list(get(answer, "entries")).flatMap((e) => {
      const n = nOf(e);
      return n === null ? [] : [[n, e] as [number, unknown]];
    }),
  last: (answer) => u64(get(answer, "last")),
};

/// A session's transcript (GET /sessions/:key/timeline): numbered from 0 by where an item stands (a page says where it
/// starts), in brief but for a stretch read whole (`whole`: a step opened). Its latest page is brought, and from the
/// lowest item held on it is kept whole (`holes`): what came after what is held and a hole a stream left are read in the
/// background, as soon as anything says it goes further (its session's summary, `transcriptLength`; a stream telling
/// where it stands; an answer's `end`); the pages before as they are gone back to. A station from before says neither
/// `after` nor `end`: its latest page is what comes after what is held there.
export const TRANSCRIPT: Kind = {
  name: "transcript",
  first: 0,
  page: TRANSCRIPT_PAGE,
  whole: false,
  holes: true,
  cost: 5,
  task: (id) => `transcript/${id}`,
  path: (id, read) => {
    const timeline = `/sessions/${encode(id)}/timeline`;
    if ("from" in read) return `${timeline}?from=${read.from}&to=${read.to}${read.whole === true ? "" : "&brief=1"}`;
    const latest = `before=${"before" in read ? read.before : 1000000000000000}&limit=${TRANSCRIPT_PAGE}&brief=1`;
    return "after" in read ? `${timeline}?after=${read.after}&${latest}` : `${timeline}?${latest}`;
  },
  items: (answer, read: Read) => {
    const start = u64(get(answer, "start")) ?? ("from" in read ? read.from : 0);
    return list(get(answer, "entries")).map((item, i) => [start + i, item] as [number, unknown]);
  },
  last: (answer) => {
    const end = u64(get(answer, "end"));
    return end !== null && end > 0 ? end - 1 : null;
  },
};

/// A thread's letters (GET /threads/:id/letters): what its agents and other chats' wrote each other, their own log beside
/// its entries, numbered from 1 in it, each as an entry is said (marked `letter`). How far it goes is the thread's summary's
/// `lettersLast`. Brought onto the device as the letters are read (their page), then kept whole. Letters from before
/// their log are among the thread's entries.
export const LETTERS: Kind = {
  name: "letter",
  first: 1,
  page: PAGE,
  whole: true,
  cost: 1,
  task: (id) => `letters/${id}`,
  path: (id, read) => {
    const letters = `/threads/${id}/letters`;
    if ("latest" in read) return `${letters}?limit=${PAGE}`;
    if ("after" in read) return `${letters}?after=${read.after}`;
    if ("before" in read) return `${letters}?before=${read.before}&limit=${PAGE}`;
    return `${letters}?from=${read.from}&to=${read.to}`;
  },
  items: (answer) =>
    list(get(answer, "letters")).flatMap((e) => {
      const n = nOf(e);
      return n === null ? [] : [[n, e] as [number, unknown]];
    }),
  last: (answer) => u64(get(answer, "last")),
};

export const entriesOf = (station: string, thread: number): Channel => ({ kind: ENTRIES, station, id: String(thread) });
export const lettersOf = (station: string, thread: number): Channel => ({ kind: LETTERS, station, id: String(thread) });
export const transcriptOf = (station: string, session: string): Channel => ({ kind: TRANSCRIPT, station, id: session });

/// Where the channels' items are held: the logs of the core's database, by number (data.ts), let go for room where a
/// chat was not opened for long (KEPT). How far a thread goes is its summary's `last` there; a transcript, its session's
/// summary's `transcriptLength`, or further as a stream or a read said.
/// `follows`: whether a station's stream follows the sessions at work itself (link.ts `followsRunning`): only then is
/// a transcript kept whole from its lowest item held (a station from before says neither how far one goes nor gives a
/// stretch in brief).
export function heldIn(data: Data, follows: (station: string) => boolean = () => true): Held {
  const table = (c: Channel) => (c.kind === ENTRIES ? "entry" : c.kind === LETTERS ? "letter" : "transcript");
  // (how far a thread's letters go, as told since its summary: a letter told before its summary is read again)
  const lettersRaised = new Map<string, number>();
  const lettersHead = (c: Channel) => {
    const said = u64(get(data.thread(c.station, Number(c.id)), "lettersLast")) ?? 0;
    return Math.max(said, lettersRaised.get(`${c.station}\u0001${c.id}`) ?? 0, data.logSpan("letter", c.station, c.id)?.max ?? 0);
  };
  return {
    numbers: (c) => data.logNumbers(table(c), c.station, c.id),
    span: (c) => data.logSpan(table(c), c.station, c.id),
    count: (c, from, to) => data.logCount(table(c), c.station, c.id, from, to),
    put: (c, items, cutAfter) => data.putItems(table(c), c.station, c.id, items, cutAfter),
    letGo: (c) => data.evicted(table(c), c.station, c.id),
    head: (c) => (c.kind === ENTRIES ? data.threadLast(c.station, Number(c.id)) : c.kind === LETTERS ? lettersHead(c) : data.transcriptHead(c.station, c.id)),
    raise: (c, n) => {
      if (c.kind === ENTRIES) data.raiseLast(c.station, Number(c.id), n);
      else if (c.kind === LETTERS) lettersRaised.set(`${c.station}\u0001${c.id}`, Math.max(n, lettersRaised.get(`${c.station}\u0001${c.id}`) ?? 0));
      else data.raiseTranscript(c.station, c.id, n);
    },
    holes: (c) => c.kind !== TRANSCRIPT || follows(c.station),
    whole: (c) => c.kind === TRANSCRIPT && follows(c.station) && data.usedLately(c.station, c.id),
  };
}
