// The agents' MCP endpoint over HTTP (mesh/app/src/server.rs `serve_mcp` / `answer_mcp`): loopback only, POST /mcp
// (src/tools/mcp.ts answers it), GET /health, and /jobs/notify (what jobs say, `stillfail-job notify`: the jobs
// module's, given here as `notify`). It listens on the launcher's descriptor when there is one, else on a port.
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import type { McpEndpoint } from "./mcp.ts";

export type McpServerOptions = {
  mcp: McpEndpoint;
  /// What a job said (token, its words): the jobs module's; refused (400) until it is given.
  notify?: (token: string, text: string) => void;
  /// The launcher's listening descriptor, else `host`:`port` (0: any free port).
  fd?: number;
  host?: string;
  port?: number;
};

const LIMIT = 64 * 1024;

function body(req: IncomingMessage, limit: number | null): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (limit !== null && size > limit) {
        reject(new Error("length limit exceeded"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

const json = (res: ServerResponse, status: number, value: unknown) => {
  const text = JSON.stringify(value);
  res.writeHead(status, { "content-type": "application/json", "content-length": Buffer.byteLength(text) }).end(text);
};

async function answer(options: McpServerOptions, req: IncomingMessage, res: ServerResponse) {
  const path = new URL(req.url ?? "/", "http://station").pathname;
  if (path === "/health") return json(res, 200, { ok: true });
  if (path === "/jobs/notify" && req.method === "POST") {
    const token = (req.headers.authorization ?? "").startsWith("Bearer ") ? req.headers.authorization!.slice(7) : "";
    let text: Buffer;
    try {
      text = await body(req, LIMIT);
    } catch (error) {
      return json(res, 400, { error: (error as Error).message });
    }
    try {
      if (!options.notify) throw new Error("jobs are not running on this station");
      options.notify(token, new TextDecoder("utf-8").decode(text));
      return json(res, 200, { ok: true });
    } catch (error) {
      return json(res, 400, { error: (error as Error).message });
    }
  }
  if (path === "/mcp") {
    let given: Buffer;
    try {
      given = await body(req, null);
    } catch (error) {
      return json(res, 400, { error: (error as Error).message });
    }
    const reply = await options.mcp.handle(req.method ?? "", req.headers.authorization, given);
    if (reply.body !== undefined) return json(res, reply.status, reply.body);
    res.writeHead(reply.status, { "content-length": 0 }).end();
    return;
  }
  res.writeHead(404, { "content-type": "text/plain; charset=utf-8", "content-length": 0 }).end();
}

/// Starts serving; resolves with the server and the port it listens on.
export function serveMcp(options: McpServerOptions): Promise<{ server: Server; port: number; url: string }> {
  const server = createServer((req, res) => {
    answer(options, req, res).catch((error) => {
      if (!res.headersSent) json(res, 500, { error: (error as Error).message });
    });
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    const ready = () => {
      const address = server.address() as AddressInfo;
      const host = options.host ?? "127.0.0.1";
      resolve({ server, port: address.port, url: `http://${host}:${address.port}/mcp` });
    };
    if (options.fd !== undefined) server.listen({ fd: options.fd }, ready);
    else server.listen(options.port ?? 0, options.host ?? "127.0.0.1", ready);
  });
}
