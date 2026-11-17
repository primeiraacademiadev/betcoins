import {execFileSync} from 'node:child_process';
import {expect,test,type Browser,type BrowserContext,type Locator,type Page} from '@playwright/test';
import {token} from './financialTokens';

export const origin='http://127.0.0.1:4174';
export type Mode='snapshot_value'|'snapshot_delta_previous';
export type MarketFixture={id:string;title:string;definition:string;occurrence:string;outcome:string};
export type Fixture={actors:string[];mode:Mode;trading:MarketFixture;ready:MarketFixture;tie:MarketFixture};
const contexts:BrowserContext[]=[];
const external:string[]=[];
const errors:string[]=[];
export function seed(scenario:'trading'|'uncertain'|'settlement',mode:Mode):Fixture {
 return JSON.parse(execFileSync('/usr/bin/python3',['tests/browser/financial_setup.py','seed',scenario,mode],
  {encoding:'utf8',timeout:60000}));
}
export async function cleanup(){
 for(const [index,context] of contexts.splice(0).entries()){
  const failed=test.info().status!==test.info().expectedStatus;
  if(failed)for(const [pageIndex,page] of context.pages().entries()){
   await page.screenshot({path:test.info().outputPath(`actor-${index}-${pageIndex}.png`),fullPage:true});
  }
  await context.close();
 }
 expect(external.splice(0),'Financial tests must never contact remote services').toEqual([]);
 expect(errors.splice(0),'Unexpected application runtime errors').toEqual([]);
}
export async function actor(browser:Browser,id:string,nickname:string){
 const access=token(id);
 const user={id,aud:'authenticated',role:'authenticated',email:nickname.toLowerCase()+'@test.invalid',
  app_metadata:{provider:'test'},user_metadata:{},identities:[],created_at:'2026-01-01T00:00:00Z'};
 const context=await browser.newContext({baseURL:origin,viewport:test.info().project.use.viewport,
  locale:'pt-PT',timezoneId:'Europe/Lisbon'});contexts.push(context);
 await context.route('**/*',route=>{
  const url=new URL(route.request().url());
  if(url.origin===origin)return route.continue();
  if(!['fonts.googleapis.com','fonts.gstatic.com'].includes(url.hostname))external.push(url.origin);
  return route.abort();
 });
 // Only Auth identity is simulated. Every /rest/v1 read and financial mutation
 // goes through the real JWT-validating PostgREST service to PostgreSQL/RLS.
 await context.route(origin+'/auth/v1/user',route=>route.fulfill({
  status:route.request().headers().authorization==='Bearer '+access?200:401,
  contentType:'application/json',body:JSON.stringify(user),
 }));
 await context.addInitScript(({user,access})=>{
  localStorage.setItem('sb-127-auth-token',JSON.stringify({access_token:access,refresh_token:'unused-test-refresh',
   expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user}));
 },{user,access});
 const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
 await page.goto('/betcoins/');
 await expect(page.locator('.account-link')).toContainText(nickname);
 return {page,id,headers:{Authorization:'Bearer '+access,apikey:token()}};
}
export type Actor=Awaited<ReturnType<typeof actor>>;
export async function rpc(who:Actor,name:string,params:Record<string,unknown>={}){
 return who.page.request.post(origin+'/rest/v1/rpc/'+name,{headers:who.headers,data:params});
}
export async function read(who:Actor,table:string){
 const response=await who.page.request.get(origin+'/rest/v1/'+table,{headers:who.headers});
 expect(response.ok(),await response.text()).toBe(true);return response.json();
}
export async function market(who:Actor,fixture:MarketFixture){
 await who.page.locator('.nav').filter({hasText:'Mercados'}).click();
 await expect(who.page.getByLabel('Bet',{exact:true}).locator(`option[value="${fixture.definition}"]`)).toHaveCount(1);
 await who.page.getByLabel('Bet',{exact:true}).selectOption(fixture.definition);
 await who.page.locator('select[aria-label="Resultado"]').selectOption('winner');
 await expect(who.page.getByRole('heading',{name:fixture.title,exact:true})).toBeVisible();
}
export function panel(page:Page,title:string){
 return page.locator('section.panel').filter({has:page.getByRole('heading',{name:title,exact:true})});
}
export async function confirm(page:Page,button:Locator,contains:string,accept=true){
 let message='';
 page.once('dialog',async dialog=>{message=dialog.message();if(accept)await dialog.accept();else await dialog.dismiss()});
 await button.click();expect(message).toContain(contains);
}
export async function publish(who:Actor,fixture:MarketFixture,side:'back'|'lay',stake=10){
 await market(who,fixture);
 const form=panel(who.page,'Colocar oferta');
 await form.getByRole('combobox',{name:/^Resultado/}).selectOption(fixture.outcome);
 await form.getByRole('combobox',{name:/^Posição/}).selectOption(side);
 await form.getByLabel('Odd decimal').fill('1.20');
 await form.getByLabel('Stake (฿)',{exact:true}).fill(String(stake));
 await confirm(who.page,form.getByRole('button',{name:'Publicar oferta'}),'Publicar oferta '+side.toUpperCase());
 await expect(who.page.getByText('Oferta publicada no mercado.',{exact:true})).toBeVisible();
}
export async function wallet(who:Actor,available:number,reserved:number){
 await who.page.locator('.nav').filter({hasText:'Carteira'}).click();
 for(const [name,value] of [['DISPONÍVEL',available],['RESERVADO',reserved]] as const){
  const stat=who.page.locator('.stat').filter({has:who.page.getByText(name,{exact:true})}).locator('strong');
  await expect.poll(async()=>Number((await stat.innerText()).replace(/[^\d,-]/g,'').replace(',','.'))).toBe(value);
 }
}
export async function refresh(who:Actor){await who.page.getByTitle('Atualizar dados',{exact:true}).click()}
export async function reconcile(admin:Actor){
 const result=await rpc(admin,'reconcile_wallets');expect(result.ok(),await result.text()).toBe(true);
 const rows=await result.json();expect(rows).toHaveLength(4);
 expect(rows.every((row:{balanced:boolean})=>row.balanced)).toBe(true);
 const wallets=await read(admin,'wallets');expect(wallets).toHaveLength(1);
}
export async function mobileFits(page:Page){
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
}
