#!/usr/bin/env python3
"""Gigavolt M4: explicit, restartable stages. No server changes on import.
Each run directory is immutable per stage: choose a new --run to rebuild.
Database measurements and embeddings must be generated on the user's instance.
"""
import argparse, csv, hashlib, io, json, os, platform, random, re
import statistics, subprocess, time, unicodedata, zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MODEL='sentence-transformers/all-MiniLM-L6-v2'
def sha(x): return hashlib.sha256(x).hexdigest()
def now(): return datetime.now(timezone.utc).isoformat()
def write(path,obj):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix(path.suffix+'.tmp')
    temp.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n'); temp.replace(path)
def read(path): return json.loads(Path(path).read_text())
def lines(path): return [json.loads(x) for x in Path(path).read_text().splitlines() if x.strip()]
def jl(path,rows):
    temp=Path(str(path)+'.tmp'); temp.parent.mkdir(parents=True,exist_ok=True)
    with temp.open('w') as f:
        for r in rows: f.write(json.dumps(r,ensure_ascii=False)+'\n')
    temp.replace(path)
def clean(text):
    # Preserve technical symbols, units, codes and numbers; collapse PDF layout whitespace.
    return re.sub(r'\s+',' ',unicodedata.normalize('NFC',text).replace('\x00',' ')).strip()
def newstage(path):
    if path.exists(): raise RuntimeError(f'{path} already exists. Use a new --run; do not overwrite evidence.')
def connect():
    import pymysql
    return pymysql.connect(**read(ROOT/'config/db.json'),charset='utf8mb4',autocommit=False,
                           connect_timeout=15,read_timeout=180,write_timeout=180)
def model(run):
    import torch
    from sentence_transformers import SentenceTransformer
    torch.set_num_threads(2)
    cfg=read(run/'chunk_config.json')
    m=SentenceTransformer(MODEL,revision=cfg['revision'],device='cpu',cache_folder=str(ROOT/'models'))
    if m.max_seq_length<cfg['target']+m.tokenizer.num_special_tokens_to_add(False):
        raise ValueError('Chunk target exceeds model input capacity')
    return m

def extract(a,run):
    from pypdf import PdfReader
    newstage(run/'documents.jsonl'); units=[]; inventory=[]; empty=[]
    archive=Path(a.archive)
    with zipfile.ZipFile(archive) as z:
        if sum(x.file_size for x in z.infolist())>500_000_000: raise ValueError('Unexpected archive expansion >500 MB')
        for info in sorted(z.infolist(),key=lambda x:x.filename):
            if info.is_dir(): continue
            path=Path(info.filename)
            if path.is_absolute() or '..' in path.parts: raise ValueError('Unsafe archive path')
            if path.suffix.lower()!='.pdf': raise ValueError(f'Unexpected file: {info.filename}')
            data=z.read(info); docsha=sha(data); sid=sha((info.filename+docsha).encode())
            reader=PdfReader(io.BytesIO(data)); counts=[]
            for i,page in enumerate(reader.pages,1):
                text=clean(page.extract_text() or ''); counts.append(len(text))
                if not text:
                    known=(path.name=='GV-SPEC-BMS-ARC-01 System Architecture.pdf' and i==2 and sha(archive.read_bytes())=='77f5aa14797985347e40d8db6977976af2785a97646891a792873bf1f8875ed3')
                    empty.append({'file':info.filename,'page':i,'reviewed_blank_in_supplied_archive':known})
                    if not known: raise ValueError(f'Empty page requires visual/OCR review: {info.filename} page {i}')
                    continue
                units.append(dict(source_id=sid,source_type='manual',source_file=info.filename,
                    record_id='',page_number=i,text=text,source_sha256=docsha,source_timestamp='',ingested_at=now()))
            inventory.append(dict(file=info.filename,sha256=docsha,pages=len(reader.pages),characters=sum(counts)))
    if a.services:
        seen=set()
        for row in lines(a.services):
            rid=str(row['record_id'])
            if rid in seen: raise ValueError('Duplicate service record ID: '+rid)
            seen.add(rid); text=clean(row['text'])
            if not text: raise ValueError('Empty service text: '+rid)
            units.append(dict(source_id=sha(('rag_payloads:'+rid).encode()),source_type='service_record',
                source_file='gigavolt.rag_payloads',record_id=rid,page_number=0,text=text,
                source_sha256=sha(text.encode()),source_timestamp=str(row.get('source_timestamp') or ''),
                equipment_id=str(row.get('equipment_id') or ''),dispatch_id=str(row.get('dispatch_id') or ''),ingested_at=now()))
    jl(run/'documents.jsonl',units)
    write(run/'inventory.json',dict(archive_sha256=sha(archive.read_bytes()),pdf_files=inventory,
        pdf_count=len(inventory),pdf_pages=sum(x['pages'] for x in inventory),empty_pages=empty,
        service_records=sum(x['source_type']=='service_record' for x in units),units=len(units)))
    print(json.dumps(read(run/'inventory.json'),indent=2))

