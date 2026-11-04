import assert from "node:assert/strict";
import { test } from "node:test";
import { lanAddrs, lanNeighbours, lanReach, privateV4, tailnetAddrs, tailnetV4 } from "../src/mesh/lan.ts";

const nic = (address: string, family: "IPv4" | "IPv6" = "IPv4", internal = false) => ({ address, family, internal, netmask: "", mac: "", cidr: null }) as never;

// A host wired on a VLAN and on Wi-Fi on the same network, wired on another besides, and with VM bridges.
test("a stations LAN addresses are its private IPv4 ones at its mesh port, bridges and tunnels left out", () => {
  const interfaces = {
    lo0: [nic("127.0.0.1", "IPv4", true)],
    en0: [nic("192.168.77.26"), nic("fe80::1", "IPv6")],
    vlan0: [nic("192.168.50.22")],
    en1: [nic("192.168.50.227")],
    bridge100: [nic("192.168.139.3")],
    bridge101: [nic("192.168.215.0")],
    utun14: [nic("100.95.1.2")],
    en8: [nic("169.254.8.3")],
  };
  assert.deepEqual(lanAddrs(["0.0.0.0:54387", "[::]:56911"], interfaces), ["192.168.77.26:54387", "192.168.50.22:54387", "192.168.50.227:54387"]);
  // Bound to one address (STILLFAIL_MESH_BIND_ADDR): that one alone; no IPv4 socket: none.
  assert.deepEqual(lanAddrs(["192.168.50.22:4770"], interfaces), ["192.168.50.22:4770"]);
  assert.deepEqual(lanAddrs(["[::]:56911"], interfaces), []);
});

// A Tailscale address is on a utun (macOS), left out of its LAN; Linux's is on tailscale0.
test("a stations tailnet addresses are its Tailscale ones at its mesh port, whatever their interface is called", () => {
  const interfaces = { en0: [nic("192.168.77.26")], utun14: [nic("100.95.1.2"), nic("fd7a:115c:a1e0::1", "IPv6")], tailscale0: [nic("100.101.2.3")], wwan0: [nic("100.128.0.9")] };
  assert.deepEqual(tailnetAddrs(["0.0.0.0:54387", "[::]:56911"], interfaces), ["100.95.1.2:54387", "100.101.2.3:54387"]);
  assert.deepEqual(tailnetAddrs(["192.168.77.26:4770"], interfaces), []);
  for (const ip of ["100.64.0.1", "100.127.255.254"]) assert.ok(tailnetV4(ip), ip);
  for (const ip of ["100.63.255.255", "100.128.0.1", "10.0.0.1"]) assert.ok(!tailnetV4(ip), ip);
});

test("private IPv4 is RFC 1918's", () => {
  for (const ip of ["10.0.0.1", "172.16.5.4", "172.31.255.255", "192.168.1.1"]) assert.ok(privateV4(ip), ip);
  for (const ip of ["172.32.0.1", "100.95.1.2", "169.254.1.1", "8.8.8.8", "192.169.0.1", "fe80::1"]) assert.ok(!privateV4(ip), ip);
});

// A host on Wi-Fi at 192.168.50.44/24, OrbStack's bridge beside it.
test("the LAN asked whether it can be reached is each one's first address, the station's own skipped", () => {
  const at = (address: string, netmask: string) => ({ address, netmask, family: "IPv4", internal: false, mac: "", cidr: null }) as never;
  const interfaces = { en0: [at("192.168.50.44", "255.255.255.0")], bridge100: [at("192.168.139.3", "255.255.254.0")], en9: [at("169.254.9.4", "255.255.0.0")], en5: [at("10.0.0.1", "255.255.255.0")] };
  assert.deepEqual(lanNeighbours(interfaces), ["192.168.50.1", "10.0.0.2"]);
});

test("the LAN is reached once one takes a byte, refused when each says no route", async () => {
  const says = (codes: Record<string, string | null>) => async (ip: string) => codes[ip] ?? null;
  assert.equal(await lanReach(["192.168.50.1"], says({ "192.168.50.1": "EHOSTUNREACH" })), "denied");
  assert.equal(await lanReach(["192.168.50.1", "192.168.77.1"], says({ "192.168.50.1": "EHOSTUNREACH", "192.168.77.1": null })), "granted");
  assert.equal(await lanReach(["192.168.50.1"], says({ "192.168.50.1": "ENETDOWN" })), null);
  assert.equal(await lanReach([], says({})), null);
});
