import os
from synthesis_records import synthesize
import json
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import pymysql
from pymongo import MongoClient

ROOT = Path(__file__).resolve().parents[1] / "gigavolt-m5"
M4 = Path(__file__).resolve().parents[1] / "Gigavolt_M4_Existing_Instance"
VECTOR_TABLE = os.environ.get("GIGAVOLT_VECTOR_TABLE", "gigavolt_m4.c_fb5e4d6b5279_m16")
if not re.fullmatch(r"[A-Za-z0-9_]+\.[A-Za-z0-9_]+", VECTOR_TABLE):
    raise ValueError("GIGAVOLT_VECTOR_TABLE must be schema.table")
sys.path.insert(0, str(M4 / "src"))
import pipeline

def sql_rows(query):
    result = subprocess.run(
        ["sudo", "mariadb", "--batch", "--raw",
         "--skip-column-names", "gigavolt", "-e", query],
        capture_output=True, text=True, check=True
    )
    return [json.loads(line) for line in result.stdout.splitlines()
            if line.strip()]

def literal(value):
    return "CONVERT(0x" + value.encode().hex() + " USING utf8mb4)"

print("Loading the existing embedding model once...")
model = pipeline.model(M4 / "runs/run01")
mongo = MongoClient(
    os.environ.get("GIGAVOLT_MONGO_URI", "mongodb://127.0.0.1:27017"),
    serverSelectionTimeoutMS=5000
)
mongo.admin.command("ping")
print("Ready. Enter a question, or type quit.")

