import {test} from '@playwright/test';
import {startOAuth,verifyRedirect,type Provider} from './liveSupport';

for(const provider of ['google','github'] as Provider[]){
 test(`${provider}: published app redirects through real Supabase to the real provider`,async({page})=>{
  verifyRedirect(await startOAuth(page,provider));
 });
}
