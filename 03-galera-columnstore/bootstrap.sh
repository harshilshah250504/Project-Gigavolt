#!/bin/bash
set -euo pipefail

fail() {
    echo "STOP: $*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || fail "Run with sudo."
[[ $# -eq 2 ]] || fail "Usage: $0 REVIEWED_UUID REVIEWED_SEQNO"

expected_uuid=$1
expected_seqno=$2

# Prevent simultaneous execution of this script on this host.
exec 9>/run/lock/gigavolt-bootstrap.lock
flock -n 9 || fail "Another bootstrap script is running."

state=$(systemctl show mariadb -p ActiveState --value)
[[ "$state" == "inactive" || "$state" == "failed" ]] \
    || fail "MariaDB must be stopped."

if pgrep -x mariadbd >/dev/null || pgrep -x mysqld >/dev/null; then
    fail "A database process is still running."
fi

state_file=/var/lib/mysql/grastate.dat
[[ -s "$state_file" ]] || fail "Missing saved state."

uuid=$(awk '$1=="uuid:" {print $2}' "$state_file")
seqno=$(awk '$1=="seqno:" {print $2}' "$state_file")
safe=$(awk '$1=="safe_to_bootstrap:" {print $2}' "$state_file")

[[ "$uuid" == "$expected_uuid" ]] || fail "UUID differs from reviewed state."
[[ "$seqno" == "$expected_seqno" ]] || fail "Sequence differs from reviewed state."
[[ "$seqno" =~ ^[0-9]+$ ]] || fail "Crash-recovery inspection is required."
[[ "$safe" == "1" ]] || fail "Node is not marked safe to bootstrap."

echo "Selected host: $(hostname)"
echo "Saved position: $uuid:$seqno"
echo
echo "This script checks LOCAL state only."
echo "Proceed only after verifying ALL three database services are stopped,"
echo "comparing their states, and selecting this node for bootstrap."
read -r -p "Type ALL-NODES-STOPPED-STATE-REVIEWED: " confirmation
[[ "$confirmation" == "ALL-NODES-STOPPED-STATE-REVIEWED" ]] \
    || fail "Bootstrap cancelled."

install -d -m 0700 /var/log/gigavolt
stamp=$(date -u +%Y%m%dT%H%M%SZ)
cp -p "$state_file" "/var/log/gigavolt/grastate-before-$stamp.dat"

if ! galera_new_cluster; then
    journalctl -u mariadb -n 60 --no-pager
    fail "Bootstrap failed. Do not bootstrap another node blindly."
fi

mariadb -e "
SHOW GLOBAL STATUS WHERE Variable_name IN (
 'wsrep_cluster_size',
 'wsrep_cluster_status',
 'wsrep_local_state_comment',
 'wsrep_ready'
);"
