#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo."
    exit 1
fi

echo "Node: $(hostname)"
echo "Time: $(date -u +%FT%TZ)"

service_state=$(systemctl show mariadb -p ActiveState --value)
echo "MariaDB service: $service_state"

if [[ "$service_state" != "inactive" && "$service_state" != "failed" ]]; then
    echo "STOP: MariaDB must be stopped before inspecting recovery state."
    exit 1
fi

if pgrep -x mariadbd >/dev/null || pgrep -x mysqld >/dev/null; then
    echo "STOP: A database process is still running."
    exit 1
fi

# Current installation uses the default data directory.
state_file=/var/lib/mysql/grastate.dat
if [[ ! -s "$state_file" ]]; then
    echo "STOP: Missing or empty $state_file"
    exit 1
fi

echo
cat "$state_file"
echo
echo "Inspection only: no files changed and no cluster started."
echo "Compare UUID, seqno, and safe_to_bootstrap across ALL three nodes."
