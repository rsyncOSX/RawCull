import sys,json,collections
from pathlib import Path
sys.path.insert(0,'/Users/thomas/.agents/skills/SwiftUI-Agent-Skill/skills/swiftui-expert-skill/scripts')
from instruments_parser import xml_utils as u
patterns={
 'preload':'ScanAndCreateThumbnails.preloadCatalog',
 'process_single':'ScanAndCreateThumbnails.processSingleFile',
 'grid_store':'ScanAndCreateThumbnails.storeInGridCache',
 'old_grid_downscale':'ScanAndCreateThumbnails.downscale',
 'new_grid_resize':'GridThumbnailResizer.resize',
 'metadata_loader':'RawImageLoader.loadMetadata',
 'scan_files':'ScanFiles.scanFiles',
 'jpeg_encode':'DiskCacheManager.jpegData',
 'disk_load':'DiskCacheManager.load',
 'image_properties':'CGImageSourceCopyPropertiesAtIndex',
 'sharpness_ordered_targets':'RawCullViewModel.sharpnessScoringTargetFiles.getter',
 'sharpness_target_count':'RawCullViewModel.sharpnessScoringTargetCount.getter',
 'zoom_ordered_files':'ZoomNavigationPresentation.orderedZoomFiles.getter',
 'zoom_projection':'RawCullViewModel.zoomNavigationProjection',
}
for label in ['before','after']:
 s=u.RowStream(Path('/tmp/rawcull-open-'+label+'-cpu.xml').read_bytes()); cache={}; agg=collections.defaultdict(lambda:collections.Counter()); totals=collections.Counter(); bins=collections.defaultdict(collections.Counter); spans={}; count=0; weight_counts=collections.Counter(); examples={}
 for r in s:
  if any(k not in r for k in ['stack','time','weight','thread']):continue
  t=u.int_text(s.resolve(r['time']));w=u.int_text(s.resolve(r['weight']))
  if t is None or w is None:continue
  thread=u.extract_thread(r['thread'],s);cat='main' if thread['is_main'] else 'background'
  # The trace targets RawCull; keep the explicit process filter for repeatability.
  if (thread.get('process') or {}).get('name')!='RawCull':continue
  bt=s.resolve(r['stack']);key=bt.get('id') or id(bt)
  if key not in cache:
   fs=[f['name'] for f in u.extract_backtrace(r['stack'],s,300)]
   tags={n for n,p in patterns.items() if any(p in f for f in fs)}
   if any('SwiftUITrace' in f or 'Trace.SwiftUI' in f or 'Trace_Handle' in f or 'AGGraphAddTraceEvent' in f for f in fs):tags.add('tracing_named_frame_heuristic')
   cache[key]=(tags,fs[0] if fs else '<empty>')
   for n in tags:examples.setdefault(n,fs[:65])
  tags,leaf=cache[key]
  count+=1;weight_counts[w]+=1;totals[cat]+=w
  bins[int(t/1e9)][cat]+=w
  for n in tags:
   agg[n][cat]+=w;bins[int(t/1e9)][n]+=w
   if n not in spans:spans[n]=[t,t]
   else:spans[n][1]=t
 result={'trace_label':label,'sample_count':count,'sample_weight_ns_distribution':dict(weight_counts),'total_sample_weight_ms':{k:round(v/1e6,3) for k,v in totals.items()},'inclusive_sample_weight_ms':{k:{th:round(w/1e6,3) for th,w in v.items()} for k,v in agg.items()},'first_last_matching_sample_ms':{k:[round(t/1e6,3) for t in v] for k,v in spans.items()},'per_second_sample_weight_ms':{k:{n:round(w/1e6,3) for n,w in v.items()} for k,v in sorted(bins.items())},'representative_stacks':examples,'notes':['Inclusive pattern weights overlap; never add parents and children.','First/last matching samples are sampled activity bounds, not operation latency or completion markers.','Missing sampled frames do not prove that a method was never called.','Truncation at 300 frames may omit deeper callers.']}
 Path('/tmp/rawcull-open-'+label+'-paths.json').write_text(json.dumps(result,indent=2)+'\n')
 print(label,json.dumps({k:result[k] for k in ['sample_count','total_sample_weight_ms','inclusive_sample_weight_ms']},indent=2),flush=True)
 del s,cache
