import {defineConfig} from '@playwright/test';
export default defineConfig({
 testDir:'tests/oauth',testMatch:'assisted.spec.ts',workers:1,retries:0,reporter:'dot',
 use:{headless:false,viewport:{width:1280,height:900},locale:'pt-PT',
  timezoneId:'Europe/Lisbon',trace:'off',screenshot:'off',video:'off',actionTimeout:15000},
});
