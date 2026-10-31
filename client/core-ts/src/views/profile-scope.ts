// Whether a station's profile can run chats of this workspace. Older stations say this only in the list of joined
// workspaces; their home workspace can use every profile.
export function profileServes(p: unknown, workspace: string, joined: boolean): boolean {
  const profile = p !== null && typeof p === "object" && !Array.isArray(p) ? p as Record<string, unknown> : {};
  if (typeof profile.serves === "boolean") return profile.serves;
  return !joined || (Array.isArray(profile.workspaces) && profile.workspaces.includes(workspace));
}
