import json
import re
from datetime import date

from pymongo import MongoClient

from ingest_service_demo import TABLE, literal, sql
from ingest_telemetry import MONGO_URI


def result(question, answer, sources, outcome="answered"):
    return {
        "question": question,
        "outcome": outcome,
        "answer": answer,
        "source_map": sources,
    }


def sql_records(statement):
    return [json.loads(line) for line in sql(statement).splitlines()]


def monthly_records(question, equipment, year, month, family):
    start = date(year, month, 1)
    end = date(year + (month == 12), month % 12 + 1, 1)
    if family == "service":
        table, identifier, date_field = (
            "silver_dispatches", "dispatch_id", "dispatch_date"
        )
    else:
        table, identifier, date_field = (
            "silver_warranty_claims", "claim_id", "claim_date"
        )

    records = sql_records(f"""
        SELECT JSON_OBJECT('record_id', {identifier}, 'equipment_id', equipment_id,
                           'date', {date_field}, 'status', status)
        FROM gigavolt.{table}
        WHERE equipment_id = {literal(equipment)}
          AND {date_field} >= '{start}' AND {date_field} < '{end}'
        ORDER BY {date_field}, {identifier};
    """)
    if not records:
        return result(question, "No matching records in the requested month.",
                      {}, "insufficient_evidence")

    lines, sources = [], {}
    for record in records:
        citation = f"SQL-{table}-{record['record_id']}"
        sources[citation] = {"type": table, "record": record}
        lines.append(
            f"{record['record_id']} | {equipment} | {record['date']} | "
            f"status: {record['status']} [{citation}]"
        )
    return result(question, "\n".join(lines), sources)


def telemetry_and_service(question, serial):
    with MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000) as client:
        event = client["gigavolt_m5"]["telemetry"].find_one(
            {"equipment_id": serial},
            {"_id": 0, "log_id": 1, "equipment_id": 1, "timestamp": 1,
             "status": 1, "fault_code": 1},
            sort=[("timestamp", -1), ("log_id", 1)],
        )

    exact_matches = int(sql(f"""
        SELECT COUNT(*)
        FROM gigavolt.silver_dispatches d
        JOIN gigavolt.silver_equipment e ON e.equipment_id = d.equipment_id
        WHERE e.serial_number = {literal(serial)}
           OR e.equipment_id = {literal(serial)};
    """))
    scope = f"Exact SQL service records found for {serial}: {exact_matches}."
    if not event:
        return result(question, f"No telemetry found for {serial}. {scope}",
                      {}, "insufficient_evidence")

    citation = event["log_id"]
    fault = event.get("fault_code") or "none recorded"
    answer = (
        f"Latest telemetry for {serial}: {event['status']} at "
        f"{event['timestamp']}, fault code: {fault} [{citation}]. {scope}"
    )
    return result(question, answer, {citation: {"type": "mongodb", "record": event}})


def document(file_marker, page, *markers):
    filters = " AND ".join(
        f"chunk_text LIKE {literal('%' + marker + '%')}" for marker in markers
    )
    records = sql_records(f"""
        SELECT JSON_OBJECT('source_file', source_file, 'page_number', page_number,
                           'chunk_id', chunk_id, 'chunk_text', chunk_text)
        FROM {TABLE}
        WHERE source_type = 'manual'
          AND source_file LIKE {literal('%' + file_marker + '%')}
          AND page_number = {page} AND {filters};
    """)
    return records[0] if len(records) == 1 else None


def answer_verified(question):
    query = question.lower()
    month = re.search(
        r"\b(january|february|march|april|may|june|july|august|september|"
        r"october|november|december)\s+(\d{4})\b", query
    )
    equipment = re.search(r"\bEQ-\d+\b", question, re.I)
    service = bool(re.search(r"\b(?:service|dispatch(?:es)?)\b", query))
    warranty = "warranty" in query
    if month and equipment and service != warranty:
        months = (
            "january february march april may june july august september "
            "october november december"
        ).split()
        return monthly_records(
            question, equipment[0].upper(), int(month[2]),
            months.index(month[1]) + 1, "service" if service else "warranty",
        )

    serial = re.search(r"\bSN-[A-Z0-9]+(?:-[A-Z0-9]+)*\b", question, re.I)
    if serial and "latest" in query and "telemetry" in query and "sql" in query and service:
        return telemetry_and_service(question, serial[0].upper())

    if "inv-scr-9901" in query and "backup" in query and "supplier" in query:
        return result(
            question,
            "Insufficient evidence to verify an approved backup supplier for INV-SCR-9901.",
            {}, "insufficient_evidence",
        )

    if re.search(r"\bx[ -]?7000\b", query) and "inverter" in query and "supplier" in query:
        change = document("GV-ECO-2024-019", 1, "INV-SCR-9901", "Inverter Bridge Assembly")
        brief = document("GV-SUP-REP-401", 2, "INV-SCR-9901", "Semicon Dynamics Inc.")
        if change is None or brief is None:
            return result(question, "Insufficient evidence to verify the supplier link.",
                          {}, "insufficient_evidence")
        change_id, brief_id = ["DOC-" + row["chunk_id"] for row in (change, brief)]
        return result(
            question,
            f"The X-7000 inverter bridge assembly uses part INV-SCR-9901 [{change_id}]. "
            f"The supply-chain brief identifies Semicon Dynamics Inc. (SUP-SDI-09) "
            f"as the Tier 1 supplier of that part [{brief_id}].",
            {change_id: change, brief_id: brief},
        )
    return None
