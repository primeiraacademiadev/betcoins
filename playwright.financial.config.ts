import {defineConfig} from '@playwright/test';
export default defineConfig({
 testDir:'tests/browser',testMatch:'financial.spec.ts',workers:1,fullyParallel:false,retries:0,maxFailures:3,
 timeout:90000,expect:{timeout:10000},
 projects:[{name:'financial-desktop',use:{viewport:{width:1280,height:900}}},
  {name:'financial-mobile',use:{viewport:{width:390,height:844}}}],
 use:{baseURL:'http://127.0.0.1:4174/betcoins/',locale:'pt-PT',timezoneId:'Europe/Lisbon',
  trace:'retain-on-failure',screenshot:'only-on-failure'},
 webServer:{command:'npm run dev -- --config vite.financial.config.ts --host 127.0.0.1 --port 4174 --strictPort',
  url:'http://127.0.0.1:4174/betcoins/',reuseExistingServer:false},
});
