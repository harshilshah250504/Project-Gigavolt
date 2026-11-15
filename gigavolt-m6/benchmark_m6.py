import contextlib
import io
import json
import runpy
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter
from unittest.mock import patch

from pymongo import MongoClient
from ingest_telemetry import MONGO_URI

M5 = Path(__file__).resolve().parents[1] / "gigavolt-m5"
sys.path.insert(0, str(M5))
AUDITS = M5 / "results"
RESULTS = Path(__file__).resolve().parent / "results"

CASES = [
    ("cross_source", "What pre-charge and inverter faults were observed for SN-X7-0094, and what related firmware changes are documented?"),
    ("cross_source", "For SN-X7-0094, show the latest fault telemetry and cite the documented inverter DSP firmware requirement."),
    ("cross_source", "For EQ-5002, show the latest service history and related equipment documentation."),
    ("cross_source", "Show warranty claims for EQ-5001 and explain whether telemetry is available for the same equipment."),
    ("cross_source", "For SN-4829, show the latest telemetry and whether there is a matching SQL service record."),
    ("cross_source", "For EQ-5002, show service history and warranty claims as separate evidence."),
    ("temporal", "What is the latest telemetry status and temperature for SN-M6-0001?"),
    ("temporal", "When was the latest telemetry recorded for SN-M6-0002, and what was its status?"),
    ("temporal", "What fault events were recorded for SN-X7-0094 on September 28, 2024?"),
    ("temporal", "What service dispatches were recorded for EQ-5002 during May 2023?"),
    ("temporal", "Show the latest service dispatch for EQ-5002 and its completion status."),
    ("temporal", "Which warranty claims for EQ-5001 were recorded in April 2024?"),
    ("technical", "What documented firmware upgrade addresses X-7000 inverter faults?"),
    ("technical", "What does X-7000 documentation say about commutation dead-time before and after the firmware update?"),
    ("technical", "What does the X-7000 documentation say about battery management system architecture?"),
    ("technical", "What temperature limits does the X-7000 technical documentation specify?"),
    ("technical", "What does the G-3500 technical documentation say about voltage limits?"),
    ("technical", "What safety procedures does C-1200 documentation describe for servicing the unit?"),
    ("technical", "Which approved backup supplier is documented for part INV-SCR-9901?"),
    ("technical", "Which supplier dependencies are documented for the X-7000 inverter assembly?"),
    ("missing_evidence", "Show service history and warranty claims for EQ-999999."),
    ("missing_evidence", "What is the latest telemetry status for SN-M6-9999?"),
]


def run_request(ask, group, question):
    # Milestone 6 final query route
    if label == "final80":
        from ask_m6 import answer_specification

        started = perf_counter()
        result = None
        error = None
        try:
            result = answer_specification(question)
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"
        elapsed = perf_counter() - started
        if result is not None or error is not None:
            audit = result or {}
            audit["timings"] = {"specification_lookup_seconds": elapsed}
            return {
                "group": group,
                "question": question,
                "seconds": elapsed,
                "outcome": "error" if error else result["outcome"],
                "error": error,
                "audit_path": None,
                "audit": audit,
                "console": audit.get("answer", ""),
            }

    before = set(AUDITS.glob("interactive_*.json"))
    output = io.StringIO()
    error = None
    started = perf_counter()
    try:
        with contextlib.redirect_stdout(output):
            ask(question)
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
    elapsed = perf_counter() - started

    new_paths = set(AUDITS.glob("interactive_*.json")) - before
    audit_path = next(iter(new_paths)) if len(new_paths) == 1 else None
    audit = json.loads(audit_path.read_text()) if audit_path else {}
    if len(new_paths) > 1 or (audit and audit.get("question") != question):
        error = error or "Could not uniquely match the request to its audit JSON"
    if error:
        outcome = "error"
    elif audit.get("answer"):
        outcome = "answered"
    elif "Insufficient evidence." in output.getvalue():
        outcome = "insufficient_evidence"
    else:
        outcome = "unclassified"

    return {
        "group": group,
        "question": question,
        "seconds": elapsed,
        "outcome": outcome,
        "error": error,
        "audit_path": str(audit_path) if audit_path else None,
        "audit": audit,
        "console": output.getvalue(),
    }


