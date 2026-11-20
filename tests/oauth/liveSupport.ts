import {expect,type Page} from '@playwright/test';

export const site='https://primeiraacademiadev.github.io/betcoins/';
export const authHost='shpasqeliognfeltltwb.supabase.co';
export type Provider='google'|'github';

// Only public protocol properties are retained. Never return state, auth codes,
// access/refresh tokens, personal identifiers or full callback URLs to reports.
export type RedirectEvidence={authorize:boolean;redirect:boolean;code:boolean;state:boolean;callback:boolean};
export async function startOAuth(page:Page,provider:Provider):Promise<RedirectEvidence>{
 const evidence:RedirectEvidence={authorize:false,redirect:false,code:false,state:false,callback:false};
 page.on('request',request=>{
  const url=new URL(request.url());
  if(url.hostname===authHost&&url.pathname==='/auth/v1/authorize'){
   evidence.authorize=url.searchParams.get('provider')===provider;
   evidence.redirect=url.searchParams.get('redirect_to')===site;
  }
  const providerHost=provider==='google'?'accounts.google.com':'github.com';
  if(url.hostname!==providerHost)return;
  // GitHub can embed the OAuth authorization parameters in return_to on login.
  const nested=url.searchParams.get('return_to');
  const parameters=nested?new URL(nested,'https://github.com').searchParams:url.searchParams;
  if(!parameters.has('client_id'))return;
  evidence.code ||= parameters.get('response_type')==='code';
  evidence.state ||= Boolean(parameters.get('state'));
  evidence.callback ||= parameters.get('redirect_uri')===`https://${authHost}/auth/v1/callback`;
 });
 await page.goto(site);
 await page.getByRole('button',{name:'Entrar / criar conta',exact:true}).click();
 await page.getByRole('button',{name:provider==='google'?'Continuar com Google':'Continuar com GitHub',exact:true}).click();
 await expect.poll(()=>new URL(page.url()).hostname,{timeout:45000}).toBe(provider==='google'?'accounts.google.com':'github.com');
 return evidence;
}

export function verifyRedirect(evidence:RedirectEvidence){
 expect(evidence).toEqual({authorize:true,redirect:true,code:true,state:true,callback:true});
}