def windows(text,tokenizer,nlp,target,overlap):
    """Sentence-aware windows with exact text offsets and forced token fallback.
    Each new window consumes at least one new unit. Overlap never prevents progress.
    """
    count=lambda s: len(tokenizer.encode(s,add_special_tokens=False))
    units=[]; fallback=0
    for sent in nlp(text).sents:
        st,en=sent.start_char,sent.end_char
        if not text[st:en].strip(): continue
        if count(text[st:en])<=target: units.append((st,en)); continue
        fallback+=1
        offsets=tokenizer(text[st:en],add_special_tokens=False,return_offsets_mapping=True)['offset_mapping']
        k=0
        while k<len(offsets):
            stop=min(k+(overlap or target),len(offsets)); end=st+offsets[stop-1][1]
            begin=st+offsets[k][0]
            while count(text[begin:end])>target and stop>k+1:
                stop-=1; end=st+offsets[stop-1][1]
            if count(text[begin:end])>target: raise ValueError('Unable to fit fallback segment')
            units.append((begin,end)); k=stop
    result=[]; i=0; previous_end=0
    while i<len(units):
        j=i
        while j<len(units) and count(text[units[i][0]:units[j][1]])<=target: j+=1
        if j==i: raise ValueError('Chunk did not advance')
        st,en=units[i][0],units[j-1][1]
        result.append(dict(text=text[st:en],start_char=st,end_char=en,token_count=count(text[st:en]),
                           overlap_chars=max(0,previous_end-st)))
        previous_end=en
        if j==len(units): break
        nxt=j
        # Retain whole trailing units only if overlap target and next chunk capacity permit.
        while nxt>i+1 and count(text[units[nxt-1][0]:units[j-1][1]])<=overlap:
            nxt-=1
        while nxt<j and count(text[units[nxt][0]:units[j][1]])>target: nxt+=1
        i=nxt
    return result,fallback

def chunk(a,run):
    import spacy
    from huggingface_hub import model_info
    from transformers import AutoTokenizer
    newstage(run/'chunks.jsonl')
    if not 0<=a.overlap<a.target<=250: raise ValueError('Require 0 <= overlap < target <= 250')
    revision=model_info(MODEL).sha
    tok=AutoTokenizer.from_pretrained(MODEL,revision=revision,cache_dir=str(ROOT/'models'),use_fast=True)
    nlp=spacy.blank('en'); nlp.add_pipe('sentencizer'); nlp.max_length=5_000_000
    rows=[]; forced=0
    cfg=dict(model=MODEL,revision=revision,target=a.target,overlap=a.overlap,sentence_splitter='spacy.blank(en).sentencizer',
             boundaries='page-local for PDFs; service-record-local; overlap may be smaller to preserve whole sentences')
    for doc in lines(run/'documents.jsonl'):
        chunks,n=windows(doc['text'],tok,nlp,a.target,a.overlap); forced+=n
        for idx,w in enumerate(chunks):
            item={**doc,**w,'chunk_index':idx,'text_sha256':sha(w['text'].encode())}
            item['chunk_id']=sha(json.dumps([doc['source_id'],doc['page_number'],idx,w['text'],cfg],sort_keys=True).encode())
            rows.append(item)
    if not rows or len({r['chunk_id'] for r in rows})!=len(rows): raise ValueError('Empty/duplicate chunks')
    jl(run/'chunks.jsonl',rows); write(run/'chunk_config.json',cfg)
    counts=[x['token_count'] for x in rows]
    report=dict(chunks=len(rows),min_tokens=min(counts),median_tokens=statistics.median(counts),max_tokens=max(counts),
        long_sentence_fallbacks=forced,overlapping_chunks=sum(x['overlap_chars']>0 for x in rows))
    write(run/'chunk_report.json',report); print(json.dumps(report,indent=2))
    for r in rows[:3]: print('\nSOURCE',r['source_file'],'PAGE',r['page_number'],'CHUNK',r['chunk_index'],'\n',r['text'])

