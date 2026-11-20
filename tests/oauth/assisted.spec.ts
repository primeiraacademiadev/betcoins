import {test,expect} from '@playwright/test';
import {site,startOAuth,verifyRedirect,type Provider} from './liveSupport';

for(const provider of ['google','github'] as Provider[]){
 test(`${provider}: real identity, callback, persisted session and logout`,async({page})=>{
  test.setTimeout(20*60*1000);
  if(process.env.CI||process.env.OAUTH_ASSISTED!=='1')throw new Error('Run explicitly with a human and dedicated test accounts');
  verifyRedirect(await startOAuth(page,provider));
  console.log(`Concluir ${provider} no navegador com a conta de teste; não enviar credenciais ao terminal. O teste continua ao regressar ao BetCoins.`);
  // Human enters credentials/MFA and reviews provider consent. No automation of
  // passwords, CAPTCHAs, MFA, permission approval or account creation.
  await page.waitForURL(url=>url.origin===new URL(site).origin&&url.pathname==='/betcoins/',{timeout:18*60*1000});
  await expect(page.locator('.account-link')).toBeVisible();
  const callback=new URL(page.url());
  expect(callback.searchParams.has('code')).toBe(false);
  expect(callback.hash.includes('access_token=')).toBe(false);
  await page.reload();
  await expect(page.locator('.account-link')).toBeVisible();
  await page.getByTitle('Gerir a minha conta',{exact:true}).click();
  await expect(page.getByText('Identidades associadas:',{exact:false})).toContainText(provider);
  await page.getByTitle('Sair',{exact:true}).click();
  await expect(page.getByRole('button',{name:'Entrar / criar conta',exact:true})).toBeVisible();
  await expect(page.locator('.account-link')).toHaveCount(0);
  await expect(page.locator('.nav').filter({hasText:'Gestão'})).toHaveCount(0);
  await page.locator('.nav').filter({hasText:'Carteira'}).click();
  await expect(page.locator('.position')).toHaveCount(0);
  await expect(page.getByText('Ainda sem movimentos registados.',{exact:true})).toBeVisible();
  await page.reload();
  await expect(page.getByRole('button',{name:'Entrar / criar conta',exact:true})).toBeVisible();
 });
}
