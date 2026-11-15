# Milestone 4 — continue on the existing Milestone 1 AND 2 instance

Use this revised package instead of the earlier new-instance package. It contains no MariaDB installer. It does not use the professor's setup script. Preserve existing databases, views, routines, triggers, accounts, and permissions. Create the separate `gigavolt_m4` database on the same server for the new work.

## 1. Start Learner Lab and identify the existing instance

Start AWS Academy Learner Lab, open its AWS Console, and start the instance containing Milestones 1 and 2. Do not launch a new instance. Record the instance ID and current public IP. Use the existing SSH access method and key. Screenshot S01: instance name/ID/state, instance type and Storage tab. Avoid including account details unnecessarily.

## 2. Read-only environment checks

On the existing instance:

```bash
cat /etc/os-release
uname -m
python3 --version
free -h
df -h /
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
sudo systemctl is-active mariadb
sudo mariadb -e "SELECT VERSION(); SHOW VARIABLES LIKE 'wsrep_on'; SHOW VARIABLES LIKE 'mhnsw%'; SHOW DATABASES;"
sudo mariadb -e "SHOW FULL TABLES FROM gigavolt; SHOW PROCEDURE STATUS WHERE Db='gigavolt'; SHOW FUNCTION STATUS WHERE Db='gigavolt'; SHOW TRIGGERS FROM gigavolt;"
```

Screenshot S02: versions, resources and vector settings. S03: existing M1/M2 objects. This is an inspection, not proof that all earlier stored procedures still behave correctly.

If the database is unavailable, Vector is absent, the instance is part of Galera, or resources are insufficient, pause for an environment-specific plan. Do not reinstall or bootstrap arbitrarily. This kit conservatively targets MariaDB 11.8+, x86_64, Python 3.10–3.13, about 4 GiB or more RAM, and at least 8 GiB free disk before dependency installation. These are planning checks, not universal software minimums. If necessary, adjust the SAME instance after backing up and confirming Learner Lab allowances.

## 3. Set up the project folder

Clone or copy the Project Gigavolt repository onto the lab instance. Run these commands from the repository root.

```bash
cd Gigavolt_M4_Existing_Instance
mkdir -p data logs runs backups evidence
set -o pipefail
bash preflight.sh 2>&1 | tee logs/preflight.log
```

The preflight checks the existing environment. Review its output before continuing.

## 4. Preserve prior work before new installations

For the known `gigavolt` source schema, during a quiet period with no schema changes:

```bash
umask 077
set -o pipefail
sudo mariadb-dump --single-transaction --quick --routines --events --triggers --hex-blob \
  --databases gigavolt | gzip > backups/gigavolt_before_m4.sql.gz.part && \
  mv backups/gigavolt_before_m4.sql.gz.part backups/gigavolt_before_m4.sql.gz
gzip -t backups/gigavolt_before_m4.sql.gz
sha256sum backups/gigavolt_before_m4.sql.gz
ls -lh backups/gigavolt_before_m4.sql.gz
```

This logical backup covers the named schema and its routines/events/triggers, not global accounts and grants. The M4 scripts do not change existing accounts. Before a server upgrade or system-level change, additionally capture a recoverable full-instance/EBS backup and preserve account definitions as appropriate. No generic upgrade is authorized by these commands. The single-transaction consistency guarantee applies to transactional tables; inspect engines before relying on it for other storage engines.

Screenshot S04: backup filename, size and checksum, never its raw data. Compression integrity is not a restore test. Download the backup to your laptop before proceeding using `scp` from the Mac shell.

## 5. Install only Python support, not MariaDB

After the preflight and backup checks pass:

```bash
sudo apt-get update
sudo apt-get install -y python3-venv python3-pip wget unzip
python3 -m venv .venv
source .venv/bin/activate
export TMPDIR=/var/tmp
python -m pip install --no-cache-dir --upgrade pip
python -m pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu
python -m pip install --no-cache-dir -r requirements.txt
python -m pip check
python -m pip freeze > logs/requirements-resolved.txt
python src/test_windows.py
bash create_account.sh
```

The account script repeats the read-only preflight and creates only a new database/account for M4. If `gigavolt_m4` or its account already exists, inspect it; do not drop it blindly. The private `config/db.json` must never appear in screenshots or submission code.

