'use strict';
(()=>{
 const $=s=>document.querySelector(s),cfg=window.EB_CONFIG;
 const client=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:true}});
 const say=text=>$('#status').textContent=text;
 const check=r=>{if(r.error)throw new Error(r.error.message);return r.data;};
 let verified=false,busy=false;
 function ready(){verified=true;$('#request').hidden=true;$('#verify').hidden=true;$('#change').hidden=false;say('Email තහවුරු වුණා. ඔබටම පමණක් දන්නා අලුත් password එකක් දාන්න.');}
 async function initial(){
  const hash=new URLSearchParams(location.hash.slice(1));
  if(hash.get('type')!=='recovery')return;
  try{const data=check(await client.auth.getSession());if(!data.session)throw new Error('Link එක කල් ඉකුත් වී ඇත. අලුත් reset email එකක් ඉල්ලන්න.');history.replaceState(null,'',location.pathname);ready();}
  catch(e){history.replaceState(null,'',location.pathname);say(e.message);}
 }
 document.addEventListener('submit',async event=>{
  event.preventDefault();if(busy)return;busy=true;const form=event.target,button=form.querySelector('button');button.disabled=true;const data=new FormData(form);
  try{
   if(form.id==='request'){
    check(await client.auth.resetPasswordForEmail(String(data.get('email')).trim(),{redirectTo:new URL('./recover.html',location.href).href}));
    say('Account එකට අදාළ reset email එක ලැබේ නම් Inbox / Spam බලන්න. Link එක Copy කර මේ පිටුවට paste කරන්න.');
   }else if(form.id==='verify'){
    const url=new URL(String(data.get('link')).trim()),own=new URL(cfg.supabaseUrl);
    if(url.origin!==own.origin||url.pathname!=='/auth/v1/verify'||url.searchParams.get('type')!=='recovery'||!url.searchParams.get('token'))throw new Error('මෙම app එකේ password recovery email link එක අවශ්‍යයි.');
    const token=url.searchParams.get('token');form.reset();
    check(await client.auth.verifyOtp({token_hash:token,type:'recovery'}));ready();
   }else if(form.id==='change'){
    if(!verified)throw new Error('මුලින් email link එක තහවුරු කරන්න.');
    const password=String(data.get('password'));if(password.length<10||password.length>256||password!==data.get('confirm'))throw new Error('Passwords දෙක ගැළපිය යුතුයි; අකුරු 10–256 අවශ්‍යයි.');
    check(await client.auth.updateUser({password}));form.reset();
    // Use the existing reauthenticated password operation to invalidate old gateway sessions.
    const stamp=await client.functions.invoke(cfg.authFunction,{body:{op:'password',current:password,password}});
    await client.auth.signOut({scope:'local'});verified=false;form.hidden=true;
    say(stamp.error?'Password save වුණා. App එකට අලුත් password එකෙන් login වෙන්න. පැරණි sessions අවසන් කිරීම තහවුරු නොවුණා.':'Password save වුණා. App එකට ගොස් අලුත් password එකෙන් login වෙන්න.');
   }
  }catch(e){say(e.message||'නැවත උත්සාහ කරන්න.');}finally{busy=false;button.disabled=false;}
 });
 initial();
})();
