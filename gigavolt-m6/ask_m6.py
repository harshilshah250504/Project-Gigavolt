import os
import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from ingest_service_demo import TABLE, literal, sql
from verified_routes import answer_verified

ROOT = Path(__file__).resolve().parent
M5 = Path(__file__).resolve().parents[1] / "gigavolt-m5" / "ask_gigavolt_v6.py"
M4 = Path(__file__).resolve().parents[1] / "Gigavolt_M4_Existing_Instance"

RULES = (
    (
        r"\bX[ -]?7000\b",
        r"\btemperatures?\b",
        "GV-MAN-X7000-",
        "maximum recorded cell temperature",
        "emergency shutdown",
        r"maximum recorded cell temperature[^?]{0,80}≥\s*(\d+(?:\.\d+)?)\s*°\s*C",
        "The manual specifies an emergency shutdown threshold of {0} °C "
        "or higher for the maximum recorded cell temperature. "
        "This passage gives a shutdown threshold. A full operating "
        "temperature range is unavailable from this passage.",
    ),
    (
        r"\bG[ -]?3500\b",
        r"\bvoltage\b",
        "GV-MAN-G3500-",
        "Bus Nominal Voltage",
        "Operating Range",
        r"Bus Nominal Voltage:\s*(\d+(?:\.\d+)?)\s*V\s*DC\s*"
        r"\(Operating Range:\s*(\d+(?:\.\d+)?)\s*V\s*[-–—]\s*"
        r"(\d+(?:\.\d+)?)\s*V\s*DC\)",
        "The nominal DC bus voltage is {0} V, with an operating range "
        "of {1}–{2} V DC.",
    ),
)


def answer_specification(question):
    verified = answer_verified(question)
    if verified is not None:
        return verified

    if not re.search(r"\b(limits?|thresholds?|range|nominal)\b", question, re.I):
        return None

    matches = [
        rule for rule in RULES
        if re.search(rule[0], question, re.I)
        and re.search(rule[1], question, re.I)
    ]
    if len(matches) != 1:
        return None

    _, _, manual, marker1, marker2, pattern, template = matches[0]
    raw = sql(f"""
        SELECT JSON_OBJECT(
            'source_file', source_file, 'page_number', page_number,
            'chunk_id', chunk_id, 'chunk_text', chunk_text
        )
        FROM {TABLE}
        WHERE source_type = 'manual'
          AND source_file LIKE {literal('%' + manual + '%')}
          AND chunk_text LIKE {literal('%' + marker1 + '%')}
          AND chunk_text LIKE {literal('%' + marker2 + '%')};
    """)
    rows = [json.loads(line) for line in raw.splitlines()]
    match = re.search(pattern, rows[0]["chunk_text"], re.I) if len(rows) == 1 else None
    if match is None:
        return {
            "question": question,
            "outcome": "insufficient_evidence",
            "answer": "Insufficient evidence to verify the requested specification.",
            "source_map": {},
        }

    record = rows[0]
    citation = "DOC-" + record["chunk_id"]
    return {
        "question": question,
        "outcome": "answered",
        "answer": f"{template.format(*match.groups())} [{citation}]",
        "source_map": {citation: record},
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("question", nargs="?")
    args = parser.parse_args()

    result = answer_specification(args.question) if args.question else None
    if result is None:
        command = [sys.executable, str(M5)]
        request = f"{args.question}\nquit\n" if args.question else None
        return subprocess.run(command, cwd=M4, text=True, input=request).returncode

    results = ROOT / "results"
    results.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = results / f"specification_{stamp}.json"
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")

    print(f"Question: {result['question']}")
    print(f"Answer: {result['answer']}")
    for citation, source in result["source_map"].items():
        record = source.get("record", source)
        if "source_file" in record:
            print(f"Source: {record['source_file']}, page {record['page_number']}")
        else:
            source_type = source.get("type", "record")
            record_id = record.get("log_id") or record.get("record_id") or citation
            print(f"Source: {source_type}, record {record_id}")
        print(f"Citation: {citation}")
    print(f"Saved: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
