import assert from "node:assert/strict";
import { test } from "node:test";
import { lanAddrs, privateV4 } from "../src/mesh/lan.ts";

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
