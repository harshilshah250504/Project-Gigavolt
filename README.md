# Project Gigavolt

An AWS-based data lakehouse and retrieval-augmented generation (RAG) application for industrial battery support. A field engineer can ask about a unit's service history, recent telemetry, or a manual specification and trace the answer to the underlying record or passage.

**ISTM 622 semester project · Harshil Prashant Shah**

## What the system does

- **Ingests and validates data.** SQL transforms raw ERP records into normalized tables. The loaders use fingerprints to skip unchanged telemetry files and repeat runs of the service fixture.
- **Retrieves evidence across stores.** MariaDB serves relational records, MongoDB serves nested telemetry, and MariaDB Vector searches MiniLM document embeddings.
- **Returns traceable answers.** Structured routes render saved records directly. Ollama summarizes selected technical passages. Responses retain source identifiers for review.

![Architecture showing service and telemetry ingestion, hybrid retrieval, and cited answers](docs/architecture.png)

## Results at a glance

On the same 22-prompt EC2 workload, all-request P95 improved from **7.547 s to 4.976 s** and sequential throughput rose from **0.363 to 0.780 requests/s**. The six final answers that called Ollama had a **4.531 s end-to-end median**. The final citation audit resolved **25 of 25 emitted references** to saved evidence.

[See benchmark scope, measurements, and reproduction commands](#benchmark-and-provenance).

## Example answer

**Question:** What documented firmware upgrade addresses X-7000 inverter faults?

**Observed answer:** The inverter’s DSP firmware must be updated to **v2.4.11-b or later** to change the commutation dead-time from **2.2 µs to 2.8 µs**.

**Source:** Engineering change order `GV-ECO-2024-019`, page 1. The live response identifies the cited passage. I compared the firmware version and both timing values with that passage during the EC2 verification.

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

## Run the application

The full application uses a configured Linux or EC2 lab with MariaDB Vector, MongoDB, Ollama, and the instructor-supplied inputs. The [lab setup guide](docs/lab-setup.md) covers data preparation, environment variables, the VS Code tasks, and live acceptance checks. This repository includes synthetic test fixtures and saved results for reviewing the project without access to that environment.

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

The historical benchmarks include prompts targeting the original course data and synthetic recovery records. Fresh runs can differ with different inputs, models, or hardware.

## Live verification on EC2

On November 15, 2026, commit `cf680a2` passed the lab acceptance check in a separate checkout on the existing AWS deployment. The check used the deployed MariaDB Vector, MongoDB, Ollama model, and original lab inputs.

| Check | Verified result |
|---|---|
| Telemetry lookup | The live answer reported `STANDBY` and 31.0 °C, matching MongoDB record `TLM-M6-DEMO-001`. |
| Service ingestion evidence | The demo dispatch had one stored dispatch, one RAG payload, indexed vector content, and one insert audit entry. |
| G-3500 manual lookup | The answer returned 750 V nominal and a 620–860 V DC operating range, citing page 1 of the model manual. |
| X-7000 hybrid answer | The Ollama statement matched page 1 of engineering change order `GV-ECO-2024-019`: DSP firmware v2.4.11-b or later, with commutation dead-time changing from 2.2 to 2.8 µs. |

All six Milestone 4 text-processing tests also passed locally. The live acceptance check passed both from the EC2 command line and from **Gigavolt: Verify live answers** in VS Code over Remote SSH. The VS Code run loaded the repository-local environment settings and passed all four checks. The X-7000 passage comparison above was performed on the earlier command-line answer. A fresh infrastructure deployment and a new 22-prompt benchmark were outside this verification.
