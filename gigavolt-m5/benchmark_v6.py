import os
import builtins
import contextlib
import io
import json
import runpy
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from pymongo import MongoClient

root = Path(__file__).resolve().parents[1] / "gigavolt-m5"

def query(sql):
    result = subprocess.run(
        ["sudo", "mariadb", "--batch", "--skip-column-names",
         "gigavolt", "-e", sql],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()

print("EQ-5001 record counts:")
counts = query("""
SELECT 'dispatches',COUNT(*) FROM silver_dispatches
WHERE equipment_id='EQ-5001'
UNION ALL
SELECT 'warranty_claims',COUNT(*) FROM silver_warranty_claims
WHERE equipment_id='EQ-5001';
""")
print(counts)

service_unit = query("""
SELECT d.equipment_id
FROM silver_dispatches d
JOIN silver_equipment e ON e.equipment_id=d.equipment_id
ORDER BY d.equipment_id LIMIT 1;
""")
if not service_unit:
    raise SystemExit("No SQL service unit found.")

# Initialize the application once, then call its request function.
original_input = builtins.input
startup = time.perf_counter()
try:
    builtins.input = lambda prompt="": "quit"
    namespace = runpy.run_path(str(root / "ask_gigavolt_v6.py"))
finally:
    builtins.input = original_input
startup_seconds = time.perf_counter() - startup

ask = namespace["ask"]
client = MongoClient(
    os.environ.get("GIGAVOLT_MONGO_URI", "mongodb://127.0.0.1:27017"),
    serverSelectionTimeoutMS=5000
)
ask.__globals__["mongo"] = client

questions = [
    ("fault_and_firmware",
     "What pre-charge and inverter faults were observed for "
     "SN-X7-0094, and what related firmware changes are documented?"),
    ("sql_service",
     f"Show service history for {service_unit}."),
    ("sql_claims",
     "Show warranty claims for EQ-5001."),
    ("telemetry",
     "What telemetry is available for SN-4829?"),
    ("documentation",
     "What documented firmware upgrade addresses X-7000 inverter faults?"),
    ("missing_unit",
     "Show service history and warranty claims for EQ-999999.")
]

rows = []
try:
    for repeat in range(1, 3):
        for name, question in questions:
            before = set((root / "results").glob("interactive_*.json"))
            captured = io.StringIO()
            started = time.perf_counter()
            error = None
            try:
                with contextlib.redirect_stdout(captured):
                    ask(question)
            except Exception as exc:
                error = f"{type(exc).__name__}: {exc}"
            elapsed = time.perf_counter() - started
            new_files = set((root / "results").glob("interactive_*.json")) - before
            evidence_path = max(new_files) if new_files else None
            evidence = (
                json.loads(evidence_path.read_text()) if evidence_path else {}
            )
            rows.append({
                "test": name, "repeat": repeat, "question": question,
                "wall_seconds": elapsed, "error": error,
                "evidence_file": str(evidence_path) if evidence_path else None,
                "answer_count": len(evidence.get("answer", [])),
                "stage_timings": evidence.get("timings", {}),
                "console_output": captured.getvalue(),
                "quality_review": "pending"
            })
            print(f"{name} repeat {repeat}: {elapsed:.3f}s"
                  + (f" ERROR: {error}" if error else ""))
            print(captured.getvalue())
finally:
    client.close()

def percentile(values, p):
    values = sorted(values)
    position = (len(values)-1) * p
    lo = int(position)
    hi = min(lo+1, len(values)-1)
    return values[lo] + (values[hi]-values[lo]) * (position-lo)

# Keep failures in the saved record; summarize completed calls separately.
times = [row["wall_seconds"] for row in rows if row["error"] is None and row["answer_count"] > 0]
summary = {
    "requests": len(rows),
    "exceptions": sum(row["error"] is not None for row in rows),
    "startup_seconds": startup_seconds,
    "answered_requests": len(times),
    "completed_without_answer": sum(
        row["error"] is None and row["answer_count"] == 0
        for row in rows
    ),
    "answered_request_p50_seconds": percentile(times, .50) if times else None,
    "answered_request_p95_seconds": percentile(times, .95) if times else None,
    "answered_request_p99_seconds": percentile(times, .99) if times else None,
    "scope": (
        "Six distinct prompts repeated twice in one process. "
        "Startup excluded from request timings and reported separately. "
        "Repeated prompts may benefit from caching. "
        "Answered-request percentiles exclude missing-evidence responses. Timings include retrieval, rule-based selection, and LLM document synthesis when routed. SQL and telemetry use deterministic summaries; their routes do not call the LLM. Latency does not establish answer correctness; quality review pending. "
        "Tail percentiles from this small sample are preliminary."
    )
}
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
path = root / "results" / f"benchmark_v6_{stamp}.json"
path.write_text(json.dumps({
    "summary": summary, "eq5001_counts": counts,
    "service_test_unit": service_unit, "requests": rows
}, indent=2) + "\n")
print("\nSUMMARY:", json.dumps(summary, indent=2))
print("Saved:", path)
