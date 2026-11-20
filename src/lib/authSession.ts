import type {AuthChangeEvent,User} from '@supabase/supabase-js';

type Snapshot={user:User}|null;
export type AuthSource={
 getUser:()=>Promise<{data:{user:User|null}}>;
 onAuthStateChange:(callback:(event:AuthChangeEvent,session:Snapshot)=>void)=>{
  data:{subscription:{unsubscribe:()=>void}};
 };
};

export function observeVerifiedSession(auth:AuthSource,onUser:(user:User|null)=>void,
 enqueue:(work:()=>void)=>void=queueMicrotask):()=>void {
 let active=true,revision=0,shown:string|null=null;
 const publish=(user:User|null)=>{shown=user?.id||null;onUser(user)};
 const verify=()=>{
  const request=++revision;
  void auth.getUser().then(({data})=>{
   if(active&&request===revision)publish(data.user);
  }).catch(()=>{if(active&&request===revision)publish(null)});
 };
 verify();
 const {data:{subscription}}=auth.onAuthStateChange((event,session)=>{
  if(!active||event==='INITIAL_SESSION')return;
  revision++;
  if(!session){publish(null);return;}
  if(shown!==session.user.id)publish(null);
  // Run outside the SDK's Auth callback/lock; verify rather than trust cache.
  enqueue(()=>{if(active)verify()});
 });
 return()=>{active=false;revision++;subscription.unsubscribe()};
}
