import os
import re
import fcntl
import hashlib
import json
import subprocess
import sys
from datetime import date
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent
M4 = Path(__file__).resolve().parents[1] / "Gigavolt_M4_Existing_Instance"
sys.path.insert(0, str(M4 / "src"))
import pipeline

TABLE = os.environ.get("GIGAVOLT_VECTOR_TABLE", "gigavolt_m4.c_fb5e4d6b5279_m16")
if not re.fullmatch(r"[A-Za-z0-9_]+\.[A-Za-z0-9_]+", TABLE):
    raise ValueError("GIGAVOLT_VECTOR_TABLE must be schema.table")
DISPATCH = "DISP-M6-DEMO-001"
REVISION = "1110a243fdf4706b3f48f1d95db1a4f5529b4d41"


def sql(statement):
    return subprocess.run(
        ["sudo", "mariadb", "--batch", "--skip-column-names"],
        input=statement,
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()


def literal(value):
    return "CONVERT(UNHEX('" + value.encode("utf-8").hex() + "') USING utf8mb4)"


def run():
    path = ROOT / "inbox" / "service-demo.json"
    raw = path.read_bytes()
    event = json.loads(raw)
    digest = hashlib.sha256(raw).hexdigest()
    dispatch = literal(DISPATCH)
    source_name = f"milestone6/{DISPATCH}"
    source = literal(source_name)

    if event["dispatch_id"] != DISPATCH or event["service_type"] != "Synthetic Test":
        raise ValueError("Expected the staged Milestone 6 synthetic dispatch")
    if event["hours_spent"] != 0 or event["labor_cost"] != 0:
        raise ValueError("The synthetic dispatch must have zero hours and cost")

    equipment = event["equipment_id"].strip()
    service_date = date.fromisoformat(event["dispatch_date"]).isoformat()
    technician = pipeline.clean(event["technician"])
    summary = pipeline.clean(event["resolution_summary"])
    status = event["status"].strip()
    if not equipment or not technician or not summary or status != "completed":
        raise ValueError("Invalid synthetic dispatch fields")

    counts_sql = f"""
    SELECT
      (SELECT COUNT(*) FROM gigavolt.silver_dispatches WHERE dispatch_id={dispatch}),
      (SELECT COUNT(*) FROM gigavolt.rag_payloads WHERE dispatch_id={dispatch}),
      (SELECT COUNT(*) FROM {TABLE} WHERE source_file={source}),
      (SELECT COUNT(*) FROM {TABLE} WHERE source_file={source}
       AND JSON_UNQUOTE(JSON_EXTRACT(metadata_json, '$.input_sha256'))={literal(digest)}),
      (SELECT COUNT(*) FROM gigavolt.Audit_Logs
       WHERE table_name='silver_dispatches' AND operation_type='INSERT'
       AND record_id={dispatch});
    """
    existing = tuple(map(int, sql(counts_sql).split()))
    dispatches, payloads, chunks, matching_chunks, audits = existing
    if dispatches == payloads == audits == 1 and chunks == matching_chunks > 0:
        print(f"SKIPPED unchanged file={path.name} dispatch={DISPATCH}")
        return
    if any(existing):
        raise RuntimeError(f"Existing rows need review before loading: {existing}")

    print(f"DETECTED file={path.name} sha256={digest[:12]}", flush=True)
    equipment_ref = sql(f"""
        SELECT COUNT(*) FROM gigavolt.silver_equipment e
        JOIN gigavolt.silver_customers c ON c.customer_id=e.customer_id
        WHERE e.equipment_id={literal(equipment)};
    """)
    if equipment_ref != "1":
        raise ValueError("Expected one matching equipment and customer reference")
    print(f"VALIDATED dispatch={DISPATCH} equipment={equipment}", flush=True)

    import numpy as np
    import spacy

    context = (
        f"Dispatch ID: {DISPATCH} | Equipment ID: {equipment} | "
        f"Service Date: {service_date} | Technician: {technician} | "
        f"Service Type: Synthetic Test | Resolution: {summary} | Status: {status}"
    )
    config = {"revision": REVISION, "target": 220, "overlap": 40}
    with TemporaryDirectory() as temporary:
        run_dir = Path(temporary)
        (run_dir / "chunk_config.json").write_text(json.dumps(config))
        model = pipeline.model(run_dir)
        nlp = spacy.blank("en")
        nlp.add_pipe("sentencizer")
        windows, _ = pipeline.windows(
            context, model.tokenizer, nlp, config["target"], config["overlap"]
        )
        if not windows:
            raise ValueError("Chunker returned no service text")
        vectors = model.encode(
            [window["text"] for window in windows],
            normalize_embeddings=True,
        )
    if vectors.shape != (len(windows), 384) or not np.isfinite(vectors).all():
        raise ValueError("Invalid embeddings")
    if not np.allclose(np.linalg.norm(vectors, axis=1), 1, atol=1e-4):
        raise ValueError("Expected normalized embeddings")

    statements = [f"""
        START TRANSACTION;
        INSERT INTO gigavolt.silver_dispatches
          (dispatch_id, equipment_id, dispatch_date, technician, service_type,
           hours_spent, labor_cost, resolution_summary, status)
        VALUES ({dispatch}, {literal(equipment)}, {literal(service_date)},
                {literal(technician)}, 'Synthetic Test', 0, 0,
                {literal(summary)}, {literal(status)});

        INSERT INTO gigavolt.rag_payloads
          (dispatch_id, equipment_id, customer_id, payload_text)
        SELECT d.dispatch_id, d.equipment_id, e.customer_id, d.full_service_context
        FROM gigavolt.silver_dispatches d
        JOIN gigavolt.silver_equipment e ON e.equipment_id=d.equipment_id
        WHERE d.dispatch_id={dispatch};
        SET @m6_payload_id = LAST_INSERT_ID();
    """]

    for index, (window, vector) in enumerate(zip(windows, vectors, strict=True)):
        chunk_id = hashlib.sha256(f"{DISPATCH}:{digest}:{index}".encode()).hexdigest()
        metadata = json.dumps({
            "dispatch_id": DISPATCH,
            "equipment_id": equipment,
            "input_sha256": digest,
            "model": pipeline.MODEL,
            **config,
        })
        vector_text = literal(json.dumps(vector.tolist()))
        statements.append(f"""
            INSERT INTO {TABLE}
              (chunk_id, source_file, source_type, page_number, chunk_index,
               token_count, chunk_text, metadata_json, embedding)
            VALUES ('{chunk_id}', {source}, 'service_record', 0, {index},
                    {int(window['token_count'])}, {literal(window['text'])},
                    JSON_SET({literal(metadata)}, '$.payload_id', @m6_payload_id),
                    VEC_FromText({vector_text}));
        """)

    sql("\n".join(statements) + "\nCOMMIT;")
    actual = tuple(map(int, sql(counts_sql).split()))
    expected = (1, 1, len(windows), len(windows), 1)
    if actual != expected:
        raise RuntimeError(f"Verification after commit: expected {expected}, got {actual}")
    print(
        f"COMPLETED dispatch={DISPATCH} sql_rows=1 rag_payloads=1 "
        f"vector_chunks={len(windows)} audit_inserts=1"
    )


if __name__ == "__main__":
    with (ROOT / ".service-demo.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            run()
        except subprocess.CalledProcessError as error:
            raise SystemExit(error.stderr.strip() or str(error)) from error