Screenshot S05: dependency check, six passing algorithm tests, and confirmation that the M4 database exists. These tests use a simple tokenizer, not a real embedding-model integration test.

## 6. Download the PDFs with wget

```bash
wget --tries=3 --timeout=30 -O data/UnstructuredData.zip.part \
  https://622.gomillion.org/data/UnstructuredData.zip && \
  mv data/UnstructuredData.zip.part data/UnstructuredData.zip
unzip -t data/UnstructuredData.zip
sha256sum data/UnstructuredData.zip
```

Screenshot S06: successful archive validation/checksum. The reviewed ZIP has 25 PDFs and 54 pages, one visually confirmed blank page. Its hash is `77f5aa14797985347e40d8db6977976af2785a97646891a792873bf1f8875ed3`. Do not assume this inventory applies to a changed ZIP. Keep the archive compressed.

## 7. Export the existing local service text

```bash
sudo mariadb -e "SHOW COLUMNS FROM gigavolt.rag_payloads; SELECT COUNT(*) AS service_records FROM gigavolt.rag_payloads;"
python3 src/export_services.py > data/services.jsonl.part && \
  mv data/services.jsonl.part data/services.jsonl
wc -l data/services.jsonl
sha256sum data/services.jsonl
```

This reads your local Milestone 2 text records; no cross-instance transfer is required. Screenshot S07: SQL count and export line count. If `rag_payloads` or its expected columns do not exist, stop for a source-schema adjustment instead of inventing records. The exporter uses payload_id, dispatch_id, equipment_id, created_at and payload_text based on the earlier schema you supplied.

The rest of this guide covers processing, measurement, notebook execution and submission.

## 8. Extract and clean — NEW instance

```bash
source .venv/bin/activate
python src/pipeline.py --run runs/run01 extract \
  --archive data/UnstructuredData.zip --services data/services.jsonl \
  2>&1 | tee logs/01-extract.log
```

Read `runs/run01/inventory.json`. Expect 25 PDFs, 54 pages, one documented blank page, and the actual service count. `documents.jsonl` contains one text unit per nonblank page or service record.

Cleaning normalizes Unicode and repeated whitespace while preserving fault codes, numbers, and units. It does not remove stopwords or punctuation because those can carry technical meaning. PDF tables and layouts may not extract perfectly. Open three originals—a manual, an incident report, and a specification—and compare the extracted text before continuing. An empty unrecognized page requires OCR or manual review; this pipeline intentionally stops rather than embedding empty content.

```bash
python - <<'PY'
import json
from pathlib import Path
for line in Path('runs/run01/documents.jsonl').read_text().splitlines()[:3]:
 r=json.loads(line); print('\n',r['source_file'],'page',r['page_number']);print(r['text'])
PY
```

## 9. Create overlapping chunks

```bash
python src/pipeline.py --run runs/run01 chunk --target 220 --overlap 40 \
  2>&1 | tee logs/02-chunk.log
```

A token is a small text piece used by the model. The target is a maximum of 220 content tokens, leaving room for special tokens within this model's 256-token input limit. Although the assignment gives 256–512 as an example, using that size with this model would risk truncating text. The model choice determines the safe size.

The splitter groups complete sentences where possible and carries up to 40 trailing tokens' worth of whole sentences into the next chunk. Actual overlap can be smaller when a sentence is too long. A long sentence uses token-sized pieces so no window exceeds the limit. Each window advances; it cannot loop forever. Pages and service records remain separate, retaining precise source locations. Context spanning two PDF pages is a known limitation.

Inspect `chunk_report.json` and three printed examples. `chunks.jsonl` records text, page, character offsets, chunk index, token count, source ID, timestamps, and checksums. The model revision is saved in `chunk_config.json`, so embedding and query stages use the same revision.

## 10. Generate embeddings

```bash
python src/pipeline.py --run runs/run01 embed --batch 8 \
  2>&1 | tee logs/03-embed.log
```

The CPU model is `sentence-transformers/all-MiniLM-L6-v2`: a compact English semantic-search baseline that outputs 384 numbers per chunk. It is not specially trained on Gigavolt terminology, so inspect retrieved passages. The first execution downloads the model. Later executions reuse the local model cache.

Vectors are normalized to length one. This makes cosine similarity suitable for comparing direction rather than text length. The script checks the vector count, dimension, finite values, and normalization, then saves `embeddings.npy` and its report. It does not upload document content to a hosted embedding API.

