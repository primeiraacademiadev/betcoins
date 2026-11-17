import {createHmac} from 'node:crypto';

// Ephemeral CI key, shared only by the disposable PostgREST service and tests.
export function token(subject?:string):string {
 const secret=process.env.FINANCIAL_JWT_SECRET;
 if(!secret)throw new Error('Missing ephemeral financial-test JWT key');
 const encode=(value:unknown)=>Buffer.from(JSON.stringify(value)).toString('base64url');
 const body=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:subject?'authenticated':'anon',
  ...(subject?{sub:subject}:{}),aud:'authenticated',exp:Math.floor(Date.now()/1000)+3600});
 return body+'.'+createHmac('sha256',secret).update(body).digest('base64url');
}