def embed(a,run):
    import numpy as np
    newstage(run/'embeddings.npy'); rows=lines(run/'chunks.jsonl'); m=model(run)
    t=time.perf_counter(); v=m.encode([r['text'] for r in rows],batch_size=a.batch,normalize_embeddings=True,
                                    show_progress_bar=True,convert_to_numpy=True).astype('float32')
    if v.shape!=(len(rows),384) or not np.isfinite(v).all(): raise ValueError('Invalid embeddings')
    if not np.allclose(np.linalg.norm(v,axis=1),1,atol=1e-4): raise ValueError('Non-unit embeddings')
    np.save(run/'embeddings.npy',v)
    write(run/'embedding_report.json',dict(rows=len(rows),dimensions=384,seconds=time.perf_counter()-t,batch=a.batch,
        chunks_sha256=sha((run/'chunks.jsonl').read_bytes()),embeddings_sha256=sha((run/'embeddings.npy').read_bytes())))
    print(json.dumps(read(run/'embedding_report.json'),indent=2))

def load(a,run):
    import numpy as np
    newstage(run/'tables.json'); rows=lines(run/'chunks.jsonl'); v=np.load(run/'embeddings.npy')
    cfg=read(run/'chunk_config.json'); er=read(run/'embedding_report.json')
    if er['chunks_sha256']!=sha((run/'chunks.jsonl').read_bytes()) or er['embeddings_sha256']!=sha((run/'embeddings.npy').read_bytes()):
        raise ValueError('Embedding provenance mismatch')
    if len(rows)!=len(v): raise ValueError('Count mismatch')
    tag=sha((str(run.resolve())+er['chunks_sha256']).encode())[:12]; tables={}; builds=[]
    db=connect()
    try:
        for mval in [6,8,16]:
            name=f'c_{tag}_m{mval}'; tables[str(mval)]=name
            ddl=f'''CREATE TABLE {name} (
chunk_id CHAR(64) CHARACTER SET ascii PRIMARY KEY,
source_file TEXT NOT NULL, source_type VARCHAR(32) NOT NULL,
page_number INT NOT NULL, chunk_index INT NOT NULL, token_count INT NOT NULL,
chunk_text LONGTEXT NOT NULL, metadata_json JSON NOT NULL,
embedding VECTOR(384) NOT NULL,
VECTOR INDEX vec_idx (embedding) M={mval} DISTANCE=cosine
) ENGINE=InnoDB'''
            (run/f'schema_m{mval}.sql').write_text(ddl+';\n')
            t=time.perf_counter()
            with db.cursor() as cur:
                cur.execute(ddl)
                for begin in range(0,len(rows),64):
                    batch=[]
                    for j in range(begin,min(begin+64,len(rows))):
                        r=rows[j]; meta={k:val for k,val in r.items() if k!='text'}; meta.update(cfg)
                        batch.append((r['chunk_id'],r['source_file'],r['source_type'],r['page_number'],r['chunk_index'],
                                      r['token_count'],r['text'],json.dumps(meta,ensure_ascii=False),json.dumps(v[j].tolist())))
                    cur.executemany(f'INSERT INTO {name} VALUES (%s,%s,%s,%s,%s,%s,%s,%s,VEC_FromText(%s))',batch); db.commit()
                cur.execute(f'SELECT COUNT(*) FROM {name}'); assert cur.fetchone()[0]==len(rows)
                cur.execute(f'SELECT chunk_id FROM {name}'); assert {x[0] for x in cur.fetchall()}=={r['chunk_id'] for r in rows}
            builds.append(dict(M=mval,table=name,load_and_index_seconds=time.perf_counter()-t,rows=len(rows)))
            print(builds[-1])
        write(run/'tables.json',tables); write(run/'builds.json',builds)
    finally: db.close()

