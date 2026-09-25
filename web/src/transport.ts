// How the admin client reaches a station's admin API. On the station itself
// it is plain HTTP; from ember cloud it is an iroh link (see cloud/link.ts).
// Both give the same shape: a JSON request, and a stream of server events.

export interface Transport {
  /** One request; resolves to status and parsed JSON body. */
  request(method: string, path: string, body?: unknown): Promise<{ status: number; data: unknown }>;
  /** Follows /admin/api/events; `onEvent(name, data)` per event, `onOpen` on each (re)connect. Returns a stop function. */
  events(onEvent: (name: string, data: string) => void, onOpen: () => void): () => void;
}

/** Same-origin HTTP: the page was served by the station. */
export const localTransport: Transport = {
  async request(method, path, body) {
    const response = await fetch(`/admin/api${path}`, {
      method,
      credentials: "same-origin",
      headers: body === undefined ? {} : { "content-type": "application/json" },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, data: await response.json().catch(() => ({})) };
  },
  events(onEvent, onOpen) {
    const source = new EventSource("/admin/api/events");
    for (const name of ["session", "config", "login"]) source.addEventListener(name, (e) => onEvent(name, (e as MessageEvent<string>).data));
    source.addEventListener("open", onOpen);
    return () => source.close();
  },
};

let current: Transport = localTransport;

export function setTransport(transport: Transport): void {
  current = transport;
}

export function transport(): Transport {
  return current;
}

/** Splits a text/event-stream into events; feed it chunks, it calls back per complete event. */
export function sseParser(onEvent: (name: string, data: string) => void): (chunk: string) => void {
  let buffer = "";
  return (chunk) => {
    buffer += chunk.replace(/\r\n/g, "\n");
    let end: number;
    while ((end = buffer.indexOf("\n\n")) >= 0) {
      const block = buffer.slice(0, end);
      buffer = buffer.slice(end + 2);
      let name = "message";
      const data: string[] = [];
      for (const line of block.split("\n")) {
        if (line.startsWith("event:")) name = line.slice(6).trim();
        else if (line.startsWith("data:")) data.push(line.slice(5).replace(/^ /, ""));
      }
      if (data.length) onEvent(name, data.join("\n"));
    }
  };
}
