import {describe,it,expect,vi} from 'vitest';
import type {AuthChangeEvent,User} from '@supabase/supabase-js';
import {observeVerifiedSession,type AuthSource} from './authSession';

const a={id:'a'} as User,b={id:'b'} as User;
function fixture(){
 const requests:Array<{resolve:(user:User|null)=>void;reject:()=>void}>=[];
 const jobs:Array<()=>void>=[];
 const users:Array<User|null>=[];
 let emit:Parameters<AuthSource['onAuthStateChange']>[0]=()=>{};
 const unsubscribe=vi.fn();
 const source:AuthSource={
  getUser:vi.fn(()=>new Promise<{data:{user:User|null}}>((resolve,reject)=>{
   requests.push({resolve:user=>resolve({data:{user}}),reject:()=>reject(new Error('unavailable'))});
  })),
  onAuthStateChange:callback=>{emit=callback;return {data:{subscription:{unsubscribe}}}},
 };
 const stop=observeVerifiedSession(source,user=>users.push(user),job=>jobs.push(job));
 return {requests,jobs,users,stop,source,unsubscribe,
  event:(event:AuthChangeEvent,user:User|null)=>emit(event,user?{user}:null)};
}
const flush=async()=>{await Promise.resolve();await Promise.resolve()};
describe('verified identity and Auth event ordering',()=>{
 it('does not turn a cached initial identity into a verified login',async()=>{
  const f=fixture();f.event('INITIAL_SESSION',a);
  expect(f.users).toEqual([]);
  f.requests[0].resolve(null);await flush();expect(f.users).toEqual([null]);
 });
 it('does not restore a user when an earlier verification returns after logout',async()=>{
  const f=fixture();f.event('SIGNED_OUT',null);
  f.requests[0].resolve(a);await flush();expect(f.users).toEqual([null]);
 });
 it('verifies a new sign-in outside the callback and ignores the older identity',async()=>{
  const f=fixture();f.event('SIGNED_IN',b);
  expect(f.requests).toHaveLength(1);f.jobs.shift()!();
  f.requests[0].resolve(a);await flush();expect(f.users).toEqual([null]);
  f.requests[1].resolve(b);await flush();expect(f.users).toEqual([null,b]);
 });
 it('clears the previous identity immediately while verifying a different account',async()=>{
  const f=fixture();f.requests[0].resolve(a);await flush();
  f.event('SIGNED_IN',b);expect(f.users).toEqual([a,null]);
  f.jobs.shift()!();f.requests[1].resolve(b);await flush();expect(f.users).toEqual([a,null,b]);
 });
 it('does not publish late results or start queued verification after disposal',async()=>{
  const f=fixture();f.event('TOKEN_REFRESHED',a);f.stop();
  f.jobs.shift()!();f.requests[0].resolve(a);await flush();
  expect(f.users).toEqual([null]);expect(f.source.getUser).toHaveBeenCalledTimes(1);
  expect(f.unsubscribe).toHaveBeenCalledTimes(1);
 });
 it('clears identity on failed server verification',async()=>{
  const f=fixture();f.requests[0].reject();await flush();expect(f.users).toEqual([null]);
 });
});
