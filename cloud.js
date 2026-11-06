/* Static PWA adapter. Publishable key only; passwords are handled by Supabase Auth. */
'use strict';
window.EBCloud=(()=>{
 const cfg=window.EB_CONFIG||{};
 if(!cfg.supabaseUrl?.startsWith('https://')||!cfg.publishableKey||!window.supabase?.createClient)throw new Error('Cloud configuration/library missing');
 const client=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,storageKey:'early-birds-phone-auth-v3'}});
 let mode='auto',current=null,lastRaw=null,companyCache;
 const failure=(message,status=400)=>Object.assign(new Error(message),{status});
 function check(r){if(r.error){const e=failure(r.error.message,r.error.status||(r.error.code==='42501'?401:400));e.code=r.error.code;if(/fetch|network/i.test(e.message)){e.network=true;e.status=0;}throw e;}return r.data;}
 const rpc=async(n,a)=>check(await client.rpc(n,a));
 const rows=async table=>check(await client.from(table).select('*'))||[];
 const cents=n=>Math.round(Number(n||0)*100), iso=()=>new Date().toISOString();
 const date=s=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Colombo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(s||Date.now()));
 const toNumber=v=>{const s=String(v??'');if(!/^\d+(\.\d{1,2})?$/.test(s)||!Number.isFinite(Number(s))||Number(s)<=0||Number(s)>1e9)throw failure('වලංගු මුදලක් අවශ්‍යයි (දශම 2 දක්වා)');return Number(s);};
 function number(v,lo=0,hi=1e6){const n=Number(v);if(!Number.isInteger(n)||n<lo||n>hi)throw failure('වලංගු පූර්ණ සංඛ්‍යාවක් අවශ්‍යයි');return n;}
 async function user(){const response=await client.auth.getUser();if(response.error&&(/session missing|auth session missing/i.test(response.error.message)||response.error.name==='AuthSessionMissingError'))throw failure('නැවත login වෙන්න',401);const data=check(response);if(!data.user)throw failure('නැවත login වෙන්න',401);current=data.user;return current;}
 async function privatePhotos(state){
  const paths=[...new Set([...state.data.bills,...state.data.days].map(r=>r.photo).filter(Boolean))];
  if(!paths.length)return state;
  const response=await client.storage.from('project-media').createSignedUrls(paths,900);
  const urls=new Map((response.data||[]).filter(r=>r.signedUrl).map(r=>[r.path,r.signedUrl]));
  for(const r of [...state.data.bills,...state.data.days]){r._photoPath=r.photo;r.photo=urls.get(r.photo)||'';}
  return state;
 }
 async function existingState(){
  const names=['profiles','projects','project_assignments','money_requests','transfers','expenses','inventory','inventory_movements','equipment_requests','daily_updates','checkins'];
  const values=await Promise.all(names.map(rows)),raw=Object.fromEntries(names.map((n,i)=>[n,values[i]]));lastRaw=raw;
  const sort=(a,k='created_at')=>a.slice().sort((x,y)=>String(x[k]||'').localeCompare(String(y[k]||'')));
  const users=raw.profiles.map(p=>({id:p.id,name:p.display_name,username:p.id===current.id?current.email:'',role:p.role,active:p.phone_active!==false,mustChange:!!p.phone_must_change}));
  const self=users.find(u=>u.id===current.id);if(!self||!self.active)throw failure('මෙම app එකට active profile එකක් අවශ්‍යයි',403);
  const ad=users.find(u=>u.role==='admin')?.id||'admin';
  const outstanding=new Map();for(const m of raw.inventory_movements){const k=m.project_id+'_'+m.inventory_id,old=outstanding.get(k)||0;outstanding.set(k,old+(m.action==='issue'?m.quantity:-m.quantity));}
  const equipment=[...outstanding].filter(([,q])=>q>0).map(([id,quantity])=>({id,project:id.slice(0,36),item:id.slice(37),quantity,holder:raw.project_assignments.find(a=>a.project_id===id.slice(0,36))?.supervisor_id||''}));
  const bills=sort(raw.expenses).map(b=>({id:b.id,project:b.project_id,user:b.supervisor_id,amount:cents(b.amount),category:b.category,note:b.description,date:date(b.created_at),time:b.created_at,photo:b.bill_path||'',status:b.status}));
  const transfers=sort(raw.transfers).map(t=>({id:t.id,project:t.project_id,from:ad,to:t.supervisor_id,amount:cents(t.amount),status:t.status==='pending_receipt'?'pending':t.status,time:t.created_at,request:t.request_id,note:''}));
  const balances=Object.fromEntries(users.filter(u=>u.role==='supervisor').map(u=>[u.id,transfers.filter(t=>t.to===u.id&&t.status==='received').reduce((s,t)=>s+t.amount,0)-bills.filter(b=>b.user===u.id&&b.status==='approved').reduce((s,b)=>s+b.amount,0)]));
  const attendance=[],opened=new Map();for(const c of sort(raw.checkins,'recorded_at')){const k=c.supervisor_id+'_'+c.project_id;if(c.event_type==='in'){const r={id:c.id,user:c.supervisor_id,project:c.project_id,in:c.recorded_at,out:'',minutes:0,offline:c.offline_record,verification:c.verification_status};attendance.push(r);opened.set(k,r);}else{const r=opened.get(k);if(r){r.out=c.recorded_at;r.minutes=Math.max(0,(Date.parse(r.out)-Date.parse(r.in))/60000);opened.delete(k);}}}
  const projects=sort(raw.projects).map(p=>({id:p.id,name:p.name,location:p.location,start:p.start_date||date(),end:p.end_date||date(),budget:cents(p.budget),progress:p.progress_pct,status:p.status,lat:p.site_lat,lng:p.site_lng,radius:1000,supervisor:raw.project_assignments.find(a=>a.project_id===p.id)?.supervisor_id||''}));
  const data={version:3,revision:0,queueGeneration:'existing-schema-v1',users,projects,bills,transfers,balances,equipment,attendance,
   requests:sort(raw.money_requests).map(r=>({id:r.id,user:r.supervisor_id,project:r.project_id,amount:cents(r.amount),status:r.status,time:r.created_at,note:''})),
   items:raw.inventory.map(i=>({id:i.id,code:i.code,name:i.name,kind:i.category,stock:i.quantity,missing:i.missing_count,damaged:0,total:i.quantity+i.missing_count+equipment.filter(e=>e.item===i.id).reduce((s,e)=>s+e.quantity,0)})),
   stockRequests:sort(raw.equipment_requests).map(r=>({id:r.id,user:r.supervisor_id,project:r.project_id,item:r.inventory_id,quantity:r.quantity,kind:r.action,status:r.status==='accepted'?'approved':r.status,condition:'good',time:r.created_at})),
   days:sort(raw.daily_updates).map(r=>({id:r.id,user:r.supervisor_id,project:r.project_id,workers:r.worker_count,stage:r.work_stage,note:r.notes,photo:r.photo_paths?.[0]||'',progress:null,previousProgress:null,time:r.created_at})),handovers:[],audit:[],adjustments:[]};
  return {user:self,data,serverTime:iso(),driveClientId:cfg.googleClientId||'',cloudMode:'existing'};
 }
 async function state(){try{await user();}catch(e){if(e.status===401&&cfg.installFunction){const r=await client.functions.invoke(cfg.installFunction,{body:{op:'status'}});if(!r.error&&!r.data.initialized&&r.data.setupEnabled)return {setup:true};}throw e;}let result;
  if(mode!=='existing'){
   const r=await client.rpc('phone_state');
   if(r.error){if(r.error.code==='PGRST202'||r.error.code==='42883')mode='existing';else check(r);}
   else{mode='phone';result=r.data;}
  }
  if(mode==='existing')result=await existingState();else {result.driveClientId=cfg.googleClientId||'';result.cloudMode='phone';result.user.username=current.email;}
  if(companyCache===undefined){const w=await client.functions.invoke(cfg.authFunction,{body:{op:'workspace.get'}});companyCache=w.error?'':w.data?.company||'';}result.data.companyName=companyCache;return await privatePhotos(result);
 }
 async function upload(a){
  if(!a.photo||!String(a.photo).startsWith('data:'))return a;
  const m=/^data:(image\/(?:png|jpeg));base64,([A-Za-z0-9+/=]+)$/.exec(a.photo);if(!m)throw failure('JPG/PNG photo එකක් අවශ්‍යයි');
  const bytes=Uint8Array.from(atob(m[2]),c=>c.charCodeAt(0));if(bytes.length>3*1024*1024)throw failure('Photo ≤ 3 MB අවශ්‍යයි');
  const kind=a.op==='bill.add'?'bills':'updates',path=`${a.project}/${current.id}/${kind}/${a.requestId}.${m[1]==='image/png'?'png':'jpg'}`;
  const r=await client.storage.from('project-media').upload(path,bytes,{contentType:m[1],upsert:false,cacheControl:'0'});
  if(r.error){if(String(r.error.statusCode)!=='409'&&!/already exists|duplicate/i.test(r.error.message))check(r);
   const previous=check(await client.storage.from('project-media').download(path));const old=new Uint8Array(await previous.arrayBuffer());
   if(old.length!==bytes.length||old.some((v,i)=>v!==bytes[i]))throw failure('එම photo ID එකේ වෙනත් file එකක් තිබේ',409);
  }
  return {...a,photo:path};
 }
 async function insertOnce(table,payload){const r=await client.from(table).insert(payload);if(!r.error)return;
  if(r.error.code!=='23505')check(r);const existing=check(await client.from(table).select('*').eq('id',payload.id).single());
  if(Object.entries(payload).some(([k,v])=>JSON.stringify(existing[k])!==JSON.stringify(v)))throw failure('Saved request conflicts with new data',409);
 }
 async function existingAction(a){
  const op=a.op,sid=current.id;
  const supported=['money.request','request.decide','money.receive','bill.add','bill.decide','stock.request','stock.return','stock.decide','day.add','attendance','item.add'];
  if(!supported.includes(op))throw failure('මෙම option එක සඳහා reviewed backend update එක activate කළ යුතුයි. දැනට data වෙනස් කර නැහැ.',409);
  if(a.queuedAt&&a.generation!=='existing-schema-v1')throw failure('පැරණි queue එක මුලින් review කරන්න',409);
  if(op==='money.request')await insertOnce('money_requests',{id:a.requestId,project_id:a.project,supervisor_id:sid,amount:toNumber(a.amount),status:'pending'});
  if(op==='request.decide')await rpc('admin_decide_money_request',{p_id:a.id,p_approve:a.approve===true});
  if(op==='money.send'){if(a.request)throw failure('Approved request එකට pending transfer එක දැනටමත් ඇත. නැවත යවන්න එපා.');await rpc('admin_send_money',{p_project:a.project,p_supervisor:a.to,p_amount:toNumber(a.amount)});}
  if(op==='money.receive')await rpc('confirm_transfer_receipt',{p_id:a.id});
  if(op==='bill.add'){
   if(a.date!==date())throw failure('පැරණි expense date එක රැකීමට backend update එක අවශ්‍යයි. අද දිනය පමණක් භාවිතා කරන්න.');
   if(!a.note?.trim())throw failure('විස්තරය අවශ්‍යයි');
   await insertOnce('expenses',{id:a.requestId,project_id:a.project,supervisor_id:sid,amount:toNumber(a.amount),category:a.category,description:a.note,bill_path:a.photo||null,status:'pending'});
  }
  if(op==='bill.decide')await rpc('admin_decide_expense',{p_id:a.id,p_approve:a.approve===true});
  if(op==='stock.request'||op==='stock.return'){
   if(op==='stock.return'&&a.condition!=='good')throw failure('Missing/damaged return සඳහා backend update එක අවශ්‍යයි');
   const parts=(a.id||'').split('_');await insertOnce('equipment_requests',{id:a.requestId,project_id:op==='stock.return'?parts[0]:a.project,supervisor_id:sid,inventory_id:op==='stock.return'?parts[1]:a.item,quantity:number(a.quantity,1),action:op==='stock.return'?'return':'issue',status:'pending'});
  }
  if(op==='stock.decide')await rpc('admin_decide_equipment',{p_id:a.id,p_approve:a.approve===true});
  if(op==='day.add'){
   const project=check(await client.from('projects').select('progress_pct').eq('id',a.project).single());
   if(number(a.progress,0,100)!==project.progress_pct)throw failure('Progress එක atomically වෙනස් කිරීමට backend update එක අවශ්‍යයි. දැනට daily notes/photos පමණක් submit කළ හැකියි.');
   await insertOnce('daily_updates',{id:a.requestId,project_id:a.project,supervisor_id:sid,worker_count:number(a.workers,0,100000),work_stage:a.stage,notes:a.note||'',photo_paths:a.photo?[a.photo]:[]});
  }
  if(op==='attendance')await rpc('submit_attendance',{p_project:a.project,p_event:a.kind,p_recorded_at:a.deviceTime,p_lat:a.lat,p_lng:a.lng,p_accuracy_m:a.accuracy,p_client_event_id:a.requestId,p_offline:!!a.offline});
  if(op==='item.add')await insertOnce('inventory',{id:a.requestId,code:a.code.trim().toUpperCase(),name:a.name.trim(),category:a.kind,quantity:number(a.quantity),condition:'good',missing_count:0});
  return {ok:true,id:a.id||a.requestId};
 }
 async function edge(a){return check(await client.functions.invoke(cfg.authFunction,{body:a}));}
 async function request(path='/api/state',a=null){
  if(path==='/api/state')return state();
  if(path==='/api/backup'){
   const r=await state();if(r.user.role!=='admin')throw failure('Admin only',403);
   const files=[];let size=0;for(const row of [...r.data.bills,...r.data.days]){if(!row._photoPath)continue;const blob=check(await client.storage.from('project-media').download(row._photoPath));size+=blob.size;if(size>20*1024*1024)throw failure('Photo export 20 MB ඉක්මවයි. Project media වෙනම download කරන්න.');const data=await new Promise((resolve,reject)=>{const f=new FileReader();f.onload=()=>resolve(String(f.result).split(',')[1]);f.onerror=()=>reject(f.error);f.readAsDataURL(blob);});files.push({id:row.id,project:row.project,owner:row.user,mime:blob.type,data,path:row._photoPath});}
   return {format:'early-birds-phone-export',version:3,created:iso(),data:r.data,source:lastRaw||null,files,note:'Data export only. Supabase Auth passwords/sessions are not exported. Signed photo links expire; private media bytes are included in files.'};
  }
  if(path!=='/api/action'||!a)throw failure('Unknown endpoint');
  if(a.op==='login'){check(await client.auth.signInWithPassword({email:a.username.trim(),password:a.password}));return {ok:true};}
  if(a.op==='logout'){check(await client.auth.signOut({scope:'local'}));current=null;return {ok:true};}
  if(a.op==='setup'){const r=check(await client.functions.invoke(cfg.installFunction,{body:a}));check(await client.auth.signInWithPassword({email:a.username.trim(),password:a.password}));return r;}
  await user();
  if(['user.add','user.reset','password','user.active','account.email','company.set'].includes(a.op)){
   if(mode!=='phone')throw failure('Account management activate කිරීමට backend update අනුමත කළ යුතුයි',409);
   if(a.op==='user.active'){const snapshot=await state();a={...a,active:!snapshot.data.users.find(u=>u.id===a.id)?.active};}const result=await edge(a);if(a.op==='company.set')companyCache=undefined;if(a.op==='password')await client.auth.signOut({scope:'local'});return result;
  }
  if(['backup.restore','legacy.import'].includes(a.op))throw failure('Cloud data import/restore තවම activate කර නැහැ. Local JSON එකෙන් live database replace නොකෙරේ.',409);
  if(mode==='auto')await state();
  const prepared=await upload(a);
  if(mode==='phone'){
   if(prepared.op==='stock.return'){prepared.equipment=prepared.id;delete prepared.id;}
   return rpc('phone_action',{a:prepared});
  }
  return existingAction(prepared);
 }
 return {request,get mode(){return mode;},get client(){return client;}};
})();
