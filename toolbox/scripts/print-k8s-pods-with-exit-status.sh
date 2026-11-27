#!/usr/bin/env bash
#
# print-k8s-pods-with-exit-status.sh
# https://github.com/half0wl/dotfiles
#
# Get the last state of k8s pods in a namespace with a specific prefix in the
# pod's name. Requires `kubectl` and `jq` to be installed.
#
# Usage:
#
#   ./print-k8s-pods-with-exit-status.sh <namespace> <pod-prefix>
#
# Example Output:
#
#   ./print-k8s-pods-with-exit-status.sh backboard backboard-yjs
#   pod-amn94jf91j-xn8fj
#   Exit Code: 139 / Uptime: 19m 11s
#
#   pod-8f4j9f8j4f-9fj4f
#   Exit Code: 0 / Uptime: 1h 5m 23s

if [ $# -ne 2 ]; then
  echo "Usage: $0 <namespace> <pod-prefix>"
  exit 1
fi

namespace="$1"
pod_prefix="$2"

kubectl get pods -n "$namespace" -o json |
  jq -r --arg prefix "$pod_prefix" '
    .items[] |
    select(.metadata.name | startswith($prefix)) |
    .status.containerStatuses[0].lastState.terminated as $term |
    "\(.metadata.name)\nExit Code: \($term.exitCode // "N/A") / Uptime: \(
      if $term.startedAt and $term.finishedAt then
        (($term.finishedAt | fromdateiso8601) - ($term.startedAt | fromdateiso8601)) as $seconds |
        (if ($seconds / 3600) >= 1 then "\(($seconds / 3600) | floor)h " else "" end) +
        (if (($seconds % 3600) / 60) >= 1 then "\((($seconds % 3600) / 60) | floor)m " else "" end) +
        "\($seconds % 60)s"
      else
        "N/A"
      end
    )\n"'
