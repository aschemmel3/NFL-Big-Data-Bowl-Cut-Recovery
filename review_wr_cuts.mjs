import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const root=path.dirname(fileURLToPath(import.meta.url));
const data=path.join(root,'nfl-big-data-bowl-2027/nfl-big-data-bowl-2027');
const out=path.join(root,'reports/cuts'); fs.mkdirSync(out,{recursive:true});
function csv(text){
  const rows=[]; let row=[],cell='',quoted=false;
  for(let i=0;i<text.length;i++) { const c=text[i];
    if(c==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++;}else quoted=!quoted;}
    else if(c===','&&!quoted){row.push(cell);cell='';}
    else if(c==='\n'&&!quoted){row.push(cell.replace(/\r$/,''));rows.push(row);row=[];cell='';}
    else cell+=c;
  }
  if(cell||row.length){row.push(cell.replace(/\r$/,''));rows.push(row);}
  const header=rows.shift().map(x=>x.replace(/^\uFEFF/,''));
  return rows.filter(r=>r.length===header.length).map(r=>Object.fromEntries(header.map((h,i)=>[h,r[i]])));
}
const read=name=>csv(fs.readFileSync(path.join(data,name),'utf8'));
const mean=a=>a.length?a.reduce((x,y)=>x+y,0)/a.length:null;
const median=a=>{const b=[...a].sort((x,y)=>x-y);return b.length?(b[Math.floor((b.length-1)/2)]+b[Math.ceil((b.length-1)/2)])/2:null;};
const wrap=a=>Math.atan2(Math.sin(a),Math.cos(a));
const deg=a=>a*180/Math.PI;
const players=new Map(read('players.csv').filter(p=>p.nfl_position==='WR'&&['2023','2024'].includes(p.draft_year)).map(p=>[p.nfl_id,p]));
const events=new Map();
for(const f of read('combine_tracking.csv')){
  if(!players.has(f.nfl_id)||f.entity_type!=='PLAYER'||f.drill_type!=='SKILL_DRILLS_WR')continue;
  const key=[f.nfl_id,f.event_id,f.attempt].join('|');
  if(!events.has(key))events.set(key,{key,player:players.get(f.nfl_id),drill:f.drill_name,event_id:f.event_id,attempt:f.attempt,frames:[]});
  events.get(key).frames.push({time:Date.parse(f.time),x:f.x===''?NaN:+f.x,y:f.y===''?NaN:+f.y,s:f.s===''?NaN:+f.s});
}
function prepare(e){
  e.frames.sort((a,b)=>a.time-b.time);const origin=e.frames[0].time;
  e.frames.forEach(f=>f.t=(f.time-origin)/1000);
  const f=e.frames;
  // A centered 3-frame mean attenuates tracking noise; no resampling across gaps.
  for(let i=0;i<f.length;i++){
    const local=f.slice(Math.max(0,i-1),Math.min(f.length,i+2));
    f[i].smooth=mean(local.map(p=>p.s));
    const lo=Math.max(0,i-1),hi=Math.min(f.length-1,i+1),dt=f[hi].t-f[lo].t;
    f[i].vx=(f[hi].x-f[lo].x)/dt; f[i].vy=(f[hi].y-f[lo].y)/dt;
    f[i].heading=Math.atan2(f[i].vy,f[i].vx);
    f[i].coordinateSpeed=Math.hypot(f[i].vx,f[i].vy);
  }
  e.quality=[];
  if(f.some(p=>![p.x,p.y,p.s,p.t].every(Number.isFinite)))e.quality.push('invalid_numeric');
  if(f.some((p,i)=>i&&(p.t-f[i-1].t<.05||p.t-f[i-1].t>.15)))e.quality.push('timestamp_gap_or_duplicate');
  if(f.some(p=>p.coordinateSpeed>15))e.quality.push('coordinate_jump');
}
for(const e of events.values())prepare(e);
function detect(e,angle=45,window=.5){
  if(e.quality.length)return [];
  const f=e.frames,candidates=[];
  for(let i=2;i<f.length-3;i++){
    let j=i+1;while(j<f.length&&f[j].t-f[i].t<window-.045)j++;
    if(j>=f.length-1||Math.abs(f[j].t-f[i].t-window)>.055)continue;
    if(Math.min(f[i].coordinateSpeed,f[j].coordinateSpeed)<2)continue;
    const net=wrap(f[j].heading-f[i].heading);
    if(Math.abs(deg(net))<angle)continue;
    const steps=f.slice(i+1,j+1).map((p,k)=>wrap(p.heading-f[i+k].heading));
    const total=steps.reduce((s,a)=>s+Math.abs(a),0);
    if(!total||Math.abs(net)/total<.8)continue;
    candidates.push({i,j,angle:deg(net)});
  }
  // Merge overlapping detection windows, keep strongest representative.
  const clusters=[];
  for(const c of candidates){let last=clusters.at(-1);if(last&&c.i<=last.end){last.end=Math.max(last.end,c.j);last.list.push(c);}else clusters.push({start:c.i,end:c.j,list:[c]});}
  return clusters.map(c=>({...c,best:[...c.list].sort((a,b)=>Math.abs(b.angle)-Math.abs(a.angle)||a.i-b.i)[0]}));
}
function features(e,clusters){
  const f=e.frames;
  return clusters.map((cluster,k)=>{
    const {i,j,angle}=cluster.best,start=f[i].t,end=f[j].t;
    // Find the fastest stable 0.3s approach interval in the preceding 1.5s.
    // A window immediately beside the turn can already be deep into braking.
    const baselines=[];
    for(const p of f.filter(p=>p.t>=start-1.5-1e-6&&p.t<=start-.45+1e-6)){
      const b=f.filter(q=>q.t>=p.t-1e-6&&q.t<=p.t+.3+1e-6);
      const m=mean(b.map(q=>q.smooth));
      const variation=m?Math.sqrt(mean(b.map(q=>(q.smooth-m)**2)))/m:Infinity;
      const slope=b.length>1?(b.at(-1).smooth-b[0].smooth)/(b.at(-1).t-b[0].t):Infinity;
      if(b.length>=4&&variation<=.1&&Math.abs(slope)<=2)baselines.push({b,m,variation,slope});
    }
    const chosen=baselines.sort((a,b)=>b.m-a.m)[0];
    const baseline=chosen?.b??f.filter(p=>p.t>=start-.45-1e-6&&p.t<=start-.15+1e-6);
    const entry=mean(baseline.map(p=>p.smooth));
    const cv=entry?Math.sqrt(mean(baseline.map(p=>(p.smooth-entry)**2)))/entry:null;
    const interval=f.filter(p=>p.t>=start-.2-1e-6&&p.t<=end+.2+1e-6);
    const minimum=interval.reduce((a,b)=>a.smooth<=b.smooth?a:b);
    const nextStart=k+1<clusters.length?f[clusters[k+1].start].t-.1:Infinity;
    const stop=Math.min(f.at(-2).t,nextStart); // centered smoothing needs a subsequent frame
    const follow=f.filter(p=>p.t>=minimum.t&&p.t<=stop);
    const recovered=entry&&follow.find(p=>p.smooth>=.9*entry&&f.some(q=>q.t>=p.t+.19&&q.t<=p.t+.21&&q.t<=stop)&&f.filter(q=>q.t>=p.t&&q.t<=p.t+.201).every(q=>q.smooth>=.9*entry));
    const flags=[];
    if(!chosen)flags.push('no_stable_approach_plateau');
    if(baseline.length<3||start<.45)flags.push('short_entry_window');
    if(entry<3)flags.push('low_entry_speed');
    if(cv>.15)flags.push('unstable_entry_speed');
    if(minimum.t>=stop)flags.push('minimum_overlaps_next_cut');
    const loss=entry?(entry-minimum.smooth)/entry:null;
    let status=loss<=.1?'no_material_speed_loss':recovered?'recovered':nextStart<f.at(-2).t?'censored_next_cut':'censored_recording_end';
    const atHalf=follow.find(p=>Math.abs(p.t-minimum.t-.5)<.045);
    const stableEntry=Boolean(chosen)&&baseline.length>=4&&entry>=3&&cv<=.1&&start>=.45;
    return {nfl_id:e.player.nfl_id,name:e.player.display_name,draft_year:e.player.draft_year,event_id:e.event_id,attempt:e.attempt,drill:e.drill,
      cut_index:k+1,turn_start_s:start,turn_end_s:end,angle_deg:angle,cluster_start_s:f[cluster.start].t,cluster_end_s:f[cluster.end].t,
      entry_speed_yd_s:entry,entry_speed_cv:cv,entry_window_start_s:baseline[0]?.t,entry_window_end_s:baseline.at(-1)?.t,
      minimum_speed_yd_s:minimum.smooth,minimum_time_s:minimum.t,
      speed_loss_fraction:loss,recovery_90_s:status==='recovered'?recovered.t-minimum.t:null,recovery_status:status,
      followup_s:Math.max(0,stop-minimum.t),speed_gain_05_yd_s:atHalf?atHalf.smooth-minimum.smooth:null,
      mean_acceleration_05_yd_s2:atHalf?(atHalf.smooth-minimum.smooth)/(atHalf.t-minimum.t):null,
      stable_entry:stableEntry,flags:flags.join(';'),
      feature_candidate:stableEntry&&k===0&&e.drill==='COMEBACK_ROUTE_RIGHT'&&Math.abs(angle)<=135&&stop-minimum.t>=.5?'primary_comeback':stableEntry&&k===0&&e.drill==='CURL_ROUTE_RIGHT'&&clusters.length===2&&Math.abs(angle)<=135&&stop-minimum.t>=.5?'secondary_curl':'review_only',
      // Multi-cut drills are retained for inspection, never silently pooled.
      review_status:'provisional_unreviewed'};
  });
}
// Verify key behavior on synthetic moving trajectories, independently of supplied NFL outcomes.
function synthetic(points){const e={player:{nfl_id:'synthetic',display_name:'synthetic',draft_year:'test'},drill:'COMEBACK_ROUTE_RIGHT',frames:points.map((p,i)=>({x:p[0],y:p[1],s:5,time:i*100}))};prepare(e);return e;}
assert.equal(detect(synthetic(Array.from({length:60},(_,i)=>[i*.5,0]))).length,0);
const rightAngle=synthetic(Array.from({length:60},(_,i)=>i<=25?[i*.5,0]:[12.5,(i-25)*.5]));
assert.equal(detect(rightAngle).length,1);
const rotated=synthetic(rightAngle.frames.map(p=>[-p.y,p.x]));
assert.equal(detect(rotated).length,1);
assert.ok(Math.abs(detect(rightAngle)[0].best.angle-detect(rotated)[0].best.angle)<1e-6);
const broken=synthetic(Array.from({length:60},(_,i)=>[i*.5,0]));broken.frames[30].time+=1000;prepare(broken);assert.equal(detect(broken).length,0);
const truncated=synthetic(Array.from({length:34},(_,i)=>i<=25?[i*.5,0]:[12.5,(i-25)*.5]));
truncated.frames.forEach((p,i)=>p.s=i<23?5:2);prepare(truncated);
const truncatedFeatures=features(truncated,detect(truncated));
assert.equal(truncatedFeatures.length,1);
assert.equal(truncatedFeatures[0].recovery_status,'censored_recording_end');
assert.equal(truncatedFeatures[0].recovery_90_s,null);
const recoveredExample=synthetic(Array.from({length:60},(_,i)=>i<=25?[i*.5,0]:[12.5,(i-25)*.5]));
recoveredExample.frames.forEach((p,i)=>p.s=i<23||i>32?5:2);prepare(recoveredExample);
assert.equal(features(recoveredExample,detect(recoveredExample))[0].recovery_status,'recovered');
const rows=[],eventRows=[],sens=[];
for(const e of events.values()){
  const clusters=detect(e);e.cuts=features(e,clusters);rows.push(...e.cuts);
  eventRows.push({nfl_id:e.player.nfl_id,name:e.player.display_name,draft_year:e.player.draft_year,event_id:e.event_id,attempt:e.attempt,drill:e.drill,frames:e.frames.length,duration_s:e.frames.at(-1).t,cuts:clusters.length,stable_entry_cuts:e.cuts.filter(c=>c.stable_entry).length,quality_flags:e.quality.join(';')});
  for(const angle of [30,45,60])for(const window of [.3,.5,.7])sens.push({drill:e.drill,nfl_id:e.player.nfl_id,angle,window,cuts:detect(e,angle,window).length});
}
function writeCSV(name,rows){const keys=Object.keys(rows[0]||{}),quote=v=>'"'+String(v??'').replaceAll('"','""')+'"';fs.writeFileSync(path.join(out,name),[keys.map(quote).join(','),...rows.map(r=>keys.map(k=>quote(r[k])).join(','))].join('\n'));}
writeCSV('provisional_cut_events.csv',rows);writeCSV('event_cut_coverage.csv',eventRows);
const drills=[...new Set(eventRows.map(r=>r.drill))].sort();
const summary=drills.map(drill=>{const es=eventRows.filter(e=>e.drill===drill),cs=rows.filter(c=>c.drill===drill);return {drill,events:es.length,players:new Set(es.map(e=>e.nfl_id)).size,events_with_cut:es.filter(e=>e.cuts).length,cuts:cs.length,stable_entry_cuts:cs.filter(c=>c.stable_entry).length,median_abs_angle:median(cs.map(c=>Math.abs(c.angle_deg))),median_entry_speed:median(cs.map(c=>c.entry_speed_yd_s)),median_speed_loss:median(cs.map(c=>c.speed_loss_fraction)),recovered:cs.filter(c=>c.recovery_status==='recovered').length,censored:cs.filter(c=>c.recovery_status.startsWith('censored')).length};});
writeCSV('drill_summary.csv',summary);
const candidates=rows.filter(r=>r.feature_candidate!=='review_only');
assert.ok(candidates.every(c=>c.speed_gain_05_yd_s!==null&&c.followup_s>=.5&&c.stable_entry));
assert.ok(rows.every(c=>['2023','2024'].includes(c.draft_year)));
assert.ok(rows.every(c=>c.recovery_90_s===null||(c.recovery_90_s>=0&&c.recovery_90_s<=c.followup_s)));
assert.equal(new Set(rows.map(c=>[c.nfl_id,c.event_id,c.attempt,c.cut_index].join('|'))).size,rows.length);
writeCSV('candidate_player_drill_features.csv',[...new Set(candidates.map(r=>`${r.nfl_id}|${r.drill}`))].map(key=>{
 const cs=candidates.filter(r=>`${r.nfl_id}|${r.drill}`===key),first=cs[0];
 return {nfl_id:first.nfl_id,name:first.name,draft_year:first.draft_year,drill:first.drill,status:'provisional_not_for_ranking',events:cs.length,
   median_entry_speed_yd_s:median(cs.map(c=>c.entry_speed_yd_s)),median_angle_deg:median(cs.map(c=>Math.abs(c.angle_deg))),
   median_speed_loss_fraction:median(cs.map(c=>c.speed_loss_fraction)),median_speed_gain_05_yd_s:median(cs.filter(c=>c.speed_gain_05_yd_s!==null).map(c=>c.speed_gain_05_yd_s)),
   recovered_events:cs.filter(c=>c.recovery_status==='recovered').length,censored_events:cs.filter(c=>c.recovery_status.startsWith('censored')).length,
   median_observed_recovery_90_s:median(cs.filter(c=>c.recovery_90_s!==null).map(c=>c.recovery_90_s)),
   repeated_measurement:cs.length>1};
}));
writeCSV('repeated_attempt_spread.csv',[...new Set(candidates.map(r=>`${r.nfl_id}|${r.drill}`))].flatMap(key=>{
 const cs=candidates.filter(r=>`${r.nfl_id}|${r.drill}`===key);if(cs.length<2)return [];
 const spread=field=>Math.max(...cs.map(c=>c[field]))-Math.min(...cs.map(c=>c[field]));
 return [{nfl_id:cs[0].nfl_id,name:cs[0].name,drill:cs[0].drill,attempts:cs.length,entry_speed_range:spread('entry_speed_yd_s'),angle_range_deg:spread('angle_deg'),speed_loss_fraction_range:spread('speed_loss_fraction'),speed_gain_05_range_yd_s:spread('speed_gain_05_yd_s')}];
}));
writeCSV('detection_sensitivity.csv',drills.flatMap(drill=>[30,45,60].flatMap(angle=>[.3,.5,.7].map(window=>{const s=sens.filter(x=>x.drill===drill&&x.angle===angle&&x.window===window);return {drill,angle,window,events_with_cut:s.filter(x=>x.cuts).length,cuts:s.reduce((n,x)=>n+x.cuts,0)};}))));
// Deterministic examples: median entry-speed event, then low/high cut count extremes.
const examples=[];
for(const drill of drills){
 const es=[...events.values()].filter(e=>e.drill===drill).sort((a,b)=>(median(a.cuts.map(c=>c.entry_speed_yd_s))??0)-(median(b.cuts.map(c=>c.entry_speed_yd_s))??0)||a.key.localeCompare(b.key));
 const picks=[es[Math.floor(es.length/2)],[...es].sort((a,b)=>a.cuts.length-b.cuts.length||a.key.localeCompare(b.key))[0],[...es].sort((a,b)=>b.cuts.length-a.cuts.length||a.key.localeCompare(b.key))[0]];
 for(const year of ['2023','2024']){const ys=es.filter(e=>e.player.draft_year===year);if(ys.length)picks.push(ys[Math.floor(ys.length/2)]);}
 for(const e of new Set(picks))examples.push({key:e.key,name:e.player.display_name,year:e.player.draft_year,drill:e.drill,event_id:e.event_id,frames:e.frames.map(f=>({t:f.t,x:f.x,y:f.y,s:f.s,smooth:f.smooth})),cuts:e.cuts});
}
fs.writeFileSync(path.join(out,'review_examples.json'),JSON.stringify(examples));
fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><meta charset="utf-8"><title>WR cut review</title><style>body{font:16px system-ui;max-width:1400px;margin:24px auto}img{max-width:100%;height:auto}nav a{display:inline-block;margin:8px}</style><h1>Development WR cut review</h1><p>2023–2024 only. Provisional 45-degree / 0.5-second turn detection. Green speed segment: stable approach baseline. Orange: detected turn window. Purple: speed minimum. Dotted green: 90% recovery target. A censored recovery is unknown, not zero. See DRILL_REVIEW.md for review decisions and limitations.</p><nav>${drills.map(d=>`<a href="#${d}">${d}</a>`).join('')}</nav>${drills.map(d=>`<section id="${d}"><h2>${d}</h2><img loading="lazy" src="${d}.png" alt="${d} trajectories and speed curves"></section>`).join('')}`);
fs.writeFileSync(path.join(out,'run_summary.json'),JSON.stringify({players:players.size,events:events.size,cuts:rows.length,examples:examples.length,candidate_events:candidates.length,synthetic_and_output_checks:'passed',development_years:[2023,2024]},null,2));
console.log(JSON.stringify(summary,null,2));