def ask(question):
    started = time.perf_counter()
    timing = {}
    sources = {}
    candidates = []
    notes = []

    def add(label, kind, record, text):
        sources[label] = {"type": kind, "record": record}
        candidates.append({"source": label, "text": text})

    unit_match = re.search(
        r"\b(?:SN-[A-Z0-9]+(?:-[A-Z0-9]+)*|EQ-\d+)\b",
        question.upper()
    )
    unit = unit_match.group() if unit_match else None
    model_match = re.search(
        r"\b(?:X-\d+|C-1200|G-3500)\b", question.upper()
    )
    model_name = model_match.group() if model_match else None

    stage = time.perf_counter()
    if unit:
        condition = (
            f"(equipment_id={literal(unit)} "
            f"OR serial_number={literal(unit)})"
        )
    elif model_name:
        condition = f"model={literal(model_name)}"
    else:
        condition = "1=0"

    equipment = sql_rows(
        "SELECT JSON_OBJECT('equipment_id',equipment_id,"
        "'serial_number',serial_number,'model',model,"
        "'warranty_expiration',warranty_expiration,'status',status) "
        f"FROM silver_equipment WHERE {condition} "
        "ORDER BY equipment_id LIMIT 5"
    )
    if unit and not equipment:
        notes.append(
            f"No exact SQL equipment match for {unit}; "
            "its SQL service and warranty history is unavailable."
        )
    if not unit and not model_name:
        notes.append("SQL requires an equipment identifier or model.")
    for row in equipment:
        add("SQL-EQUIP-" + row["equipment_id"], "sql_equipment",
            row, json.dumps(row))

    # Unit-specific service and warranty records only for exact SQL matches.
    if unit:
        for equipment_row in equipment:
            eid = literal(equipment_row["equipment_id"])
            for table, id_field, date_field in [
                ("silver_dispatches", "dispatch_id", "dispatch_date"),
                ("silver_warranty_claims", "claim_id", "claim_date")
            ]:
                if table == "silver_dispatches":
                    fields = (
                        "'resolution_summary',resolution_summary,"
                        "'service_type',service_type,"
                    )
                else:
                    fields = "'claim_notes',claim_notes,"
                query = (
                    f"SELECT JSON_OBJECT('record_id',{id_field},"
                    "'equipment_id',equipment_id,"
                    f"'date',{date_field},{fields}'status',status) "
                    f"FROM {table} WHERE equipment_id={eid} "
                    f"ORDER BY {date_field} DESC,{id_field} LIMIT 2"
                )
                for row in sql_rows(query):
                    add(f"SQL-{table}-{row['record_id']}", table,
                        row, json.dumps(row))
    timing["sql_seconds"] = time.perf_counter() - stage

    stage = time.perf_counter()
    telemetry_unit = (
        equipment[0]["serial_number"]
        if unit and unit.startswith("EQ-") and len(equipment) == 1
        else unit
    )
    if telemetry_unit:
        logs = list(mongo.gigavolt_m5.telemetry.find(
            {
                "equipment_id": telemetry_unit,
                **({"fault_code": {"$exists": True, "$ne": None}}
                   if re.search(r"fault|error|failure", question, re.I)
                   else {})
            },
            {"_id": 0}
        ).sort("timestamp", -1).limit(3))
        for row in logs:
            add(row["log_id"], "mongodb", row, json.dumps(row))
        if not logs:
            notes.append("No telemetry found for the resolved unit.")
    timing["telemetry_seconds"] = time.perf_counter() - stage

    needs_documents = bool(re.search(
        r"document|firmware|guidance|manual|procedure|specification",
        question, re.I
    )) or not (unit or model_name)
    timing["vector_seconds"] = 0.0
    timing["embedding_seconds"] = 0.0
    if needs_documents:
        stage = time.perf_counter()
        vector = model.encode(
            question, normalize_embeddings=True
        ).astype("float32").tolist()
        timing["embedding_seconds"] = time.perf_counter() - stage

        stage = time.perf_counter()
        connection = pipeline.connect()
        try:
            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                cursor.execute("SET SESSION mhnsw_ef_search=640")
                cursor.execute(f"""
                    SELECT chunk_id,source_file,page_number,chunk_text,
                           metadata_json,
                           VEC_DISTANCE_COSINE(
                               embedding,VEC_FromText(%s)
                           ) AS distance
                    FROM {VECTOR_TABLE}
                    WHERE source_type='manual'
                    ORDER BY distance LIMIT 6
                """, (json.dumps(vector),))
                documents = cursor.fetchall()
        finally:
            connection.close()

        # Exclude manuals explicitly belonging to a different known model.
        inferred = model_name
        if not inferred and unit and unit.startswith("SN-X7-"):
            inferred = "X-7000"
        if not inferred and unit and unit.startswith("SN-C12-"):
            inferred = "C-1200"
        if not inferred and unit and unit.startswith("SN-G35-"):
            inferred = "G-3500"

        for row in documents:
            filename = row["source_file"]
            known_manual = next(
                (name for marker, name in [
                    ("GV-MAN-X7000", "X-7000"),
                    ("GV-MAN-C1200", "C-1200"),
                    ("GV-MAN-G3500", "G-3500")
                ] if marker in filename),
                None
            )
            if inferred and known_manual and known_manual != inferred:
                continue
            label = "DOC-" + row["chunk_id"]
            sources[label] = {"type": "vector_document", "record": row}
            passages = [
                text.strip() for text in
                re.split(r"(?<=[.!?])\s+|●", row["chunk_text"])
                if text.strip()
            ]
            for text in passages:
                candidates.append({"source": label, "text": text})
        timing["vector_seconds"] = time.perf_counter() - stage


    # Build small, source-specific groups so one source cannot crowd out another.
    lower = question.lower()
    groups = {}
    def group(name, items):
        if items:
            groups[name] = items[:3]
        else:
            notes.append(f"No retrieved evidence for requested section: {name}")

    sql_service = [
        c for c in candidates
        if sources[c["source"]]["type"] == "silver_dispatches"
    ]
    sql_claims = [
        c for c in candidates
        if sources[c["source"]]["type"] == "silver_warranty_claims"
    ]
    telemetry_items = [
        c for c in candidates
        if sources[c["source"]]["type"] == "mongodb"
    ]
    document_items = [
        c for c in candidates
        if sources[c["source"]]["type"] == "vector_document"
    ]

    wants_service = bool(re.search(r"service|history|dispatch", lower))
    wants_claims = bool(re.search(r"warranty|claim", lower))
    wants_faults = bool(re.search(r"fault|error|failure", lower))
    wants_documents = bool(re.search(
        r"document|firmware|guidance|manual|procedure|specification", lower
    ))

    if wants_service:
        group("SQL service example", sql_service)
    if wants_claims:
        group("SQL warranty claim example", sql_claims)

    if wants_faults:
        # Preserve separate coverage of the retrieved fault codes.
        codes = {}
        for item in telemetry_items:
            row = sources[item["source"]]["record"]
            code = row.get("fault_code")
            if code:
                codes.setdefault(code, []).append(item)
        for code, items in list(codes.items())[:3]:
            group("Observed " + code, items)
    elif telemetry_items and not (wants_service or wants_claims):
        group("Recent telemetry example", telemetry_items)

    if wants_documents:
        terms = set(re.findall(r"[a-z0-9_]+", lower))
        def relevance(item):
            text = item["text"].lower()
            overlap = len(terms & set(re.findall(r"[a-z0-9_]+", text)))
            firmware_bonus = (
                10 if "firmware" in lower
                and "firmware" in text
                and re.search(r"requirement|updated|version", text) else 0
            )
            return overlap + firmware_bonus
        document_items.sort(key=relevance, reverse=True)
        if "firmware" in lower and re.search(r"change|update|upgrade", lower):
            change_items = [
                item for item in document_items
                if "GV-ECO-" in sources[item["source"]]["record"]["source_file"]
                and "firmware" in item["text"].lower()
                and re.search(
                    r"requirement|updated|version",
                    item["text"], re.I
                )
            ]
            group("Documented firmware change", change_items)
        else:
            group("Related document statement", document_items)

    if not groups:
        group("Equipment evidence", [
            c for c in candidates
            if sources[c["source"]]["type"] == "sql_equipment"
        ])
        if not groups:
            group("Documentation evidence", document_items)

    if not groups:
        print("Insufficient evidence.")
        for note in notes:
            print("Scope:", note)
        return

    # Compact text is used only for selection; full records stay in the audit.
    # Long items are omitted from the prompt tail, not rewritten as quotations.
    pool = [item for items in groups.values() for item in items]
    choices = {
        name: {str(i): item["text"][:500] for i, item in enumerate(items)}
        for name, items in groups.items()
    }
    # SQL and telemetry are ordered by recency.
    # Document candidates are ranked by question relevance.
    selected = {name: 0 for name in groups}
    result = {
        "selection_method": "deterministic_ranked_first_candidate",
        "selected_indices": selected,
        "model_called_for_selection": False
    }
    timing["selection_seconds"] = 0.0
    answer = []
    for name, items in groups.items():
        index = selected[name]
        if type(index) is not int or not 0 <= index < len(items):
            raise ValueError("Invalid selection; answer withheld.")
        answer.append({**items[index], "section": name})
    generated, synthesis_seconds, generation_file = synthesize(
        question, answer, sources
    )
    timing["synthesis_seconds"] = synthesis_seconds
    total = time.perf_counter() - started
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    destination = ROOT / "results" / f"interactive_{stamp}.json"
    destination.write_text(json.dumps({
        "question": question, "answer": answer, "generated_answer": generated, "generation_file": generation_file,
        "source_map": sources, "candidate_pool": pool,
        "scope_notes": notes, "timings": timing,
        "total_seconds": total, "selection_result": result,
        "method": "Hybrid retrieval, deterministic ranked selection and record summaries, and source-isolated LLM document synthesis",
        "review_status": "Relevance and applicability require review"
    }, indent=2, default=str) + "\n")

    print("\nRETRIEVED EVIDENCE")
    if not answer:
        print("No relevant passage selected; insufficient evidence.")
    print("\nGENERATED ANSWER — factual review required")
    for sentence in generated:
        print(f"- {sentence['text']} [{sentence['source']}]")
    print("\nSupporting evidence:")
    for item in answer:
        source = sources[item["source"]]
        row = source["record"]
        locator = (
            f"{row['source_file']}, page {row['page_number']}"
            if source["type"] == "vector_document"
            else source["type"]
        )
        print(f"\n\"{item['text']}\"")
        print(f"[{item['source']}] {locator}")
    for note in notes:
        print("\nScope:", note)
    print("\nDocument findings do not establish a unit's diagnosis.")
    print(f"End-to-end: {total:.3f} seconds")
    print("Saved:", destination)

try:
    while True:
        question = input("\nQuestion> ").strip()
        if question.lower() in {"quit", "exit"}:
            break
        if not question:
            continue
        try:
            ask(question)
        except Exception as error:
            print(f"Request failed; no accepted answer: {type(error).__name__}: {error}")
finally:
    mongo.close()
