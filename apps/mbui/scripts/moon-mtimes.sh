#!/bin/bash
# CI, before moon builds over the build main's last run left (the moon cache): each file of apps/mbui given an mtime
# that is its content's (from its blob's id), the same in every checkout of that content. moon builds again a file whose
# mtime is not the one it built from, older or newer: a checkout gives every file a new one, and moon built all of it
# again over the cache each run (80 tasks, 95 s of the Mac job's 243 where three files of two pages had changed: main
# f4e79a00, 41364512757, 2026-11-01). With these, only what changed differs from the build it took.
# CI only: the content is the index's (a file changed and not committed keeps its old one, and moon would not see it).
#   scripts/moon-mtimes.sh
set -e
cd "$(git rev-parse --show-toplevel)"
# (git ls-files -s: mode, blob id, stage, path; 2000-01-01 plus its first 28 bits in seconds, 2000 to 2008: never ahead of the clock)
git ls-files -s -z apps/mbui | perl -0ne '
  my ($meta, $path) = split /\t/, $_, 2; $path =~ s/\0$//;
  my $t = 946684800 + hex(substr((split / /, $meta)[1], 0, 7));
  next if -l $path || ! -e $path;
  utime($t, $t, $path) or die "moon-mtimes: $path: $!\n"; $n++;
  END { print "moon-mtimes: $n files of apps/mbui given their content'"'"'s mtime\n" }'
