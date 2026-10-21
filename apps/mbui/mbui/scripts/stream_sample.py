#!/usr/bin/env python3
"""The streams demo's sample (src/streamdemo/sample.mbt): H.264 as a remote screen sends it (an avcC, then access
units in AVCC with whether each is a key frame) and a few JPEG frames, made by ffmpeg from its test pattern.

    python3 scripts/stream_sample.py [out.mbt]     (ffmpeg on PATH)
"""
import base64
import os
import subprocess
import sys
import tempfile

W, H, FPS, FRAMES = 640, 360, 10, 15


def nals(annexb):
    """The NAL units of an Annex B stream, start codes taken off."""
    out, i, n = [], 0, len(annexb)
    starts = []
    while i + 3 <= n:
        if annexb[i:i + 3] == b"\0\0\1":
            starts.append(i + 3)
            i += 3
        else:
            i += 1
    for k, s in enumerate(starts):
        e = starts[k + 1] - 3 if k + 1 < len(starts) else n
        u = annexb[s:e]
        # (a 4-byte start code's leading zero belongs to it, not to the NAL before)
        while u.endswith(b"\0") and k + 1 < len(starts):
            u = u[:-1]
        out.append(u)
    return out


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "src", "streamdemo", "sample.mbt")
    with tempfile.TemporaryDirectory() as d:
        h264 = os.path.join(d, "s.h264")
        subprocess.run([
            "ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", f"testsrc=size={W}x{H}:rate={FPS}",
            "-frames:v", str(FRAMES), "-c:v", "libx264", "-profile:v", "baseline", "-preset", "veryfast",
            "-tune", "zerolatency", "-crf", "30", "-g", "10", "-pix_fmt", "yuv420p",
            "-bsf:v", "h264_metadata=aud=insert", "-f", "h264", h264,
        ], check=True)
        jpegs = []
        for k in range(3):
            j = os.path.join(d, f"f{k}.jpg")
            subprocess.run([
                "ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", f"testsrc=size=320x180:rate=1",
                "-vf", f"select=eq(n\\,{k * 3})", "-frames:v", "1", "-q:v", "12", j,
            ], check=True)
            jpegs.append(open(j, "rb").read())
        units = nals(open(h264, "rb").read())
    sps = next(u for u in units if u[0] & 0x1f == 7)
    pps = next(u for u in units if u[0] & 0x1f == 8)
    avcc = bytes([1, sps[1], sps[2], sps[3], 0xff, 0xe1]) + len(sps).to_bytes(2, "big") + sps + bytes([1]) + \
        len(pps).to_bytes(2, "big") + pps
    # access units: from one delimiter (type 9) to the next; the parameter sets are the avcC's
    frames, cur = [], None
    for u in units:
        t = u[0] & 0x1f
        if t == 9:
            cur = []
            frames.append(cur)
        elif t not in (7, 8) and cur is not None:
            cur.append(u)
    lines = [
        "// Made by scripts/stream_sample.py (ffmpeg's test pattern): H.264 as a remote screen sends it, an avcC and",
        f"// access units in AVCC ({W}x{H}, {len(frames)} frames, a key frame every 10), and JPEG frames (320x180).",
        "",
        "///|",
        "let sample_w : Int = %d" % W,
        "",
        "///|",
        "let sample_h : Int = %d" % H,
        "",
        "///|",
        'let sample_avcc : String = "%s"' % base64.b64encode(avcc).decode(),
        "",
        "///|",
        "/// Each access unit: whether it is a key frame, its bytes in base64.",
        "let sample_frames : Array[(Bool, String)] = [",
    ]
    for f in frames:
        au = b"".join(len(u).to_bytes(4, "big") + u for u in f)
        key = any(u[0] & 0x1f == 5 for u in f)
        lines.append('  (%s, "%s"),' % ("true" if key else "false", base64.b64encode(au).decode()))
    lines += ["]", "", "///|", "let sample_jpegs : Array[String] = ["]
    for j in jpegs:
        lines.append('  "%s",' % base64.b64encode(j).decode())
    lines += ["]", ""]
    with open(out_path, "w") as f:
        f.write("\n".join(lines))
    print(f"{out_path}: avcC {len(avcc)} bytes, {len(frames)} frames, {sum(len(x) for x in jpegs)} bytes of JPEG")


main()
