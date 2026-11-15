import {describe,it,expect,vi} from 'vitest';
import {observeRequest,rankCurrentCompetitors,competitionError} from './competition';
describe('competition UI boundaries',()=>{
 it('does not rank an undeclared legacy zero, but ranks a declared zero and ties',()=>{
  const row=(id:string,ytd:number|null,updated_at:string|null='2026-11-15T00:00:00Z')=>({id,nickname:id,ytd,updated_at});
  expect(rankCurrentCompetitors([row('missing',0,null),row('new',null,null),row('loss',-1),row('A',0),row('B',0)]).map(r=>[r.id,r.place]))
   .toEqual([['A',1],['B',1],['loss',3],['missing',null],['new',null]]);
 });
 it('ignores a late response from a previous period',async()=>{
  let finish!:(value:string)=>void;
  const delivered=vi.fn(),failed=vi.fn();
  const cancel=observeRequest(new Promise<string>(resolve=>{finish=resolve;}),delivered,failed);
  cancel();
  observeRequest(Promise.resolve('current'),delivered,failed);
  finish('old');
  await Promise.resolve();
  expect(delivered.mock.calls).toEqual([['current']]);
  expect(failed).not.toHaveBeenCalled();
 });
 it('ignores a late error after changing account, but delivers current errors',async()=>{
  let fail!:(error:Error)=>void;
  const delivered=vi.fn(),failed=vi.fn();
  const cancel=observeRequest(new Promise<string>((_,reject)=>{fail=reject;}),delivered,failed);
  cancel();fail(new Error('old account'));
  const current=new Error('current request');
  observeRequest(Promise.reject(current),delivered,failed);
  await Promise.resolve();
  expect(failed.mock.calls).toEqual([[current]]);
  expect(delivered).not.toHaveBeenCalled();
 });
 it('maps only known competition errors, without exposing SQL details',()=>{
  expect(competitionError({code:'BC004',detailMessage:'private SQL'})).toContain('apenas para consulta');
  expect(competitionError({code:'99999',detailMessage:'private SQL'})).toBeNull();
 });
});
