import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {OccurrencePicker} from '../ui/RecurringBets';
import {occurrenceStatus,marketsForOccurrence,type BetOccurrence,type BetDefinition} from './recurringBets';
import type {Market} from './domain';
const o:BetOccurrence={id:'o',championship_id:'c',kind:'weekly',period_key:'2026-W47',name:'Semana 47',starts_at:'2026-11-13T21:00:00Z',ends_at:'2026-11-20T21:00:00Z',sprint_id:'s',previous_occurrence_id:'p'};
const m:Market={id:'m',title:'Mercado',kind:'weekly',category:'winner',closes_at:o.ends_at,state:'open',definition_id:'d',occurrence_id:'o',mode:'snapshot_value'};
describe('recurring calendar navigation',()=>{
 it('distinguishes future, current, pending, settled and unavailable history',()=>{
  expect(occurrenceStatus(o,[m],Date.parse('2026-11-12'))).toBe('Futura');
  expect(occurrenceStatus(o,[m],Date.parse('2026-11-16'))).toBe('Em curso');
  expect(occurrenceStatus(o,[m],Date.parse('2026-11-21'))).toBe('Em apuramento');
  expect(occurrenceStatus(o,[{...m,state:'settled'}])).toBe('Liquidada');
  expect(occurrenceStatus(o,[],Date.parse('2026-11-21'))).toContain('sem mercados');
 });
 it('never falls back to a different occurrence when history has no markets',()=>{
  expect(marketsForOccurrence([m],'d','missing')).toEqual([]);
  expect(marketsForOccurrence([m],'other','o')).toEqual([]);
  expect(marketsForOccurrence([m,{...m,id:'legacy',definition_id:null}],'','')).toHaveLength(1);
 });
 it('shows mode, dates and changing-universe notice without requiring competitor selection',()=>{
  const d:BetDefinition={id:'d',championship_id:'c',kind:'weekly',mode:'snapshot_delta_previous',active:true};
  const html=renderToStaticMarkup(<OccurrencePicker definitions={[d]} occurrences={[o]} markets={[m]} definition="d" occurrence="o" onSelect={()=>{}}/>);
  expect(html).toContain('período anterior');expect(html).toContain('universo de resultados pode aumentar');
  expect(html).toContain('Fecho:');expect(html).toContain('Períodos passados são apenas consultáveis');
  expect(html).not.toContain('multiple');
 });
});
