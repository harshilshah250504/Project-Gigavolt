"""Offline algorithm tests using a whitespace tokenizer, not a model integration test."""
import re, unittest
from types import SimpleNamespace
from pipeline import windows, clean
class Tokenizer:
 def encode(self,s,add_special_tokens=False): return s.split()
 def __call__(self,s,**kw): return {'offset_mapping':[(m.start(),m.end()) for m in re.finditer(r'\S+',s)]}
def sentences(s):
 return SimpleNamespace(sents=[SimpleNamespace(start_char=m.start(),end_char=m.end()) for m in re.finditer(r'[^.!?]+[.!?]?',s)])
class Checks(unittest.TestCase):
 def verify(self,text,target=12,overlap=4):
  rows,n=windows(text,Tokenizer(),sentences,target,overlap)
  self.assertTrue(rows)
  self.assertTrue(all(0<r['token_count']<=target for r in rows))
  self.assertTrue(all(rows[i]['end_char']<rows[i+1]['end_char'] for i in range(len(rows)-1)))
  for m in re.finditer(r'\S',text): self.assertTrue(any(r['start_char']<=m.start()<r['end_char'] for r in rows))
  return rows,n
 def test_sentences(self): self.verify('One two three. Four five six. Seven eight nine. Ten eleven twelve. Thirteen fourteen fifteen.')
 def test_long_sentence_overlap(self):
  rows,n=self.verify(' '.join('word'+str(i) for i in range(100)))
  self.assertEqual(n,1);self.assertTrue(all(r['overlap_chars']>0 for r in rows[1:]))
 def test_no_overlap(self):
  rows,n=self.verify(' '.join('word'+str(i) for i in range(100)),overlap=0)
  self.assertTrue(all(r['overlap_chars']==0 for r in rows))
 def test_single(self): self.verify('ERR_INV_404 exceeds 40 °C.')
 def test_empty(self): self.assertEqual(windows('',Tokenizer(),sentences,12,4),([],0))
 def test_clean(self): self.assertEqual(clean(' 60 ± 2 Ω\n\tERR_BMS_301 '),'60 ± 2 Ω ERR_BMS_301')
if __name__=='__main__': unittest.main()
