import assert from "node:assert/strict";
import { test } from "node:test";
import { lanAddrs, lanKept, lanNeighbours, lanReach, privateV4 } from "../src/mesh/lan.ts";

const nic = (address: string, family: "IPv4" | "IPv6" = "IPv4", internal = false) => ({ address, family, internal, netmask: "", mac: "", cidr: null }) as never;

// studio, 2026-10-17: wired on a VLAN and Wi-Fi on the same network, wired on another besides, OrbStack's bridges.
test("a stations LAN addresses are its private IPv4 ones at its mesh port, bridges and tunnels left out", () => {
  const interfaces = {
    lo0: [nic("127.0.0.1", "IPv4", true)],
    en0: [nic("192.168.0.126"), nic("fe80::1", "IPv6")],
    vlan0: [nic("192.168.20.10")],
    en1: [nic("192.168.20.107")],
    bridge100: [nic("192.168.139.3")],
    bridge101: [nic("192.168.215.0")],
    utun14: [nic("100.67.165.110")],
    en8: [nic("169.254.129.195")],
  };
  assert.deepEqual(lanAddrs(["0.0.0.0:54387", "[::]:56911"], interfaces), ["192.168.0.126:54387", "192.168.20.10:54387", "192.168.20.107:54387"]);
  // Bound to one address (STILLFAIL_MESH_BIND_ADDR): that one alone; no IPv4 socket: none.
  assert.deepEqual(lanAddrs(["192.168.20.10:4770"], interfaces), ["192.168.20.10:4770"]);
  assert.deepEqual(lanAddrs(["[::]:56911"], interfaces), []);
});

test("private IPv4 is RFC 1918's", () => {
  for (const ip of ["10.0.0.1", "172.16.5.4", "172.31.255.255", "192.168.1.1"]) assert.ok(privateV4(ip), ip);
  for (const ip of ["172.32.0.1", "100.67.165.110", "169.254.1.1", "8.8.8.8", "192.169.0.1", "fe80::1"]) assert.ok(!privateV4(ip), ip);
});

// The MacBook of 2026-10-18: on Wi-Fi at 192.168.20.152/24, OrbStack's bridge beside it.
test("the LAN asked whether it can be reached is each one's first address, the station's own skipped", () => {
  const at = (address: string, netmask: string) => ({ address, netmask, family: "IPv4", internal: false, mac: "", cidr: null }) as never;
  const interfaces = { en0: [at("192.168.20.152", "255.255.255.0")], bridge100: [at("192.168.139.3", "255.255.254.0")], en9: [at("169.254.197.190", "255.255.0.0")], en5: [at("10.0.0.1", "255.255.255.0")] };
  assert.deepEqual(lanNeighbours(interfaces), ["192.168.20.1", "10.0.0.2"]);
});

test("the LAN is reached once one takes a byte, refused when each says no route", async () => {
  const says = (codes: Record<string, string | null>) => async (ip: string) => codes[ip] ?? null;
  assert.equal(await lanReach(["192.168.20.1"], says({ "192.168.20.1": "EHOSTUNREACH" })), "denied");
  assert.equal(await lanReach(["192.168.20.1", "192.168.0.1"], says({ "192.168.20.1": "EHOSTUNREACH", "192.168.0.1": null })), "granted");
  assert.equal(await lanReach(["192.168.20.1"], says({ "192.168.20.1": "ENETDOWN" })), null);
  assert.equal(await lanReach([], says({})), null);
});

// The MacBook's app, not let reach its LAN: studio's address on its own subnet refused, the one past the router not.
test("a station's LAN addresses are kept from the app when one on its subnet is refused", async () => {
  const says = (codes: Record<string, string | null>) => async (ip: string) => codes[ip] ?? null;
  const studio = ["192.168.0.126:54829", "192.168.20.10:54829", "192.168.20.107:54829"];
  assert.equal(await lanKept(studio, says({ "192.168.20.10": "EHOSTUNREACH", "192.168.20.107": "EHOSTUNREACH" })), true);
  assert.equal(await lanKept(studio, says({})), false);
  assert.equal(await lanKept(["100.67.165.110:1", "nonsense"], says({ "100.67.165.110": "EHOSTUNREACH" })), false);
});
