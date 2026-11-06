// Deployment is pending owner approval of backend/phone.sql. No secret belongs in config.js.
import {createClient} from 'npm:@supabase/supabase-js@2.95.0';
const ORIGINS=new Set(['https://lovercripto-ui.github.io','http://localhost:8080','http://127.0.0.1:8080']);
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin')||'';
 const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':ORIGINS.has(origin)?origin:'https://lovercripto-ui.github.io','Vary':'Origin','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'};
 const reply=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers});
 if(origin&&!ORIGINS.has(origin))return reply({error:'Origin denied'},403);
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return reply({error:'POST required'},405);
 try{
  if(Number(req.headers.get('content-length')||0)>8192)return reply({error:'Request too large'},413);
  const body=await req.json(),url=Deno.env.get('SUPABASE_URL')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authorization=req.headers.get('authorization')||'',token=authorization.replace(/^Bearer\s+/i,'');
  if(!token||authorization===token)return reply({error:'Sign in required'},401);
  const service=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const auth=await service.auth.getUser(token);if(auth.error||!auth.data.user)return reply({error:'Invalid session'},401);
  const caller=auth.data.user;
  const profile=await service.from('profiles').select('id,role,phone_active,phone_must_change').eq('id',caller.id).single();
  if(profile.error||!profile.data.phone_active)return reply({error:'Active profile required'},403);
  const check=(r:any)=>{if(r.error)throw r.error;return r.data;};
  const validPassword=(p:unknown)=>{if(typeof p!=='string'||p.length<10||p.length>256)throw new Error('Password must have 10–256 characters');return p;};
  const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  if(body.op==='password'){
   const reauth=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
   const signed=await reauth.auth.signInWithPassword({email:caller.email!,password:String(body.current||'')});
   if(signed.error||signed.data.user?.id!==caller.id)return reply({error:'Current password is incorrect'},403);
   check(await service.auth.admin.updateUserById(caller.id,{password:validPassword(body.password)}));
   check(await service.rpc('phone_auth_stamp',{p_target:caller.id,p_clear_temp:true}));
   await service.auth.admin.signOut(token,'global');if(signed.data.session)await service.auth.admin.signOut(signed.data.session.access_token,'global');
   return reply({ok:true,relogin:true});
  }
  if(profile.data.role!=='admin'||profile.data.phone_must_change)return reply({error:'Admin only'},403);
  if(body.op==='user.add'){
   const email=String(body.username||'').trim().toLowerCase(),name=String(body.name||'').trim();
   if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||!name||name.length>160)throw new Error('Valid email and name required');
   const created=check(await service.auth.admin.createUser({email,password:validPassword(body.password),email_confirm:true}));
   const inserted=await service.from('profiles').insert({id:created.user.id,display_name:name,role:'supervisor',phone_active:true,phone_must_change:true});
   if(inserted.error){await service.auth.admin.deleteUser(created.user.id);throw inserted.error;}
   return reply({ok:true,id:created.user.id});
  }
  const target=check(await service.from('profiles').select('id,role').eq('id',String(body.id)).single());
  if(target.role!=='supervisor')return reply({error:'Supervisor account required'},403);
  if(body.op==='user.reset'){
   check(await service.auth.admin.updateUserById(target.id,{password:validPassword(body.password),ban_duration:'none'}));
   check(await service.from('profiles').update({phone_must_change:true}).eq('id',target.id));
   check(await service.rpc('phone_auth_stamp',{p_target:target.id,p_clear_temp:false}));
   return reply({ok:true});
  }
  if(body.op==='user.active'){
   const result=check(await client.rpc('phone_action',{a:body}));
   check(await service.auth.admin.updateUserById(target.id,{ban_duration:body.active?'none':'876000h'}));
   return reply(result);
  }
  return reply({error:'Unsupported account operation'},400);
 }catch(e){return reply({error:e instanceof Error?e.message:'Account request failed'},400);}
});
