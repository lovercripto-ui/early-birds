import {createClient} from 'npm:@supabase/supabase-js@2.95.0';
// Set EB_INSTALL_TOKEN (32+ random characters) only on a fresh buyer's project.
// This deployment has existing profiles and can never be claimed through setup.
Deno.serve(async(req:Request)=>{
 const allowed=(Deno.env.get('EB_APP_ORIGIN')||'https://lovercripto-ui.github.io');
 const origin=req.headers.get('origin')||'';
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin','Access-Control-Allow-Origin':allowed,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
 const reply=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers});
 if(origin&&origin!==allowed)return reply({error:'Origin denied'},403);
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return reply({error:'POST required'},405);
 const service=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const check=(r:any)=>{if(r.error)throw r.error;return r.data;};
 let claim='',created='';
 try{
  const text=await req.text();if(text.length>8192)return reply({error:'Request too large'},413);
  const body=JSON.parse(text),status=check(await service.rpc('phone_install_status'));
  const token=Deno.env.get('EB_INSTALL_TOKEN')||'';
  if(body.op==='status')return reply({initialized:status.initialized,setupEnabled:!status.initialized&&token.length>=32});
  if(body.op!=='setup')return reply({error:'Unsupported operation'},400);
  if(status.initialized)return reply({error:'Workspace already initialized. Sign in with the existing account.'},409);
  if(token.length<32||typeof body.setupToken!=='string'||body.setupToken!==token)return reply({error:'Valid installation token required'},403);
  const email=String(body.username||'').trim().toLowerCase(),name=String(body.name||'').trim(),company=String(body.company||'').trim();
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||name.length<2||name.length>120||company.length<2||company.length>160)throw new Error('Valid company, Admin name and real email required');
  if(typeof body.password!=='string'||body.password.length<10||body.password.length>256||body.password!==body.password2)throw new Error('Matching passwords of 10–256 characters required');
  claim=check(await service.rpc('phone_install_claim'));
  const result=check(await service.auth.admin.createUser({email,password:body.password,email_confirm:true}));created=result.user.id;
  check(await service.rpc('phone_install_finish',{p_claim:claim,p_user:created,p_name:name,p_company:company}));
  // Mark committed before returning. Never delete an account after successful commit.
  created='';claim='';return reply({ok:true});
 }catch(e){
  if(created){
   // A dropped HTTP response may hide a successful database commit. Never
   // delete a committed Admin or release a claim when its outcome is unknown.
   const profile=await service.from('profiles').select('id').eq('id',created).maybeSingle();
   if(profile.error)return reply({error:'Setup outcome could not be confirmed. Contact the installation owner before retrying.'},503);
   if(profile.data)return reply({ok:true});
   const removed=await service.auth.admin.deleteUser(created);
   if(removed.error)return reply({error:'Setup cleanup needs installation owner assistance.'},503);
  }
  if(claim)await service.rpc('phone_install_release',{p_claim:claim});
  return reply({error:e instanceof Error?e.message:'Setup failed'},400);
 }
});
