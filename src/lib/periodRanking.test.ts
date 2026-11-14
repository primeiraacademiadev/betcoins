import {describe,it,expect} from 'vitest';
import {classifyPeriod,collateralToRefund,type PeriodScore} from './periodRanking';
const score=(id:string,declaredYtd:number,baselineYtd:number|null=0,missedClose=false):PeriodScore=>({
 competitorId:id,nickname:id,declaredYtd,baselineYtd,missedClose
});
describe('classificação de períodos',()=>{
 it('ordena o YTD final sem comparar com o baseline',()=>{
  const r=classifyPeriod([score('A',17,14),score('B',2,-5),score('C',-1,-2)],'ytd');
  expect(r.winners).toEqual({winner:'A',second:'B',last:'C'});
 });
 it('ordena o maior delta YTD do período, em pontos percentuais',()=>{
  const r=classifyPeriod([score('A',17,14),score('B',2,-5),score('C',-1,-2)],'delta');
  expect(r.winners.winner).toBe('B');
  expect(r.winners.second).toBe('A');
  expect(r.rows.find(x=>x.competitorId==='B')?.deltaPp).toBe(7);
 });
 it('anula primeiro e segundo se há empate no primeiro, mas não o último',()=>{
  const r=classifyPeriod([score('A',12),score('B',12),score('C',1)],'ytd');
  expect(r.winners).toEqual({winner:null,second:null,last:'C'});
  expect(r.rows.map(x=>x.place)).toEqual([1,1,3]);
 });
 it('empate no último invalida apenas o último',()=>{
  const r=classifyPeriod([score('A',12),score('B',8),score('C',1),score('D',1)],'ytd');
  expect(r.winners).toEqual({winner:'A',second:'B',last:null});
 });
 it('ausência de declaração de fecho causa penalização local de 1 pp',()=>{
  const a=score('A',12,10,true);
  const r=classifyPeriod([a,score('B',10,8)],'ytd');
  expect(r.rows.find(x=>x.competitorId==='A')?.effectiveYtd).toBe(11);
  expect(a.declaredYtd).toBe(12);
  expect(classifyPeriod([a],'delta').rows[0].deltaPp).toBe(1);
 });
 it('o primeiro valor de um novo concorrente é o seu baseline',()=>{
  const r=classifyPeriod([score('A',15,12),score('B',14,10)],'delta');
  expect(r.rows.find(x=>x.competitorId==='A')?.deltaPp).toBe(3);
 });
 it('recusa delta sem referência de entrada',()=>{
  expect(()=>classifyPeriod([score('A',12,null)],'delta')).toThrow();
 });
 it('não inventa um segundo classificado em empate ao topo',()=>{
  expect(classifyPeriod([score('A',10),score('B',10)],'ytd').winners.second).toBeNull();
 });
});
describe('anulação de mercado',()=>{
 it('restitui apenas a reserva BACK/LAY',()=>{
  expect(collateralToRefund('back',10,2)).toBe(10);
  expect(collateralToRefund('lay',10,2)).toBe(2);
 });
});
