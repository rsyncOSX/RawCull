import sys,json,collections
from pathlib import Path
sys.path.insert(0,'/Users/thomas/.agents/skills/SwiftUI-Agent-Skill/skills/swiftui-expert-skill/scripts')
from instruments_parser import xml_utils as u
s=u.RowStream(Path('/tmp/rawcull-browse-cpu.xml').read_bytes())
counts=collections.defaultdict(collections.Counter); totals=collections.Counter(); examples={}; cache={}
windows={'hang40':(40389.57,40652.57),'hang95':(95885.10,96151.10),'hang119':(119873.86,120452.86),'hitch68':(68393.38,68543.38),'hitch112':(112968.31,113135.31)}
for r in s:
 if 'stack' not in r or 'time' not in r: continue
 t=u.int_text(s.resolve(r['time']))/1e6; w=u.int_text(s.resolve(r['weight']))/1e6
 th=u.extract_thread(r['thread'],s); bt=s.resolve(r['stack']); key=bt.get('id') or id(bt)
 if key not in cache: cache[key]=[f['name'] for f in u.extract_backtrace(r['stack'],s,250)]
 fs=cache[key]
 cats=['main' if th['is_main'] else 'background']
 if th['is_main']: cats += [n for n,(a,b) in windows.items() if a<=t<=b]
 for cat in cats:
  totals[cat]+=w
  for f in set(fs): counts[cat][f]+=w
  if any('Trace.' in f or 'SwiftUITrace' in f or 'Tracing' in f or 'Tracing' in f or 'trace' in f.lower() and 'backtrace' not in f.lower() for f in fs): counts[cat]['[any tracing frame]']+=w
  for f in fs:
   if any(n in f for n in ['RawCull','Thumbnail','Zoom','ImageItem','ImageTable','Loupe','FileHandler']):
    counts[cat+'-app'][f]+=w
 for f in fs:
  if ('findClosestDefinedSymbol' in f or 'swift_conformsToProtocolMaybe' in f) and (th['is_main']): examples.setdefault(f,fs)
result={'total_sample_weight_ms':dict(totals),'inclusive_stacks':{k:v.most_common(300) for k,v in counts.items()},'examples':examples}
Path('/tmp/rawcull-stack-details.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