If memory is insufficient, run the same stage with `--batch 2` only if no completed `embeddings.npy` exists. A completed stage refuses overwrite. Large improvements in speed are not guaranteed by increasing batch size on a small CPU instance.

## 11. Create and load the vector tables

```bash
python src/pipeline.py --run runs/run01 load 2>&1 | tee logs/04-load.log
cat runs/run01/tables.json
cat runs/run01/schema_m8.sql
```

Three tables contain identical vectors and metadata, but use index connectivity `M=6`, `M=8`, and `M=16`. This is an experiment, not three different datasets. The complete SQL definitions are generated into `schema_m6.sql`, `schema_m8.sql`, and `schema_m16.sql`.

`VECTOR(384)` stores the embeddings. `VECTOR INDEX ... DISTANCE=cosine` enables approximate nearest-neighbor search: it visits promising candidates rather than comparing every row. Larger M may improve recall but adds index work and storage. The script inserts in batches of 64, commits completed batches, and verifies row counts and stored chunk IDs against the source file. `builds.json` measures combined insertion and index-maintenance time, not isolated index construction.

Metadata includes source document or service record, page, chunk index, ingestion time, original timestamp when available, model revision, and content hashes. A document's ingestion time is not presented as its publication date.

Do not rerun a partially completed load over existing tables. It deliberately refuses duplicate table creation. Diagnose the error, then use a new run directory for a clean rebuild or remove only confirmed failed project tables after inspecting their names. Never drop the original `gigavolt` database.

## 12. Benchmark and select index settings

Review `config/questions.json` **before** benchmarking. There are 20 tuning questions and 10 held-out test questions. Source hints help manual checking; they are not ground-truth answer labels. The service questions are broad because your current service export was not provided for inspection. You may replace them with realistic technician questions before freezing the evaluation set.

```bash
python src/pipeline.py --run runs/run01 benchmark --split tune --repeats 20 \
  2>&1 | tee logs/05-tuning.log
```

This tests all 12 combinations of M (6, 8, 16) and `mhnsw_ef_search` (10, 20, 40, 80). Search effort controls how many candidates the index explores. Each configuration gets one warm-up per question, then 400 measured requests. Configuration order and question order are shuffled reproducibly. This is a single-client, warm-cache experiment—not a concurrent load test.

For each query, an exhaustive NumPy comparison over all stored vectors provides the exact top five. Recall@5 is the fraction of those five found by the index. Strict recall uses exact chunk IDs; a separate tie-aware value reports equal-distance alternatives within tolerance. Duplicate or nearly identical passages can create ties, so preserve both metrics. This measures index agreement, not whether a passage answers the question correctly.

The timer measures `execute` plus fetching all five passage texts and metadata over an already-open local database connection. It excludes model loading, question embedding, and terminal printing. Query result caching is disabled in the search SQL. It does not flush the operating system or InnoDB cache.

P50 is the median; P95 and P99 describe slower requests. A configuration is eligible only if strict mean recall@5 is greater than 0.90 and P50 is below 20 ms. The fastest eligible tuning configuration is saved in `selection.json`. No passing configuration means no automatic selection and no claim of success.

```bash
cat runs/run01/selection.json
python src/pipeline.py --run runs/run01 benchmark --split test --repeats 20 \
  2>&1 | tee logs/06-held-out.log
```

The held-out test uses only the selected configuration, with 200 requests. **Its result is the final reported performance**, even if it fails the target. Do not keep trying settings against these ten questions and still call them held out. A revised experiment needs a fresh, independently prepared test set.

Evidence includes raw request timings, summaries, query vectors, exact neighbor IDs, server version/settings, and `EXPLAIN` plans. The script stops if the plan does not select `vec_idx`. Inspect that failure rather than calling a full scan an indexed benchmark. On a database error, it writes failure details and partial request records.

MariaDB documents M and `mhnsw_ef_search`, but no separately exposed `ef_construction` setting. The rubric names that setting for generic HNSW. State this limitation explicitly and explain that MariaDB Vector is your professor's required database. Do not invent a setting or claim all three generic controls were tuned.

## 13. Run a live search and inspect relevance

```bash
python src/pipeline.py --run runs/run01 search
```

Type, for example:

