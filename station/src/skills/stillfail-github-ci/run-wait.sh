#!/usr/bin/env bash
# Waits for given workflow runs (a release, a deploy): exit 1 as soon as a job fails, 0 when all succeeded, 2 when a
# run cannot be read.
# Usage: bash run-wait.sh <owner/name> <run id> [run id ...]
set -eu

repo=${1:?usage: run-wait.sh <owner/name> <run id> [run id ...]}
shift
if [ "$#" -eq 0 ]; then
  echo 'at least one run id is needed' >&2
  exit 2
fi

while :; do
  pending=0
  for id in "$@"; do
    if ! run=$(gh run view "$id" -R "$repo" --json status,conclusion,jobs); then
      echo "cannot read run $id" >&2
      exit 2
    fi
    bad=$(printf '%s' "$run" | jq -r '.jobs[] | select(.status == "completed" and (.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "cancelled" or .conclusion == "action_required")) | "\(.name)\t\(.url)"')
    if [ -n "$bad" ]; then
      printf 'run %s failed:\n%s\n' "$id" "$bad" >&2
      exit 1
    fi
    status=$(printf '%s' "$run" | jq -r .status)
    if [ "$status" = completed ]; then
      conclusion=$(printf '%s' "$run" | jq -r .conclusion)
      if [ "$conclusion" != success ]; then
        printf 'run %s ended: %s\n' "$id" "$conclusion" >&2
        exit 1
      fi
    else
      pending=1
    fi
  done
  if [ "$pending" -eq 0 ]; then
    printf 'all runs succeeded: %s\n' "$*"
    exit 0
  fi
  sleep 15
done
