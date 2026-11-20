import {test,expect} from '@playwright/test';
import {actor,cleanup,confirm,market,origin,publish,refresh,seed,wallet,type Mode} from './financialSupport';

test.afterEach(cleanup);
for(const mode of ['snapshot_value','snapshot_delta_previous'] as Mode[]){
 test(`${mode}: logout clears private data and ignores a previous session response`,async({browser})=>{
  const fixture=seed('trading',mode);
  const owner=await actor(browser,fixture.actors[0],'Ana');
  const other=await actor(browser,fixture.actors[1],'Bruno');
  await publish(owner,fixture.trading,'back',5);
  await market(other,fixture.trading);await refresh(other);
  await confirm(other.page,other.page.locator('.offer-explained').getByRole('button',{name:'Aceitar',exact:true}),'A tua posição: LAY');
  await expect(other.page.getByText('Oferta aceite; posição criada.',{exact:true})).toBeVisible();
  await refresh(owner);await wallet(owner,995,5);
  await expect(owner.page.locator('.position')).toHaveCount(1);
  let release=()=>{},arrived=()=>{},delivered=()=>{};
  const waiting=new Promise<void>(resolve=>{release=resolve});
  const ready=new Promise<void>(resolve=>{arrived=resolve});
  const completed=new Promise<void>(resolve=>{delivered=resolve});
  // Real old-identity RPC response, held until after logout; no financial mock.
  await owner.page.route('**/rest/v1/rpc/get_wallet',async route=>{
   const response=await route.fetch();expect(response.ok()).toBe(true);
   arrived();await waiting;await route.fulfill({response});delivered();
  });
  // This local contract test controls Auth identity only. It is distinct from
  // live OAuth preflight/assisted suites, which do not intercept any endpoint.
  await owner.page.context().route(origin+'/auth/v1/logout*',route=>route.fulfill({status:204}));
  await refresh(owner);await ready;
  await owner.page.getByTitle('Sair',{exact:true}).click();
  await expect(owner.page.getByRole('button',{name:'Entrar / criar conta',exact:true})).toBeVisible();
  release();await completed;
  await owner.page.unroute('**/rest/v1/rpc/get_wallet');
  await expect(owner.page.locator('.account-link')).toHaveCount(0);
  await expect(owner.page.locator('.nav').filter({hasText:'Gestão'})).toHaveCount(0);
  await owner.page.locator('.nav').filter({hasText:'Carteira'}).click();
  await expect(owner.page.locator('.position')).toHaveCount(0);
  await expect(owner.page.getByText('Ainda não tens posições.',{exact:true})).toBeVisible();
  await expect(owner.page.getByText('Ainda sem movimentos registados.',{exact:true})).toBeVisible();
  await expect(owner.page.locator('.stat').first().locator('strong')).toHaveText('—');
  await owner.page.reload();
  await expect(owner.page.getByRole('button',{name:'Entrar / criar conta',exact:true})).toBeVisible();
  await expect(owner.page.locator('.account-link')).toHaveCount(0);
 });
}