```text
What upgrade addresses DC overcurrent trips during rapid power ramping in hot weather?
```

Read the returned source and passage. Another example:

```text
What termination resistance should be measured on the BMS communication bus?
```

The terminal prints embedding time, database retrieval time, and combined time separately. A database time under 20 ms does not mean the entire application ran in under 20 ms. Do not report a single fast query as the benchmark median.

Inspect at least ten questions, including service queries. Record question ID, returned chunk ID, source/page, whether the passage answers the question, and a short reason in a separate relevance log. There may be related but unhelpful passages even when ANN recall is high. For a question not covered by the collection, say evidence was not found; this search interface does not invent an answer.

## 14. Generate the benchmark notebook and charts

The supplied notebook is intentionally unexecuted. It reads YOUR results and creates charts on YOUR instance.

```bash
python -m ipykernel install --user --name gigavolt-m4 --display-name "Gigavolt M4"
python src/run_notebook.py --run runs/run01
```

Outputs are `runs/run01/benchmark_results.ipynb` and three PNG charts in the run folder. Download them to the LAPTOP:

```bash
scp -i "$M4_KEY" -r "ubuntu@$M4_IP:~/Gigavolt_M4_Existing_Instance/runs/run01" "$HOME/Downloads/Gigavolt_M4_results"
```

Open the notebook in VS Code or Jupyter locally. Review executed cells, latency distribution, recall-versus-latency chart, load/index timing, final pass/fail statement, and the written limitations. Keep the raw CSVs with the notebook so another reader can reproduce the plots.

## 15. Preserve the work and recover after a lab stop

On the NEW instance:

```bash
mkdir -p backups
umask 077
set -o pipefail
sudo mariadb-dump --single-transaction --quick gigavolt_m4 | gzip > backups/gigavolt_m4.sql.gz.part && \
  mv backups/gigavolt_m4.sql.gz.part backups/gigavolt_m4.sql.gz
gzip -t backups/gigavolt_m4.sql.gz
```

Download that backup and the project run files to your laptop. Keep `config/db.json` private and out of your Word document or shared source archive. A successful gzip check verifies compression integrity, not a tested database restore; embeddings and original inputs also allow rebuilding tables.

After a normal EC2 stop/start, reconnect using its current public IP:

```bash
sudo systemctl start mariadb
sudo systemctl is-active mariadb
cd "$HOME/Gigavolt_M4_Existing_Instance"
source .venv/bin/activate
python src/pipeline.py --run runs/run01 search
```

This standalone instance needs no `galera_new_cluster` command. Do not bootstrap the Milestone 3 cluster for this search service.

## 16. Troubleshooting without hiding failures

- Socket error: inspect `sudo systemctl status mariadb --no-pager` and `sudo journalctl -u mariadb -n 80 --no-pager`. Do not reinstall over existing data.
- Connection refused from Python: check the local service and `config/db.json`; no public database port is required.
- Unknown VECTOR type or missing mhnsw variables: the installed version is wrong for this kit. Inspect `SELECT VERSION()` and package sources.
- Empty PDF page: inspect its image. Add OCR only after identifying scanned content; do not silently discard it.
- Model download failure: check outbound HTTPS/DNS, disk space, and retry the stage. Do not change models midway through a run.
- Out of memory: use batch 2, close unrelated jobs, or increase permitted instance RAM. Never present incomplete embeddings as a complete run.
- Stage already exists: completed evidence is protected. For a changed configuration use `--run runs/run02` through every stage, starting at extract. Do not mix chunks from one run with embeddings from another.
- No passing tuning configuration: examine raw recall and timings, index use, ties, instance load, and relevance. Report the failure honestly. Further tuning is allowed, but freeze a new held-out set before validating it.
- A partial table load exists: retain logs, identify only that run's generated tables, and plan a clean rebuild. The scripts intentionally do not automatically delete database contents.

## 17. A video under five minutes

Prepare dependencies, input transfers, and a rehearsal before recording. Use separate terminal tabs and increase font size. Do not expose the private account file. If a full embedding/load takes longer than the recording limit, label a cut or speed-up honestly and retain the full logs; do not pretend the complete dataset finished instantly.