def query_sql(table):
    if not re.fullmatch(r'c_[0-9a-f]{12}_m(6|8|16)',table): raise ValueError('Invalid table name')
    return f'''SELECT SQL_NO_CACHE chunk_id, source_file, page_number, chunk_text,
VEC_DISTANCE_COSINE(embedding,VEC_FromText(%s)) AS distance
FROM {table} ORDER BY distance LIMIT 5'''

def bench(a,run):
    import numpy as np
    out=run/f'benchmark_{a.split}'; newstage(out); out.mkdir()
    questions=[x for x in read(ROOT/'config/questions.json') if x['split']==a.split]
    m=model(run); qv=m.encode([x['question'] for x in questions],normalize_embeddings=True,convert_to_numpy=True).astype('float32')
    vectors=np.load(run/'embeddings.npy'); chunks=lines(run/'chunks.jsonl'); ids=[x['chunk_id'] for x in chunks]
    if len(ids)<5: raise ValueError('Need at least 5 chunks')
    exact=[]
    for q in qv:
        d=1-vectors@q; order=np.lexsort((np.array(ids),d)); top=order[:5]
        exact.append((set(ids[i] for i in top),set(ids[i] for i in np.flatnonzero(d<=d[top[-1]]+1e-6))))
    write(out/'ground_truth.json',[dict(question_id=questions[i]['id'],exact_top5=sorted(e[0]),tie_candidates=sorted(e[1])) for i,e in enumerate(exact)])
    np.save(out/'query_embeddings.npy',qv)
    payloads=[json.dumps(q.tolist()) for q in qv]; tables=read(run/'tables.json')
    configs=[(int(k),e) for k in tables for e in [10,20,40,80]]
    if a.split=='test':
        s=read(run/'selection.json'); configs=[(s['M'],s['ef_search'])]
    random.Random(622).shuffle(configs); data=[]; plans=[]; db=connect()
    try:
        with db.cursor() as cur:
            cur.execute('SELECT VERSION()'); version=cur.fetchone()[0]
            cur.execute("SHOW VARIABLES LIKE 'mhnsw%'"); variables=cur.fetchall()
            for M,ef in configs:
                sql=query_sql(tables[str(M)]); cur.execute('SET SESSION mhnsw_ef_search=%s',(ef,))
                cur.execute('EXPLAIN '+sql,(payloads[0],)); columns=[x[0] for x in cur.description]
                plan=[dict(zip(columns,r)) for r in cur.fetchall()]; plans.append(dict(M=M,ef=ef,plan=plan))
                if not any(r.get('key')=='vec_idx' for r in plan):
                    write(out/'explain.json',plans); raise RuntimeError('Vector index not selected. Review EXPLAIN before benchmarking.')
                for p in payloads: cur.execute(sql,(p,)); cur.fetchall()  # one warm-up per question
                jobs=[i for _ in range(a.repeats) for i in range(len(questions))]; random.Random(622).shuffle(jobs)
                for i in jobs:
                    t=time.perf_counter_ns(); cur.execute(sql,(payloads[i],)); result=cur.fetchall(); elapsed=(time.perf_counter_ns()-t)/1e6
                    found={r[0] for r in result}
                    data.append(dict(M=M,ef_search=ef,question_id=questions[i]['id'],latency_ms=elapsed,
                        recall5=len(found&exact[i][0])/5,tie_aware_recall5=len(found&exact[i][1])/5))
        summary=[]
        for M,ef in configs:
            rs=[r for r in data if r['M']==M and r['ef_search']==ef]; ts=[r['latency_ms'] for r in rs]
            summary.append(dict(M=M,ef_search=ef,requests=len(rs),p50_ms=float(np.percentile(ts,50)),
                p95_ms=float(np.percentile(ts,95)),p99_ms=float(np.percentile(ts,99)),
                recall5=float(np.mean([r['recall5'] for r in rs])),tie_aware_recall5=float(np.mean([r['tie_aware_recall5'] for r in rs]))))
        for file,rs in [('raw.csv',data),('summary.csv',summary)]:
            with (out/file).open('w') as f:
                w=csv.DictWriter(f,fieldnames=list(rs[0]));w.writeheader();w.writerows(rs)
        write(out/'explain.json',plans)
        write(out/'method.json',dict(timestamp=now(),mariadb=version,mhnsw=variables,python=platform.python_version(),
            platform=platform.platform(),questions=questions,repeats=a.repeats,warmup='one per question per configuration',
            timing='persistent connection; execute + fetch all top-5 texts and metadata; excludes embedding and printing',
            exact_reference='float32 normalized embeddings, NumPy exhaustive dot product; strict IDs and tolerance 1e-6 tie-aware recall',
            corpus_size=len(ids),failures=0,scope='Fails closed on first DB error; incomplete run is not a passing benchmark'))
        if a.split=='tune':
            eligible=[s for s in summary if s['recall5']>0.9 and s['p50_ms']<20]
            if eligible:
                best=min(eligible,key=lambda s:s['p50_ms']);write(run/'selection.json',best)
                print('Selected from tuning only:',best)
            else: print('No setting meets both strict recall >0.9 and median <20ms. No selection created; inspect results.')
        print(json.dumps(summary,indent=2))
    except Exception as e:
        jl(out/'partial_requests.jsonl',data)
        write(out/'FAILED.json',dict(error=str(e),completed_requests=len(data),timestamp=now()));raise
    finally: db.close()

