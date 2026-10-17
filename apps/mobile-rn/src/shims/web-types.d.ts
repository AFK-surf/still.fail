// What the web modules the app type-checks through import from packages only the web app has (web/src/telemetry.ts,
// which src/shims/telemetry.ts stands in for when bundling): enough for the checker to read them.
declare module "posthog-js" {
  export type CaptureResult = any;
  export type Properties = Record<string, any>;
  export interface PostHog {
    init(key: string, config: Record<string, any> & { session_recording?: Record<string, any> & { maskAttributeFn?: (name: string, value: string) => string } }): void;
    [k: string]: any;
  }
  export const posthog: PostHog;
}
declare module "react-router" {
  export function useLocation(): { pathname: string };
}
