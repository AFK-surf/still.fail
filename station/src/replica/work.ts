// The export's work as one thing (replica/AGENTS.md): a pass of the exporter, and where the files its batches name are.
// In the worker thread (worker.ts) as the station runs; in a test's own thread, its clock the test's.
import { type ExporterOptions, Exporter, type Passed, type Places, type Told } from "./export.ts";

/// A pass, and whether the station has no chat of its own (a copy is taken back only into such a one).
export type WorkPassed = Passed & { empty: boolean };

export class ExportWork {
  readonly exporter: Exporter;

  constructor(o: ExporterOptions) {
    this.exporter = new Exporter(o);
  }

  close(): void {
    this.exporter.close();
  }

  setPlaces(places: Places): void {
    this.exporter.setPlaces(places);
  }

  newGenerations(after: number): void {
    this.exporter.newGenerations(after);
  }

  pass(told: Told): WorkPassed {
    return { ...this.exporter.pass(told), empty: this.exporter.empty() };
  }

  sources(hashes: string[]): Record<string, string> {
    const out: Record<string, string> = {};
    for (const h of hashes) {
      const s = this.exporter.sourceOf(h);
      if (s !== null) out[h] = s;
    }
    return out;
  }
}
