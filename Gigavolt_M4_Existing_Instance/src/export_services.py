"""Run on an OLD Gigavolt database node. Writes JSONL to stdout; no DB changes."""
import json, subprocess, sys
sql="""SELECT JSON_OBJECT('record_id',payload_id,'dispatch_id',dispatch_id,
'equipment_id',equipment_id,'source_timestamp',created_at,'text',payload_text)
FROM gigavolt.rag_payloads ORDER BY payload_id"""
r=subprocess.run(['sudo','mariadb','--batch','--raw','--skip-column-names','-e',sql],capture_output=True,text=True,check=True)
for line in r.stdout.splitlines():
    row=json.loads(line)
    if not isinstance(row.get('text'),str) or not row['text'].strip():
        raise ValueError(f"Empty payload: {row.get('record_id')}")
    print(json.dumps(row,ensure_ascii=False))
print('Export complete',file=sys.stderr)
