import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'tests/browser',fullyParallel:true,retries:0,use:{baseURL:'http://127.0.0.1:4173/betcoins/',locale:'pt-PT',timezoneId:'Europe/Lisbon'},webServer:{command:'npm run dev -- --host 127.0.0.1 --port 4173 --strictPort',url:'http://127.0.0.1:4173/betcoins/',reuseExistingServer:!process.env.CI}});
