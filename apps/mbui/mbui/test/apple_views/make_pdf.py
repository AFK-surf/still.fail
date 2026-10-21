#!/usr/bin/env python3
# A two-page PDF for the self-test: on each page (612 x 792 points) a red
# square near the bottom left (72..272, 72..172) and a blue one near the top
# right (400..500, 650..750); the second page has /Rotate 90.
import sys

content = b"1 0 0 rg 72 72 200 100 re f\n0 0 1 rg 400 650 100 100 re f\n"
objs = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R /Resources << >> >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Rotate 90 /Contents 5 0 R /Resources << >> >>",
    b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream",
]
out = bytearray(b"%PDF-1.4\n")
offs = []
for i, o in enumerate(objs):
    offs.append(len(out))
    out += b"%d 0 obj\n" % (i + 1) + o + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
for o in offs:
    out += b"%010d 00000 n \n" % o
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
open(sys.argv[1], "wb").write(out)
