"""Execute the supplied notebook against real benchmark output, never synthetic results."""
import argparse,os
from pathlib import Path
import nbformat
from nbclient import NotebookClient
p=argparse.ArgumentParser();p.add_argument('--run',required=True);a=p.parse_args()
run=Path(a.run).resolve();root=Path(__file__).resolve().parents[1]
for name in ['benchmark_test/summary.csv','benchmark_tune/summary.csv','selection.json']:
 if not (run/name).exists(): raise SystemExit('Missing real result: '+str(run/name))
out=run/'benchmark_results.ipynb'
if out.exists(): raise SystemExit('Executed notebook already exists; preserve it before rerunning.')
os.environ['GIGAVOLT_RUN']=str(run)
nb=nbformat.read(root/'notebooks/benchmark_template.ipynb',as_version=4)
client=NotebookClient(nb,timeout=180,kernel_name='gigavolt-m4',resources={'metadata':{'path':str(root)}})
try:
 client.execute()
except Exception:
 nbformat.write(nb,run/'benchmark_results_failed.ipynb');raise
nbformat.write(nb,out)
print(out)