def search(a,run):
    m=model(run); s=read(run/'selection.json'); table=read(run/'tables.json')[str(s['M'])]
    db=connect()
    try:
        with db.cursor() as cur:
            cur.execute('SET SESSION mhnsw_ef_search=%s',(s['ef_search'],))
            while True:
                question=input('\nQuestion (blank to quit): ').strip()
                if not question: break
                if len(m.tokenizer.encode(question))>m.max_seq_length:
                    print('Question is too long; shorten it to avoid truncation.'); continue
                start=time.perf_counter(); vector=m.encode(question,normalize_embeddings=True).tolist(); encoded=time.perf_counter()
                payload=json.dumps(vector); t=time.perf_counter();cur.execute(query_sql(table),(payload,)); rows=cur.fetchall();end=time.perf_counter()
                print(f'Embedding: {(encoded-start)*1000:.3f} ms; database: {(end-t)*1000:.3f} ms; combined: {(end-start)*1000:.3f} ms')
                for cid,source,page,text,distance in rows:
                    print(f'\n{source} | page {page} | chunk {cid} | distance {distance:.6f}\n{text}')
    finally: db.close()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run',default='runs/run01')
    sub=p.add_subparsers(dest='command',required=True)
    e=sub.add_parser('extract');e.add_argument('--archive',required=True);e.add_argument('--services')
    c=sub.add_parser('chunk');c.add_argument('--target',type=int,default=220);c.add_argument('--overlap',type=int,default=40)
    e=sub.add_parser('embed');e.add_argument('--batch',type=int,default=8)
    sub.add_parser('load')
    b=sub.add_parser('benchmark');b.add_argument('--split',choices=['tune','test'],required=True);b.add_argument('--repeats',type=int,default=20)
    sub.add_parser('search');a=p.parse_args();run=Path(a.run).resolve();run.mkdir(parents=True,exist_ok=True)
    if getattr(a,'repeats',1)<1 or getattr(a,'batch',1)<1: p.error('Batch/repeats must be positive')
    {'extract':extract,'chunk':chunk,'embed':embed,'load':load,'benchmark':bench,'search':search}[a.command](a,run)
if __name__=='__main__': main()
