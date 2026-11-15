import {describe,it,expect} from 'vitest';
import {rankSprintResults,type SprintResult} from './sprintRanking';
const row=(id:string,delta:number):SprintResult=>({
 competitor_id:id,nickname:id,start_ytd:12,end_ytd:12+delta,return_pct:delta
});
describe('existing sprint ranking presentation',()=>{
 it('shares competition ranks for ties without inventing a second place',()=>{
  expect(rankSprintResults([row('C',1),row('B',4.5),row('A',4.5)]).map(r=>[r.competitor_id,r.place]))
   .toEqual([['A',1],['B',1],['C',3]]);
 });
 it('orders negative deltas and shares last place',()=>{
  expect(rankSprintResults([row('B',-3),row('A',-1),row('C',-3)]).map(r=>r.place)).toEqual([1,2,2]);
 });
 it('does not turn distinct four-decimal deltas into ties through display rounding',()=>{
  expect(rankSprintResults([row('A',1.0001),row('B',1.0002)]).map(r=>[r.competitor_id,r.place]))
   .toEqual([['B',1],['A',2]]);
 });
 it('preserves snapshots and source order, and handles an empty ranking',()=>{
  const rows=[row('B',1),row('A',4.5)];
  const before=structuredClone(rows);
  expect(rankSprintResults(rows)[0]).toMatchObject({start_ytd:12,end_ytd:16.5,return_pct:4.5});
  expect(rows).toEqual(before);
  expect(rankSprintResults([])).toEqual([]);
 });
});