def stats(values):
    values = sorted(values)
    result = {"n": len(values)}
    for label, percent in (("p50", .50), ("p95", .95), ("p99", .99)):
        if not values:
            result[label] = None
            continue
        position = (len(values) - 1) * percent
        lower = int(position)
        upper = min(lower + 1, len(values) - 1)
        value = values[lower] + (values[upper] - values[lower]) * (position - lower)
        result[label] = round(value, 6)
    return result


label = sys.argv[1]
RESULTS.mkdir(exist_ok=True)
started = perf_counter()
with patch("builtins.input", return_value="quit"):
    ask = runpy.run_path(str(M5 / "ask_gigavolt_v6.py"))["ask"]
startup = perf_counter() - started

rows = []
with MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000) as client:
    ask.__globals__["mongo"] = client
    warmup = run_request(ask, "warmup", "What documented X-7000 firmware changes address inverter faults?")
    print(f"Warm-up: {warmup['outcome']} in {warmup['seconds']:.3f}s", flush=True)

    for number, (group, question) in enumerate(CASES, 1):
        row = run_request(ask, group, question)
        rows.append(row)
        print(f"{number:02d}/{len(CASES)} {group} {row['outcome']} "
              f"{row['seconds']:.3f}s", flush=True)

answers = [row for row in rows if row["outcome"] == "answered"]
def has_model_response(row):
    filename = row["audit"].get("generation_file")
    if not filename:
        return False
    generation = json.loads(Path(filename).read_text())
    return any(
        isinstance(entry.get("result"), dict) and "eval_count" in entry["result"]
        for entry in generation["audits"]
    )


document = [row for row in answers if has_model_response(row)]
direct = [row for row in answers if row not in document]
stages = defaultdict(list)
for row in answers:
    for name, value in row["audit"].get("timings", {}).items():
        if isinstance(value, (int, float)) and value > 0:
            stages[name].append(value)

summary = {
    "requests": len(rows),
    "answered": len(answers),
    "insufficient_evidence": sum(r["outcome"] == "insufficient_evidence" for r in rows),
    "errors_or_unclassified": sum(r["outcome"] in {"error", "unclassified"} for r in rows),
    "startup_seconds": round(startup, 6),
    "attempted_requests_per_second": round(len(rows) / sum(r["seconds"] for r in rows), 3),
    "all_attempts_seconds": stats([r["seconds"] for r in rows]),
    "answered_seconds": stats([r["seconds"] for r in answers]),
    "document_generation_route_seconds": stats([r["seconds"] for r in document]),
    "direct_answer_seconds": stats([r["seconds"] for r in direct]),
    "recorded_nonzero_stage_seconds": {name: stats(values) for name, values in stages.items()},
}
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
path = RESULTS / f"benchmark_{label}_{stamp}.json"
path.write_text(json.dumps({"summary": summary, "warmup": warmup, "requests": rows}, indent=2) + "\n")

print(f"\n{label.upper()} | {len(rows)} prompts | {len(answers)} answered | "
      f"{summary['insufficient_evidence']} insufficient | "
      f"{summary['errors_or_unclassified']} errors/unclassified")
print(f"Startup: {startup:.3f}s | Sequential throughput: "
      f"{summary['attempted_requests_per_second']} requests/s")
print("Timing group                     n       P50       P95       P99")
for name, values in [
    ("All requests", summary["all_attempts_seconds"]),
    ("Answered requests", summary["answered_seconds"]),
    ("Document generation route", summary["document_generation_route_seconds"]),
    ("Direct answers", summary["direct_answer_seconds"]),
    *summary["recorded_nonzero_stage_seconds"].items(),
]:
    columns = " ".join(
        f"{values[key]:9.3f}" if values[key] is not None else f"{'—':>9}"
        for key in ("p50", "p95", "p99")
    )
    print(f"{name:30} {values['n']:3} {columns}")
print(f"Saved: {path}")
