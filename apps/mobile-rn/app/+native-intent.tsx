// Links the app is opened with are the app's (src/Main.tsx handles them: the sign-in coming back, an item's link), not
// routes: the router stays on its one route whatever the link.
export function redirectSystemPath({ path }: { path: string; initial: boolean }): string {
  void path;
  return "/";
}
