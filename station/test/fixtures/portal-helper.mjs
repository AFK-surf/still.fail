// A portal process with a deterministic framed stream, for testing the station's process boundary.
import { createInterface } from "node:readline";
import { writeFileSync } from "node:fs";

function send(kind, value) {
  const body = Buffer.isBuffer(value) ? value : Buffer.from(JSON.stringify(value));
  const head = Buffer.alloc(5);
  head.writeUInt8(kind, 0);
  head.writeUInt32BE(body.length, 1);
  // Headers and bodies need not arrive in the same read from a real pipe.
  process.stdout.write(head.subarray(0, 2));
  process.stdout.write(Buffer.concat([head.subarray(2), body]));
}

if (process.env.STILLFAIL_TEST_HOLD_CONSENT === "1") send(1, { type: "consent" });
else send(1, { type: "ready", width: 1280, height: 800 });
createInterface({ input: process.stdin }).on("line", (line) => {
  const command = JSON.parse(line);
  if (command.op === "start") {
    send(1, { type: "picture", width: 640, height: 400 });
    send(2, Buffer.from([0xff, 0xd8, 0xff, 0xd9]));
  } else if (command.op === "input") {
    // The test reads this frame to know the helper received the input.
    send(2, Buffer.from(JSON.stringify(command.event)));
  } else if (command.op === "close") {
    if (process.env.STILLFAIL_TEST_CLOSE_MARKER) writeFileSync(process.env.STILLFAIL_TEST_CLOSE_MARKER, "closed");
    process.exit(0);
  }
});
