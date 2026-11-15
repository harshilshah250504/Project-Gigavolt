#!/usr/bin/env bash
# Creates a new dedicated local account; refuses to overwrite credentials.
set -euo pipefail
cd "$(dirname "$0")"
[[ ! -e config/db.json ]] || { echo 'config/db.json already exists; not replacing it.'; exit 1; }
bash preflight.sh
python3 - <<'PY'
import json,secrets,subprocess,os
password=secrets.token_hex(24)
sql=f"""CREATE DATABASE gigavolt_m4 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'gigavolt_m4'@'127.0.0.1' IDENTIFIED BY '{password}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX ON gigavolt_m4.* TO 'gigavolt_m4'@'127.0.0.1';"""
subprocess.run(['sudo','mariadb'],input=sql,text=True,check=True)
fd=os.open('config/db.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:
 json.dump(dict(host='127.0.0.1',port=3306,user='gigavolt_m4',password=password,database='gigavolt_m4'),f)
print('Created local account and private config/db.json. Do not include this file in submissions.')
PY
