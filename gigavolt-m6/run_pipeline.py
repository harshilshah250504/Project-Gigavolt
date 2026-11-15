import subprocess
import sys
from pathlib import Path
from time import perf_counter

ROOT = Path(__file__).resolve().parent


def main():
    failed = []
    for name, script in (
        ("telemetry", "ingest_telemetry.py"),
        ("service_demo", "ingest_service_demo.py"),
    ):
        print(f"START stage={name}", flush=True)
        start = perf_counter()
        result = subprocess.run([sys.executable, str(ROOT / script)], cwd=ROOT)
        elapsed = perf_counter() - start
        print(f"END stage={name} status={result.returncode} seconds={elapsed:.3f}")
        if result.returncode:
            failed.append(name)

    if failed:
        print(f"PIPELINE FAILED stages={','.join(failed)}")
        return 1

    print("PIPELINE SUCCEEDED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
