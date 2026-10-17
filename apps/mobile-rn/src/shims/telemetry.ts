// web/src/telemetry.ts for the app: no PostHog here yet; errors go to the log.
export function startTelemetry(): void {}
export function telemetrySettled(): Promise<void> { return Promise.resolve(); }
export function pathTemplate(path: string): string { return path; }
export function track(): void {}
export function trackNow(): void {}
export function captureException(error: unknown): void { console.warn("still.fail:", error); }
export function identify(): void {}
export function signedOut(): void {}
export function PageViews(): null { return null; }
export function chatClicked(): void {}
export function chatOpening(): { at: number; cold: boolean } { return { at: Date.now(), cold: false }; }
