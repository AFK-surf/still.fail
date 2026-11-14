// The one function of the driver plugin's (dsh-bridge.mjs) the station's tests read: the driver apart from the
// process's stdin and stdout.
export function driver(
  ctx: unknown,
  config: { tools?: string } | undefined,
  write: (message: Record<string, unknown>) => void,
): { line(line: string): Promise<void>; closed(): Promise<void> };
