import os
import hashlib
import json
import logging
import re
import sqlite3
from datetime import datetime
from pathlib import Path

from pymongo import MongoClient

ROOT = Path(__file__).resolve().parent
MONGO_URI = os.environ.get("GIGAVOLT_MONGO_URI", "mongodb://127.0.0.1:27017")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("gigavolt-m6")


def read_events(raw):
    events = {}
    for number, line in enumerate(raw.decode("utf-8").splitlines(), 1):
        if not line.strip():
            continue

        event = json.loads(line)
        if not isinstance(event, dict) or "_id" in event:
            raise ValueError(f"Line {number}: expected an event object without _id")

        for field in ("log_id", "equipment_id", "timestamp", "model", "status"):
            if not isinstance(event.get(field), str) or not event[field].strip():
                raise ValueError(f"Line {number}: missing or invalid {field}")

        if not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z", event["timestamp"]
        ):
            raise ValueError(f"Line {number}: expected UTC timestamp with milliseconds")
        datetime.fromisoformat(event["timestamp"])

        if not isinstance(event.get("telemetry"), dict):
            raise ValueError(f"Line {number}: expected a telemetry object")
        if not isinstance(event.get("flagged_components"), list):
            raise ValueError(f"Line {number}: expected a flagged_components list")
        if event["log_id"] in events:
            raise ValueError(f"Line {number}: duplicate log_id {event['log_id']}")

        events[event["log_id"]] = event

    if not events:
        raise ValueError("File contains no events")
    return events


def main():
    failures = 0
    with sqlite3.connect(ROOT / "ingestion.sqlite3") as state, MongoClient(
        MONGO_URI, serverSelectionTimeoutMS=5000
    ) as client:
        state.execute(
            "CREATE TABLE IF NOT EXISTS processed "
            "(filename TEXT PRIMARY KEY, sha256 TEXT NOT NULL)"
        )
        collection = client["gigavolt_m5"]["telemetry"]

        for path in sorted((ROOT / "inbox").glob("telemetry-*.jsonl")):
            try:
                raw = path.read_bytes()
                digest = hashlib.sha256(raw).hexdigest()
                saved = state.execute(
                    "SELECT sha256 FROM processed WHERE filename = ?", (path.name,)
                ).fetchone()
                if saved == (digest,):
                    log.info("SKIPPED unchanged file=%s", path.name)
                    continue

                log.info("DETECTED file=%s sha256=%s", path.name, digest[:12])
                events = read_events(raw)
                log.info("VALIDATED file=%s records=%d", path.name, len(events))

                indexes = collection.index_information()
                if not any(
                    index.get("unique")
                    and not index.get("sparse")
                    and not index.get("partialFilterExpression")
                    and index["key"] == [("log_id", 1)]
                    for index in indexes.values()
                ):
                    raise RuntimeError("Expected existing unique MongoDB index on log_id")

                inserted = 0
                for log_id, event in events.items():
                    key = {"log_id": log_id}
                    result = collection.update_one(key, {"$setOnInsert": event}, upsert=True)
                    stored = collection.find_one(key, {"_id": 0})
                    if stored != event:
                        raise ValueError(f"Conflicting existing telemetry event: {log_id}")
                    inserted += result.upserted_id is not None

                with state:
                    state.execute(
                        "INSERT INTO processed (filename, sha256) VALUES (?, ?) "
                        "ON CONFLICT(filename) DO UPDATE SET sha256 = excluded.sha256",
                        (path.name, digest),
                    )
                log.info(
                    "COMPLETED file=%s inserted=%d verified=%d ids=%s",
                    path.name, inserted, len(events), ",".join(events)
                )
            except Exception:
                failures += 1
                log.exception("FAILED file=%s", path.name)

    return int(failures > 0)


if __name__ == "__main__":
    raise SystemExit(main())
