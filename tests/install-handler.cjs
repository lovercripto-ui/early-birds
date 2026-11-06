const fs=require('fs'),vm=require('vm'),assert=require('assert');
let handler,initialized=false,token='t'.repeat(40),failFinish=false,committed=false,unknown=false,deleted=0,created=0,n=0;
const source=fs.readFileSync(__dirname+'/../backend/phone-install.ts','utf8').replace(/^import .*;\n/m,'').replace(/req:Request/g,'req').replace(/value:unknown/g,'value').replace(/r:any/g,'r').replace(/\)!/g,')');
const createClient=()=>({rpc:async name=>{
 if(name==='phone_install_status')return {data:{initialized}};
 if(name==='phone_install_claim')return {data:'claim'};
 if(name==='phone_install_finish'){if(failFinish)return {error:new Error('Dropped response')};committed=true;return {data:{}};}
 return {data:{}};
},auth:{admin:{createUser:async()=>{created++;return {data:{user:{id:'new-owner'}}};},deleteUser:async()=>{deleted++;return {data:{}};}}},from:()=>({select(){return this;},eq(){return this;},maybeSingle:async()=>unknown?{error:new Error('Offline')}:{data:committed?{id:'new-owner'}:null}})});
vm.runInNewContext(source,{Deno:{env:{get:k=>k==='EB_INSTALL_TOKEN'?token:k==='EB_APP_ORIGIN'?undefined:'mock'},serve:fn=>handler=fn},createClient,Response,Request,JSON,Error,Number,String});
const valid={op:'setup',setupToken:token,company:'Buyer Company',name:'Buyer',username:'buyer@example.test',password:'Buyer-Password-123',password2:'Buyer-Password-123'};
async function call(body,origin='https://lovercripto-ui.github.io'){return handler(new Request('https://example.test/setup',{method:'POST',headers:{origin},body:JSON.stringify(body)}));}
async function test(name,fn){await fn();console.log('PASS',name);n++;}
(async()=>{
 await test('Wrong origin cannot provision',async()=>assert.equal((await call(valid,'https://evil.test')).status,403));
 await test('Missing installation secret fails closed',async()=>{token='';assert.equal((await call(valid)).status,403);token=valid.setupToken;});
 await test('Wrong installer token cannot create Auth users',async()=>{assert.equal((await call({...valid,setupToken:'wrong'})).status,403);assert.equal(created,0);});
 await test('Existing workspace blocks setup even with correct token',async()=>{initialized=true;assert.equal((await call(valid)).status,409);assert.equal(created,0);initialized=false;});
 await test('Mismatched passwords are blocked before account creation',async()=>{assert.equal((await call({...valid,password2:'Other-password-123'})).status,400);assert.equal(created,0);});
 await test('Failed uncommitted profile creation cleans up Auth user',async()=>{failFinish=true;assert.equal((await call(valid)).status,400);assert.equal(deleted,1);});
 await test('Lost successful commit response never deletes Admin',async()=>{committed=true;const d=deleted;assert.equal((await call(valid)).status,200);assert.equal(deleted,d);});
 await test('Unknown commit outcome preserves account for operator recovery',async()=>{unknown=true;const d=deleted;assert.equal((await call(valid)).status,503);assert.equal(deleted,d);unknown=false;});
 console.log(`PASS: ${n} installation handler cases; no hosted accounts created.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
