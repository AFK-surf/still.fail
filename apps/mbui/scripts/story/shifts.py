# How far a film's list moved each frame: a strip of each frame (gray, its left part) matched against the one before,
# the best vertical offset said per frame (a jump or a frame that stood still shows as an odd one out).
import subprocess, sys
film, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
W, H = 60, 787
raw = subprocess.run(["/opt/homebrew/bin/ffmpeg", "-loglevel", "error", "-i", film, "-vf",
    f"trim=start_frame={a}:end_frame={b + 1},crop=180:2362:40:0,scale={W}:{H},format=gray", "-f", "rawvideo", "-"],
    capture_output=True, check=True).stdout
n = len(raw) // (W * H)
rows = [[sum(raw[f * W * H + y * W:(f * W * H + (y + 1) * W)]) for y in range(H)] for f in range(n)]
for f in range(1, n):
    p, q = rows[f - 1], rows[f]
    best = min(range(-80, 81), key=lambda s: sum(abs(q[y] - p[y + s]) for y in range(120, H - 160) if 0 <= y + s < H))
    err = sum(abs(q[y] - p[y + best]) for y in range(120, H - 160) if 0 <= y + best < H) // 1000
    print(a + f, best * 3, err)
