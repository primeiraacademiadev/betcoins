import {defineConfig} from '@playwright/test';
export default defineConfig({
 testDir:'tests/oauth',testMatch:'preflight.spec.ts',workers:1,retries:0,timeout:60000,
 projects:[{name:'oauth-desktop',use:{viewport:{width:1280,height:900}}},
  {name:'oauth-mobile',use:{viewport:{width:390,height:844}}}],
 // No storage state, traces, videos, screenshots, real account credentials or
 // network interception. This checks redirects, never claims completed login.
 use:{locale:'pt-PT',timezoneId:'Europe/Lisbon',trace:'off',screenshot:'off',video:'off',actionTimeout:15000},
});
