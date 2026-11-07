import { log } from "../ops/log.ts";
import { BackgroundIndexBuilder } from "../store/background-index-builder.ts";
import { hasProcessJobs, installProcessJobs, processJobs, processJobsReady, processJobsStep, refreshProcessJobs, type ProcessJob } from "../store/process-jobs.ts";
import type { Store } from "../store/store.ts";

/// Memory protection answers immediately while one worker prepares an older station's running groups.
export class ProcessJobsBuilder extends BackgroundIndexBuilder {
  constructor(store: Store, previous: Promise<void>, workerFile?: URL) {
    super(store, previous, {
      scope: "memory", name: "process job", previousName: "jobs", kind: "process-jobs",
      install: () => installProcessJobs(store.db), ready: () => processJobsReady(store.db),
      step: () => processJobsStep(store.db), refresh: () => refreshProcessJobs(store.db),
    }, workerFile);
  }

  read(): ProcessJob[] | null {
    if (this.stopped) return null;
    try { return processJobs(this.store.db); }
    catch (error) { log.warn("memory", "the process job lookup could not be read", { error: (error as Error).message }); return null; }
  }

  /// The old answer already counted these rows. Small stations need no extra index or probe.
  consider(running: number): void {
    this.buildIf(() => {
      const installed = hasProcessJobs(this.store.db);
      return !((installed && processJobsReady(this.store.db)) || (!installed && running <= 32));
    });
  }
}
