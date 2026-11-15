"""Check the configured lab and compare demo answers with their evidence."""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.request import urlopen

from pymongo import MongoClient
from pymongo.errors import PyMongoError

from ask_m6 import M4, M5, answer_specification
from ingest_service_demo import DISPATCH, TABLE, literal, sql
from ingest_telemetry import MONGO_URI

ROOT = Path(__file__).resolve().parent


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def check_databases():
    for path in (M4 / "config/db.json", M4 / "runs/run01/chunk_config.json"):
        require(path.is_file(), f"Required Milestone 4 file is missing: {path}")
    (ROOT / "inbox/telemetry-demo.jsonl").read_text()
    print("MariaDB version:", sql("SELECT VERSION();"), flush=True)
    for table in (
        "gigavolt.silver_equipment",
        "gigavolt.silver_dispatches",
        "gigavolt.silver_warranty_claims",
        "gigavolt.rag_payloads",
        "gigavolt.Audit_Logs",
        TABLE,
    ):
        sql(f"SELECT 1 FROM {table} LIMIT 0;")
    sample = json.loads((ROOT / "inbox/service-demo.json").read_text())
    unit = literal(sample["equipment_id"])
    require(sql(f"SELECT COUNT(*) FROM gigavolt.silver_equipment WHERE equipment_id={unit};") == "1",
            "Service fixture must name an existing equipment ID.")
    require(int(sql(f"SELECT COUNT(*) FROM {TABLE} WHERE source_type='manual';")) > 0,
            "The configured vector table has no manual chunks.")
    with MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000) as client:
        client.admin.command("ping")
        collection = client["gigavolt_m5"]["telemetry"]
        require(any(
            list(index["key"]) == [("log_id", 1)]
            and index.get("unique") and not index.get("sparse")
            and not index.get("partialFilterExpression")
            for index in collection.index_information().values()
        ), "MongoDB telemetry requires a full unique log_id index.")
    print("PASS: MariaDB tables, equipment reference, vector corpus, MongoDB unique index.")


def check_ollama():
    chat = os.environ.get("GIGAVOLT_OLLAMA_CHAT_URL", "http://127.0.0.1:11434/api/chat")
    require(chat.rstrip("/").endswith("/api/chat"), "Expected an Ollama /api/chat URL.")
    tags_url = chat.rstrip("/").removesuffix("/api/chat") + "/api/tags"
    with urlopen(tags_url, timeout=10) as response:
        models = json.load(response)["models"]
    require(any(model["name"] == "qwen2.5:1.5b" for model in models),
            "Ollama must have qwen2.5:1.5b installed.")
    print("PASS: Ollama is reachable and the configured model is available.")


def run_live_query(question):
    return subprocess.run(
        [sys.executable, str(M5)], cwd=M4, input=f"{question}\nquit\n",
        text=True, stdout=subprocess.PIPE, check=True, timeout=300,
    ).stdout


def check_answers():
    fixture = json.loads((ROOT / "inbox/telemetry-demo.jsonl").read_text())
    unit = fixture["equipment_id"]
    citation = fixture["log_id"]
    with MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000) as client:
        collection = client["gigavolt_m5"]["telemetry"]
        require(collection.count_documents({"log_id": citation}) == 1,
                "Expected exactly one copy of the demo event after the pipeline runs.")
        latest = collection.find_one(
            {"equipment_id": unit}, {"_id": 0}, sort=[("timestamp", -1)]
        )
    require(latest == fixture, "The staged demo event must be the latest record for its unit.")
    answer = run_live_query(f"What is the latest telemetry status and temperature for {unit}?")
    expected = (f"[{citation}]", f"status {latest['status']}",
                f"temperature {latest['telemetry']['temperature_c']} C")
    answer_lines = [line for line in answer.splitlines() if line.startswith("- Unit ")]
    require(any(all(value in line for value in expected) for line in answer_lines),
            "The live telemetry answer did not match the MongoDB event.")

    key = literal(DISPATCH)
    counts = sql(f"""
        SELECT (SELECT COUNT(*) FROM gigavolt.silver_dispatches WHERE dispatch_id={key}),
               (SELECT COUNT(*) FROM gigavolt.rag_payloads WHERE dispatch_id={key}),
               (SELECT COUNT(*) FROM {TABLE} WHERE source_file={literal(f'milestone6/{DISPATCH}')}),
               (SELECT COUNT(*) FROM gigavolt.Audit_Logs
                 WHERE record_id={key} AND table_name='silver_dispatches'
                   AND operation_type='INSERT');
    """).split()
    require(len(counts) == 4 and counts[:2] == ["1", "1"]
            and int(counts[2]) > 0 and counts[3] == "1",
            "Expected one dispatch, one payload, indexed chunks, and one insert audit.")
    spec = answer_specification("What does the G-3500 technical documentation say about voltage limits?")
    require(spec["outcome"] == "answered" and len(spec["source_map"]) == 1,
            "The verified specification route did not return a cited answer.")
    label, source = next(iter(spec["source_map"].items()))
    require(all(value in spec["answer"] for value in ("750 V", "620–860 V DC", f"[{label}]"))
            and "GV-MAN-G3500-" in source["source_file"]
            and int(source["page_number"]) == 1,
            "The specification answer or its citation did not match the verified manual.")
    print("PASS: live telemetry values and citation, service effects, and G-3500 manual citation.")

    answer = run_live_query("What documented firmware upgrade addresses X-7000 inverter faults?")
    generated = [line for line in answer.splitlines()
                 if line.startswith("- Document statement:") and "[DOC-" in line]
    require(generated, "The hybrid X-7000 query produced no cited Ollama document statement.")
    print("PASS: Ollama-backed hybrid query returned a cited document statement.")
    print("Review its factual support in the saved interactive audit.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--answers", action="store_true", help="Exercise the system after ingestion")
    args = parser.parse_args()
    try:
        check_databases()
        check_ollama()
        if args.answers:
            check_answers()
    except (OSError, ValueError, RuntimeError, PyMongoError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