- **0:00–0:35 — Purpose and data.** “I built a search system for Gigavolt technical documents and service records. The supplied collection has 25 PDFs across 54 pages, with one verified blank page excluded. The service export adds [actual count] records. The purpose is to help technicians locate relevant instructions and previous work.” Show the inventory and instance.
- **0:35–1:15 — Chunking.** Show the chunk command, report, and sample passages. “I group sentences into chunks up to 220 tokens and retain overlapping context. This fits the model's 256-token limit. Source names, pages and IDs remain attached.” For a live fresh demonstration, use a new `--run runs/video01` and execute extract then chunk; do not overwrite run01.
- **1:15–1:55 — Embedding.** Run embed on video01, show progress and the report. “The model produces 384 numbers per chunk. Batches control memory use. The saved model revision and hashes make the run traceable.” Use an explicitly labeled cut if needed.
- **1:55–2:35 — MariaDB ingestion.** Run load on video01, show row counts and the generated schema. “MariaDB stores the vectors and their source metadata. I compared three index-connectivity settings using the same data.” This creates additional experiment tables; check disk space first.
- **2:35–3:20 — Benchmark method and results.** Show the executed run01 notebook. Clearly say these are the complete earlier benchmark, not newly produced video01 results. “I tuned on 20 questions, then evaluated the selected setting on ten held-out questions. Database retrieval excludes embedding time. The measured P50 is [actual], P95 [actual], P99 [actual], and recall@5 [actual].” Explain M and search effort briefly, and disclose the missing ef_construction control.
- **3:20–4:35 — Live searches.** Use the fully benchmarked run01 search command, ask two questions, show source passages and separate timings. Explain one useful match and any limitation honestly.
- **4:35–4:55 — Business value and limits.** “This helps locate evidence for technical decisions. The benchmark uses this specific corpus on one local client, so it is not a claim of large-scale performance. Source documents still need human review.”

The full fresh video01 ingestion is useful demonstration evidence, but run01 remains the source of the reported tuning/test results. Do not claim video01 has passed the benchmark unless you separately benchmark it.

## 18. Submission checklist and four Ds

Include the scripts, generated SQL schema, executed notebook with graphs, raw benchmark CSVs, chunk/embedding reports, actual screenshots, and the unlisted video link in the required Word submission. Paste the relevant code as required by your instructor; a ZIP alone does not replace that requirement. This kit contains no invented benchmark results.

The assignment asks for the **four Ds of AI fluency**: Delegation, Description, Discernment, and Diligence. [Framework reference](https://www.anthropic.com/ai-fluency/overview). Write a truthful reflection after executing the project:

- **Delegation:** Explain which tasks you assigned to AI, such as drafting extraction code and benchmark steps, and which decisions and execution you retained.
- **Description:** Explain how you specified MariaDB Vector, the actual ZIP, the separate-instance constraint, and the required evidence.
- **Discernment:** Describe how you checked extracted text, tested code, inspected source passages, and distinguished measured results from assumptions. Include an actual issue you caught.
- **Diligence:** Disclose AI assistance, protect credentials, preserve source attribution, and report failed or incomplete measurements honestly. Do not claim tests were performed before you perform them.

## 19. Official references and validation status

- [MariaDB Vector overview](https://mariadb.com/docs/server/reference/sql-structure/vectors/vector-overview): vector columns, dimensions and vector-index syntax.
- [MariaDB vector variables](https://mariadb.com/docs/server/reference/sql-structure/vectors/vector-system-variables): supported M and search-effort controls.
- [Cosine distance](https://mariadb.com/docs/server/reference/sql-functions/vector-functions/vec_distance_cosine): distance function and index metric alignment.
- [VEC_FromText](https://mariadb.com/docs/server/reference/sql-functions/vector-functions/vec_fromtext): conversion from JSON numeric arrays.
- [Model card](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2): 384 dimensions and default 256-word-piece truncation.
- [Course data hub](https://622.gomillion.org): professor-supplied source; the attached ZIP was used for inspection when the site could not be reached here.

Verified locally: extraction of this ZIP, archive inventory, visual review of the blank page, six offline windowing tests, Python syntax, shell syntax, and notebook JSON structure. The windowing tests use a simple test tokenizer; they do not substitute for checking real model-tokenizer output. AWS package installation, model downloads, actual embedding generation, MariaDB vector SQL execution, notebook execution against real results, and measured performance remain to be validated on your instance. No claim is made that the latency or recall target has already been met.
