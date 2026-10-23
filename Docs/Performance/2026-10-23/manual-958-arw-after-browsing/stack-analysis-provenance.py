import sys,json,collections
from pathlib import Path
sys.path.insert(0,'/Users/thomas/.agents/skills/SwiftUI-Agent-Skill/skills/swiftui-expert-skill/scripts')
from instruments_parser import xml_utils as u
patterns={
'preload':'ScanAndCreateThumbnails.preloadCatalog','grid_resize':'GridThumbnailResizer.resize','metadata_loader':'RawImageLoader.loadMetadata',
'sharpness_ordered_targets':'RawCullViewModel.sharpnessScoringTargetFiles.getter','sharpness_target_count':'RawCullViewModel.sharpnessScoringTargetCount.getter','sharpness_description':'RawCullViewModel.sharpnessScoringTargetDescription.getter',
'zoom_ordered_files':'ZoomNavigationPresentation.orderedZoomFiles.getter','zoom_current_index':'ZoomNavigationPresentation.currentZoomIndex.getter','zoom_projection':'RawCullViewModel.zoomNavigationProjection',
'zoom_keyboard':'ZoomOverlayView.handleKeyEvent','zoom_navigate':'ZoomOverlayView.navigateSelection','selected_file':'RawCullViewModel.selectedFile.getter',
'jpeg_encode':'DiskCacheManager.jpegData','disk_load':'DiskCacheManager.load','image_properties':'CGImageSourceCopyPropertiesAtIndex',
}
s=u.RowStream(Path('/tmp/rawcull-browsing-after-cpu.xml').read_bytes());cache={};weights=collections.Counter();totals=collections.Counter();leaves=collections.defaultdict(collections.Counter);symbols=collections.defaultdict(collections.Counter);apps=collections.defaultdict(collections.Counter);bins=collections.defaultdict(collections.Counter);spans={};patternsums=collections.defaultdict(collections.Counter);examples={};samples=0;later_symbols=collections.defaultdict(collections.Counter);later_apps=collections.defaultdict(collections.Counter);later_patterns=collections.defaultdict(collections.Counter);later_totals=collections.Counter()
app_tokens=['RawCull','Zoom','Thumbnail','Loupe','Histogram','Focus','Comparison','ScanFiles','DiskCache','ImageItem','ImageTable','ImageReview','RAWExposure','RAWPreview','RawImageLoader','ImageSource','ReviewImage','Sharpness','Semantic']
for r in s:
 if any(k not in r for k in ['stack','time','weight','thread']):continue
 t=u.int_text(s.resolve(r['time']));w=u.int_text(s.resolve(r['weight']));th=u.extract_thread(r['thread'],s)
 if t is None or w is None or (th.get('process') or {}).get('name')!='RawCull':continue
 cat='main' if th['is_main'] else 'background';bt=s.resolve(r['stack']);key=bt.get('id') or id(bt)
 if key not in cache:
  fs=[f['name'] for f in u.extract_backtrace(r['stack'],s,300)]
  tags={n for n,p in patterns.items() if any(p in f for f in fs)}
  if any('SwiftUITrace' in f or 'Trace.SwiftUI' in f or 'Trace_Handle' in f or 'AGGraphAddTraceEvent' in f for f in fs):tags.add('tracing_named_frame_heuristic')
  app={f for f in fs if any(token in f for token in app_tokens)}
  cache[key]=(tags,fs[0] if fs else '<empty>',set(fs),app)
  for n in tags:examples.setdefault(n,fs[:80])
 tags,leaf,fs,app=cache[key];samples+=1;weights[w]+=1;totals[cat]+=w;leaves[cat][leaf]+=w;bins[int(t/1e9)][cat]+=w
 for f in fs:symbols[cat][f]+=w
 for f in app:apps[cat][f]+=w
 if t >= 31_000_000_000:
  later_totals[cat]+=w
  for f in fs:later_symbols[cat][f]+=w
  for f in app:later_apps[cat][f]+=w
  for n in tags:later_patterns[n][cat]+=w
 for n in tags:
  patternsums[n][cat]+=w;bins[int(t/1e9)][n]+=w
  if n not in spans:spans[n]=[t,t]
  else:spans[n][1]=t
result={'sample_count':samples,'sample_weight_ns_distribution':dict(weights),'total_sample_weight_ms':{k:round(v/1e6,3) for k,v in totals.items()},'inclusive_pattern_weight_ms':{k:{th:round(w/1e6,3) for th,w in v.items()} for k,v in patternsums.items()},'top_leaf_symbols_ms':{k:[(f,round(w/1e6,3)) for f,w in v.most_common(30)] for k,v in leaves.items()},'inclusive_symbol_weights_ms':{k:[(f,round(w/1e6,3)) for f,w in v.most_common(120)] for k,v in symbols.items()},'inclusive_app_symbol_weights_ms':{k:[(f,round(w/1e6,3)) for f,w in v.most_common(100)] for k,v in apps.items()},'first_last_matching_sample_ms':{k:[round(t/1e6,3) for t in v] for k,v in spans.items()},'per_second_sample_weight_ms':{k:{n:round(w/1e6,3) for n,w in v.items()} for k,v in sorted(bins.items())},'representative_stacks':examples,'notes':['Inclusive weights overlap; absent samples do not prove a method was never called.','First/last sampled activity is not an exact operation latency.','App symbol classification is a substring heuristic, not binary ownership.']}
result['after_preload_window']={'start_ms':31000,'end_ms':72466.131,'reason':'First whole second after the last sampled preload stack at 30840.416 ms; not an exact completion marker.','total_sample_weight_ms':{k:round(v/1e6,3) for k,v in later_totals.items()},'inclusive_pattern_weight_ms':{k:{th:round(w/1e6,3) for th,w in v.items()} for k,v in later_patterns.items()},'inclusive_app_symbol_weights_ms':{k:[(f,round(w/1e6,3)) for f,w in v.most_common(40)] for k,v in later_apps.items()}}
Path('/tmp/rawcull-browsing-after-paths.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['sample_count','sample_weight_ns_distribution','total_sample_weight_ms','inclusive_pattern_weight_ms','top_leaf_symbols_ms','inclusive_app_symbol_weights_ms']},indent=2))
