// A station opened from ember cloud: the station's own admin client, talking
// to it over iroh, under /w/<workspace>/s/<station>/. The sidebar's header
// shows where you are and switches station or goes back to the workspace.
import { QueryClient, QueryClientProvider, useQuery } from "@tanstack/react-query";
import { useMemo } from "react";
import { BrowserRouter } from "react-router";
import { App } from "../App.tsx";
import { ApiError } from "../api.ts";
import { setTransport } from "../transport.ts";
import { accounts } from "./accounts.ts";
import { cloud } from "./api.ts";
import { SignInGate } from "./gate.tsx";
import { FrameContext, type Frame } from "./switcher.tsx";
import { StationTransport } from "./link.ts";


const cloudClient = new QueryClient({ defaultOptions: { queries: { refetchOnWindowFocus: false, retry: false } } });

export function StationFrame({ ws, station }: { ws: string; station: string }) {
  return (
    <QueryClientProvider client={cloudClient}>
      <SignInGate><Resolve ws={ws} station={station} /></SignInGate>
    </QueryClientProvider>
  );
}

/** Finds which signed-in account reaches this workspace, then opens the station. */
function Resolve({ ws, station }: { ws: string; station: string }) {
  const found = useQuery({
    queryKey: ["frame", ws],
    queryFn: async () => {
      for (const account of accounts()) {
        const me = await cloud.me(account.sub).catch(() => null);
        if (!me?.workspaces.some((w) => w.id === ws)) continue;
        return { account, relay: me.relay_url, workspace: await cloud.workspace(account.sub, ws) };
      }
      return null;
    },
  });
  if (found.isPending) return <div className="gate"><h1>正在连接…</h1></div>;
  if (!found.data) return <div className="gate"><h1>打不开这台 station</h1><p>你登录的账号都不在这个 workspace 里。</p><a className="btn btn-secondary" href="/">回到 ember</a></div>;
  if (!found.data.workspace.stations.some((s) => s.id === station)) {
    return <div className="gate"><h1>找不到这台 station</h1><p>它可能已经从「{found.data.workspace.name}」移除了。</p><a className="btn btn-secondary" href={`/w/${ws}`}>回到 workspace</a></div>;
  }
  return <Station key={`${ws}/${station}`} frame={{ workspace: found.data.workspace, station }} sub={found.data.account.sub} relay={found.data.relay} />;
}

function Station({ frame, sub, relay }: { frame: Frame; sub: string; relay: string }) {
  // One transport and one cache per station, so nothing from another station leaks in.
  const client = useMemo(() => {
    setTransport(new StationTransport(sub, frame.workspace.id, frame.station, relay));
    return new QueryClient({
      defaultOptions: { queries: { refetchOnWindowFocus: false, retry: (n, e) => !(e instanceof ApiError && e.status < 500) && n < 2 } },
    });
  }, [sub, frame.workspace.id, frame.station, relay]);
  return (
    <FrameContext.Provider value={frame}>
      <QueryClientProvider client={client}>
        <BrowserRouter basename={`/w/${frame.workspace.id}/s/${frame.station}`}>
          <App />
        </BrowserRouter>
      </QueryClientProvider>
    </FrameContext.Provider>
  );
}

