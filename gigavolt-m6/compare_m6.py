import json
import sys
from collections import Counter
from pathlib import Path
from statistics import median


def load(path):
    return json.loads(Path(path).read_text())["requests"]


def model_results(row):
    filename = row["audit"].get("generation_file")
    if not filename:
        return []
    generation = json.loads(Path(filename).read_text())
    return [
        entry["result"]
        for entry in generation["audits"]
        if isinstance(entry.get("result"), dict) and "eval_count" in entry["result"]
    ]


def report(label, rows):
    calls = [model_results(row) for row in rows]
    answered = [row for row in rows if row["outcome"] == "answered"]
    model_times = [
        row["seconds"] for row, results in zip(rows, calls)
        if results and row["outcome"] == "answered"
    ]
    direct_times = [
        row["seconds"] for row, results in zip(rows, calls)
        if not results and row["outcome"] == "answered"
    ]
    reasons = Counter(
        result.get("done_reason", "unknown")
        for results in calls for result in results
    )

    print(f"\n{label} | {len(rows)} prompts | {len(answered)} answered")
    for name, times in (
        ("Answered with recorded Ollama response", model_times),
        ("Answered without recorded Ollama response", direct_times),
    ):
        timing = f"{median(times):.3f}s" if times else "n/a"
        print(f"{name}: n={len(times)} | median={timing}")
    print(f"Ollama stop reasons: {dict(reasons)}")
    print(f"Sequential throughput: {len(rows) / sum(r['seconds'] for r in rows):.3f} requests/s")


baseline, tuned = map(load, sys.argv[1:])
if [r["question"] for r in baseline] != [r["question"] for r in tuned]:
    raise SystemExit("The prompt lists differ")

report("BASELINE", baseline)
report("TUNED 64", tuned)

print("\nPrompt-level changes for review")
for number, (before, after) in enumerate(zip(baseline, tuned), 1):
    if (
        before["outcome"] != after["outcome"]
        or before["audit"].get("answer") != after["audit"].get("answer")
    ):
        print(f"{number:02d} {before['outcome']} -> {after['outcome']} | {before['question']}")
