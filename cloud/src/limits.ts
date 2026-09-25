// Shared relay budget; kept apart from the Durable Object so tests can read it.
export const LIMITS = {
  // Every open web page holds one relay connection, and every station one; sized for a few teams.
  connections: 64,
  connectsPerMinute: 120,
  bytesPerSecond: 4 * 1024 * 1024,
  burstBytes: 8 * 1024 * 1024,
  bytesPerDay: 5 * 1024 * 1024 * 1024,
  frameBytes: 128 * 1024,
  framesPerSecond: 4096,
  burstFrames: 8192,
  framesPerDay: 20_000_000,
};
