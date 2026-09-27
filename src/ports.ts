// The agents' MCP endpoint's port (the admin page's is ember-station's: mesh/station/src/local.rs, alike). A port the
// config names is the station's to keep: taken, starting fails and says by what. Unnamed, the usual one (4750) is
// taken if free, else any free one: another program on the machine (an old ssh tunnel, a second ember) must not keep
// the station from starting.
import type { Server } from "node:http";

export class PortTaken extends Error {}

/** Listens on `port`, or, when it is only the usual one (not named in the config) and taken, on any free port. */
export async function listen(server: Server, host: string, port: number, named: boolean, what: string): Promise<number> {
  try {
    return await listenOn(server, host, port);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EADDRINUSE") throw error;
    if (named) throw new PortTaken(`${what} 的端口 ${host}:${port} 已被别的程序占用（配置里指定了这个端口）。用 \`lsof -nP -iTCP:${port} -sTCP:LISTEN\` 看是谁，或在配置里换一个端口。`);
    return listenOn(server, host, 0);
  }
}

function listenOn(server: Server, host: string, port: number): Promise<number> {
  return new Promise((resolve, reject) => {
    const failed = (error: Error) => reject(error);
    server.once("error", failed);
    server.listen(port, host, () => {
      server.off("error", failed);
      const address = server.address();
      resolve(typeof address === "object" && address ? address.port : port);
    });
  });
}
