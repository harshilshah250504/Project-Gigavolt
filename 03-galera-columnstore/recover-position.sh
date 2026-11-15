#!/bin/bash
set -euo pipefail

fail() {
    echo "STOP: $*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || fail "Run with sudo."

exec 9>/run/lock/gigavolt-bootstrap.lock
flock -n 9 || fail "Another recovery/bootstrap script is running."

state=$(systemctl show mariadb -p ActiveState --value)
[[ "$state" == "inactive" || "$state" == "failed" ]] \
    || fail "Stop MariaDB before recovering its position."

if pgrep -x mariadbd >/dev/null || pgrep -x mysqld >/dev/null; then
    fail "A database process is still running."
fi

recovery_tool=$(command -v galera_recovery) \
    || fail "galera_recovery is not installed."

install -d -m 0700 /var/log/gigavolt
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log="/var/log/gigavolt/recovered-position-$stamp.log"

if [[ -f /var/lib/mysql/grastate.dat ]]; then
    cp -p /var/lib/mysql/grastate.dat \
        "/var/log/gigavolt/grastate-before-recovery-$stamp.dat"
fi

echo "Recovering position on $(hostname)."
echo "This may perform local storage-engine crash recovery."

if ! "$recovery_tool" >"$log" 2>&1; then
    cat "$log"
    fail "Recovery failed; inspect the log before proceeding."
fi

cat "$log"
echo
echo "Saved recovery output: $log"
echo "Compare recovered UUID:seqno positions from ALL THREE nodes."
echo "No cluster has been bootstrapped by this script."
