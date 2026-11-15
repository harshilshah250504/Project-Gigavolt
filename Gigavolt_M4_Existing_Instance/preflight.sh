#!/usr/bin/env bash
# READ ONLY: no packages, service changes, or database writes.
set -euo pipefail
cat /etc/os-release
uname -m
python3 --version
free -h
df -h /
sudo mariadb --batch -e "SELECT VERSION(); SHOW VARIABLES LIKE 'wsrep_on'; SHOW VARIABLES LIKE 'mhnsw%'; SHOW DATABASES;"
M4_SERVER_VERSION=$(sudo mariadb --batch --skip-column-names -e 'SELECT VERSION();')
M4_WSREP=$(sudo mariadb --batch --skip-column-names -e "SHOW VARIABLES LIKE 'wsrep_on';")
M4_VECTOR=$(sudo mariadb --batch --skip-column-names -e "SHOW VARIABLES LIKE 'mhnsw_ef_search';")
export M4_SERVER_VERSION M4_WSREP M4_VECTOR
python3 - <<'PY'
import os,re,sys,platform,shutil
version=os.environ['M4_SERVER_VERSION']; m=re.match(r'(\d+)\.(\d+)',version)
errors=[]
if 'MariaDB' not in version or not m or tuple(map(int,m.groups())) < (11,8): errors.append('Needs review of MariaDB version; this kit targets MariaDB 11.8 or newer. No automatic upgrade.')
if not os.environ['M4_VECTOR'].strip():errors.append('Vector search variables missing.')
ws=os.environ['M4_WSREP'].split()
if ws and ws[-1].upper()!='OFF': errors.append('Galera enabled: review cluster implications before any vector writes.')
if not (3,10)<=sys.version_info[:2]<(3,14):errors.append('Python version needs dependency compatibility review.')
if platform.machine()!='x86_64':errors.append('Architecture differs from the CPU dependency plan; review before installing.')
mem=int(next(x.split()[1] for x in open('/proc/meminfo') if x.startswith('MemTotal:')))*1024
free=shutil.disk_usage(os.getcwd()).free
if mem<3*1024**3:errors.append('Less than 3 GiB physical RAM: review resizing this SAME instance before local embeddings.')
if free<8*1024**3:errors.append('Less than 8 GiB free disk: review storage on this SAME instance before dependencies.')
if errors:
 print('\nREVIEW REQUIRED — no changes made:')
 for e in errors:print('-',e)
 sys.exit(1)
print('\nPreflight passed. Review source schema and make a backup before creating M4 tables.')
PY
