# Gigavolt lab setup and verification

[Project overview](../README.md)

## Lab setup

Use a disposable lab environment with MariaDB Vector, MongoDB, and a running Ollama service for the query application. The SQL tools use the local MariaDB client through sudo as in the original lab. Milestone 3 requires separate Galera nodes and a ColumnStore-enabled benchmark node. Its cluster configuration contains placeholders for the three addresses. Review the cluster scripts against the actual node state before using them.

1. Obtain the authorized ERP CSV inputs, technical manual archive, and telemetry dataset from their original source. Raw inputs, database dumps and local credentials are excluded. The two files under `gigavolt-m6/examples` are synthetic fixtures.
2. Create a fresh MariaDB schema named `gigavolt`. Use the Milestone 1 script with the five CSVs in MariaDB's configured import directory. The script contains table drops from the original lab workflow and is intended for a disposable schema. Apply the numbered Milestone 2 scripts in order in that schema.
3. Follow the [Milestone 4 runbook](../Gigavolt_M4_Existing_Instance/README.md) for the database account and corpus setup. Use the checked-in folder as the project root. The hybrid application expects the Milestone 4 run artifacts at `Gigavolt_M4_Existing_Instance/runs/run01` and the local connection configuration at `Gigavolt_M4_Existing_Instance/config/db.json`.
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

## Course inputs and validation

Use the instructor-provided files from the Advanced Data Management course. These are the raw input counts observed before MariaDB cleansing and deduplication.

| Input | Observed source count |
|---|---:|
| `customers.csv` | 525 records |
| `equipment.csv` | 2,575 records |
| `parts.csv` | 150 records |
| `dispatches.csv` | 5,000 records |
| `warranty_claims.csv` | 1,248 records |
| `UnstructuredData.zip` | 25 PDFs, 54 pages, 53 text-bearing pages |

The five CSVs had consistent field counts within each file. The Milestone 4 extractor processed the supplied archive and recorded the known blank page. These checks verify the source files and document extraction. Run the lab acceptance tasks after loading the data to verify the deployed database and application.

## Run and verify from VS Code

Open the project root in VS Code on the Linux machine hosting the lab, or use VS Code Remote SSH to open that folder on EC2. Create the repository-local `.venv`, load the course data, stage the two demo fixtures, and configure `.env` using the lab setup steps above. Use a dedicated lab and keep the fixed service demo dispatch ID. If the original lab already contains these records, keep the original staged fixture files. Changing the fixture under an existing log or dispatch ID creates a conflict by design.

Use **Tasks: Run Task** in the Command Palette and run these tasks in order.

| Task | What to look for |
|---|---|
| **Gigavolt: Check lab prerequisites** | MariaDB tables and an existing equipment reference, the indexed manual corpus, MongoDB telemetry with a unique log ID index, and a reachable Ollama model. |
| **Gigavolt: Run incremental pipeline** | Both stages succeed. On a repeat, the same inputs skip processing after the prior writes are verified. |
| **Gigavolt: Verify live answers** | The telemetry answer matches the stored MongoDB event and its citation. The service dispatch has a corresponding payload, vector chunk and audit entry. The G-3500 manual route returns its documented voltage range, and the X-7000 hybrid route returns a cited Ollama statement for review. |

The terminal equivalents, from the repository root, are:

```bash
source .env
.venv/bin/python gigavolt-m6/check_lab.py
.venv/bin/python -u gigavolt-m6/run_pipeline.py
.venv/bin/python -u gigavolt-m6/run_pipeline.py
.venv/bin/python gigavolt-m6/check_lab.py --answers
```

The acceptance check uses the original Gigavolt corpus for the manual and firmware questions. It checks exact results for the synthetic telemetry and G-3500 specification. The Ollama-backed check confirms the route executed and produced a citation. Its generated statement still needs human comparison with the cited passage.
