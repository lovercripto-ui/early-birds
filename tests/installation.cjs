const fs=require('fs'),assert=require('assert');
const {PGlite}=require((process.env.EB_TEST_DEPS||'../node_modules')+'/@electric-sql/pglite');
const base=__dirname+'/../backend/',A='00000000-0000-4000-8000-000000000001';
let n=0;
async function test(name,fn){await fn();console.log('PASS',name);n++;}
async function deny(fn){await assert.rejects(fn);}
(async()=>{
 const db=new PGlite();await db.exec(fs.readFileSync(__dirname+'/schema-fixture.sql','utf8'));
 await db.exec(fs.readFileSync(base+'phone.sql','utf8'));
 await db.exec(fs.readFileSync(base+'installation.sql','utf8'));
 await db.query('insert into auth.users values($1,$2)',[A,'owner@example.test']);
 await test('Anon cannot reserve or complete installation',async()=>{await db.exec('set role anon');await deny(()=>db.query('select phone_install_claim()'));await deny(()=>db.query('select phone_install_status()'));await db.exec('reset role');});
 await test('Authenticated cannot use legacy signup workspace shortcut',async()=>{await db.exec('set role authenticated');await deny(()=>db.query("select register_company_workspace('x','x','x','x')"));await db.exec('reset role');});
 await db.exec('set role service_role');
 let claim;
 await test('Empty installation can be reserved once',async()=>{claim=(await db.query('select phone_install_claim() c')).rows[0].c;assert(claim);await deny(()=>db.query('select phone_install_claim()'));});
 await test('Wrong reservation cannot finish',async()=>{await deny(()=>db.query('select phone_install_finish(gen_random_uuid(),$1,$2,$3)',[A,'Owner','Company']));});
 await test('Invalid company cannot create an Admin',async()=>{await deny(()=>db.query('select phone_install_finish($1,$2,$3,$4)',[claim,A,'Owner',null]));});
 await test('Valid finish creates exactly one Admin and saves company',async()=>{await db.query('select phone_install_finish($1,$2,$3,$4)',[claim,A,'Owner','Company']);const status=(await db.query('select phone_install_status() s')).rows[0].s;assert.equal(status.initialized,true);assert.equal(status.company,'Company');});
 await test('Completed installation cannot be claimed or replayed',async()=>{await deny(()=>db.query('select phone_install_claim()'));await deny(()=>db.query('select phone_install_finish($1,$2,$3,$4)',[claim,A,'Owner','Other Company']));});
 await test('Company names are validated',async()=>{await deny(()=>db.query("select phone_company_set('x')"));await db.query("select phone_company_set('New Company')");});
 await db.exec('reset role');
 await test('Setup retains exactly one profile',async()=>assert.equal((await db.query('select count(*)::int n from profiles')).rows[0].n,1));
 await test('Installation secrets are not directly readable',async()=>{await db.exec('set role authenticated');await deny(()=>db.query('select * from eb_phone.installation'));await db.exec('reset role');});
 await db.close();console.log(`PASS: ${n} installation database cases`);
})().catch(e=>{console.error(e);process.exitCode=1;});
