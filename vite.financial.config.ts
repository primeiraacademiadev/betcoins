import {defineConfig,mergeConfig} from 'vite';
import base from './vite.config';
import {token} from './tests/browser/financialTokens';

// Test-only gateway to the local, real PostgREST service. Production never loads
// this config; no JWT signing secret is defined or included in browser code.
export default mergeConfig(base,defineConfig({
 define:{'import.meta.env.VITE_SUPABASE_URL':JSON.stringify('http://127.0.0.1:4174'),
  'import.meta.env.VITE_SUPABASE_ANON_KEY':JSON.stringify(token())},
 server:{proxy:{'/rest/v1':{target:'http://127.0.0.1:54322',rewrite:path=>path.replace(/^\/rest\/v1/,'')}}},
}));
