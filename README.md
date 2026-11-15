# Project Gigavolt

An AWS-based data lakehouse and retrieval-augmented generation (RAG) application for industrial battery support. A field engineer can ask about a unit's service history, recent telemetry, or a manual specification and trace the answer to the underlying record or passage.

**ISTM 622 semester project · Harshil Prashant Shah**

## What the system does

- **Ingests and validates data.** SQL transforms raw ERP records into normalized tables. Incremental loaders fingerprint service and telemetry inputs so unchanged files can be skipped.
- **Retrieves evidence across stores.** MariaDB serves relational records, MongoDB serves nested telemetry, and MariaDB Vector searches MiniLM document embeddings.
- **Returns traceable answers.** Structured routes render saved records directly. Ollama summarizes selected technical passages. Responses retain source identifiers for review.

![Architecture showing service and telemetry ingestion, hybrid retrieval, and cited answers](docs/architecture.png)

## Results at a glance

On the same 22-prompt EC2 workload, all-request P95 improved from **7.547 s to 4.976 s** and sequential throughput rose from **0.363 to 0.780 requests/s**. The six final answers that called Ollama had a **4.531 s end-to-end median**. The final citation audit resolved **25 of 25 emitted references** to saved evidence.

[See benchmark scope, measurements, and reproduction commands](#benchmark-and-provenance).

## Milestones

| Milestone | Implementation |
|---|---|
| 1 | [MariaDB lakehouse ingestion and data quality checks](01-lakehouse/load_and_validate.sql) |
| 2 | [Generated service context, RAG stored procedure, audit triggers and views](02-sql-automation/) |
| 3 | [Galera configuration, recovery scripts and InnoDB versus ColumnStore benchmark](03-galera-columnstore/) |
| 4 | [Document chunking, MiniLM embeddings and MariaDB Vector retrieval](Gigavolt_M4_Existing_Instance/) |
| 5 | [Hybrid SQL, MongoDB, vector and Ollama query application](gigavolt-m5/) |
| 6 | [Incremental loaders, verified lookup routes and benchmarks](gigavolt-m6/) |

## Verify locally

The chunking and cleaning tests run without access to the lab database or model servers.

```bash
python3 -m unittest discover -s Gigavolt_M4_Existing_Instance/src -p test_windows.py
```

## Lab setup

Use a disposable lab environment with MariaDB Vector, MongoDB, and a running Ollama service for the query application. The SQL tools use the local MariaDB client through sudo as in the original lab. Milestone 3 requires separate Galera nodes and a ColumnStore-enabled benchmark node. Its cluster configuration contains placeholders for the three addresses. Review the cluster scripts against the actual node state before using them.

1. Obtain the authorized ERP CSV inputs, technical manual archive, and telemetry dataset from their original source. Raw inputs, database dumps and local credentials are excluded. The two files under `gigavolt-m6/examples` are synthetic fixtures.
2. Create a fresh MariaDB schema named `gigavolt`. Use the Milestone 1 script with the five CSVs in MariaDB's configured import directory. The script contains table drops from the original lab workflow and is intended for a disposable schema. Apply the numbered Milestone 2 scripts in order in that schema.
3. Follow the [Milestone 4 runbook](Gigavolt_M4_Existing_Instance/README.md) for the database account and corpus setup. Use the checked-in folder as the project root. The hybrid application expects the Milestone 4 run artifacts at `Gigavolt_M4_Existing_Instance/runs/run01` and the local connection configuration at `Gigavolt_M4_Existing_Instance/config/db.json`.
4. Install the Python dependencies in a virtual environment. Copy `.env.example` to `.env`, set the MongoDB and Ollama endpoints if they run remotely, and set `GIGAVOLT_VECTOR_TABLE` to the schema-qualified M16 table listed in `runs/run01/tables.json`. Load `qwen2.5:1.5b` on the Ollama host.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
# Edit .env for your deployment, then load it.
source .env
```

5. Import approved telemetry as needed into `gigavolt_m5.telemetry` and create the unique `log_id` index. Check that `EQ-5002` exists in MariaDB before loading the service fixture, or set its equipment ID to a valid unit in your environment. Keep the fixed demo dispatch ID.

```bash
mongosh "$GIGAVOLT_MONGO_URI" --eval   'db.getSiblingDB("gigavolt_m5").telemetry.createIndex({log_id:1},{unique:true})'
mkdir -p gigavolt-m6/inbox gigavolt-m5/results gigavolt-m6/results
cp gigavolt-m6/examples/telemetry-demo.jsonl gigavolt-m6/examples/service-demo.json gigavolt-m6/inbox/
python gigavolt-m6/run_pipeline.py
python gigavolt-m6/run_pipeline.py
python gigavolt-m6/ask_m6.py "What is the latest telemetry status for SN-M6-0001?"
python gigavolt-m6/ask_m6.py "What does the G-3500 technical documentation say about voltage limits?"
```

The first run validates and loads the fixtures. A repeat uses the telemetry file fingerprint and verifies the service dispatch, payload, vector and audit counts. The voltage question requires the corresponding manual in the vector corpus.

## Benchmark and provenance

The original EC2 comparison used the same 22 sequential prompts in both runs. The final run returned 19 answers and three insufficient-evidence responses with zero execution errors.

| Measure | Baseline | Final |
|---|---:|---:|
| All-request P50 | 0.800 s | 0.058 s |
| All-request P95 | 7.547 s | 4.976 s |
| All-request P99 | 10.969 s | 5.564 s |
| Sequential throughput | 0.363 requests/s | 0.780 requests/s |

The six final Ollama-backed answers had an end-to-end median of **4.531 s**. The mixed workload contains direct lookups and model-backed requests. Timings exclude startup and warm-up. The [saved summary](docs/benchmark-summary.json) and [citation audit](docs/citation-audit.txt) contain the observed results. The audit resolved 25 of 25 emitted references to saved records, and separate relevance review found remaining answer-quality gaps.

To run the two benchmark modes against your prepared environment:

```bash
python -u gigavolt-m6/benchmark_m6.py baseline
python -u gigavolt-m6/benchmark_final80.py
```

The historical benchmarks include prompts targeting the original course data and synthetic recovery records. Fresh runs can differ with different inputs, models, or hardware. The public-ready source was syntax-checked and the Milestone 4 text tests were run locally. The database deployment and full benchmark were not rerun from this checkout.
