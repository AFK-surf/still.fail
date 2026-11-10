import { parentPort } from "node:worker_threads";
import { transcriptLocationHints, transcriptSources, useTranscriptLocationHints, type TranscriptLocationHints } from "../src/read/transcript.ts";

parentPort!.on("message", (ask: { data: string; profiles: { id: string; home: string }[]; sources: { id: string; runtime: string; profile: string | null }[]; places: string[]; hints: TranscriptLocationHints }) => {
  useTranscriptLocationHints(ask.hints);
  const found = transcriptSources(ask.data, ask.profiles, ask.sources, ask.places, { anywhere: false });
  parentPort!.postMessage({ found, hints: transcriptLocationHints(ask.data, ask.profiles, ask.sources).value });
});
