import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {modeLabel,type MarketClassification} from '../lib/marketModes';
import {ClassificationDetails} from './MarketSettlement';
const base:MarketClassification={status:'validated',mode:'snapshot_delta_previous',unit:'pp',can_validate:false,
 current_capture:{id:'current',cutoff_at:'2026-11-15T16:00:00Z'},previous_capture:{id:'previous',cutoff_at:'2026-11-08T16:00:00Z'},
 validation:{id:'v',note:'Revisão dos dois fechos',validated_at:'2026-11-16T10:00:00Z'},
 rows:[{competitor_id:'a',nickname:'A',end_ytd:16.5,previous_ytd:12,value:4.5,status:'complete',place:1}]};
describe('snapshot market modes',()=>{
 it('labels explicit criteria without deriving them from weekly/annual kind',()=>{
  expect(modeLabel('snapshot_value','weekly')).toContain('fecho (%)');
  expect(modeLabel('snapshot_delta_previous','annual')).toContain('período anterior (pp)');
  expect(modeLabel(null,'weekly')).toContain('Legado');
 });
 it('shows both end snapshots, 12 to 16.5 as 4.5 pp and validation',()=>{
  const html=renderToStaticMarkup(<ClassificationDetails review={base}/>);
  expect(html).toContain('Referência: 12%');expect(html).toContain('Fecho: 16.5%');
  expect(html).toContain('4.5000 pp');expect(html).toContain('Fecho anterior:');
  expect(html).toContain('validada e imutável');
 });
 it('shows snapshot value as 16.5%, without presenting the difference',()=>{
  const html=renderToStaticMarkup(<ClassificationDetails review={{...base,mode:'snapshot_value',unit:'%',previous_capture:null,rows:[{...base.rows[0],previous_ytd:null,value:16.5}]}}/>);
  expect(html).toContain('16.5000 %');expect(html).not.toContain('Referência:');expect(html).not.toContain('4.5000');
 });
 it('keeps a missing previous value distinct from a declared zero',()=>{
  const html=renderToStaticMarkup(<ClassificationDetails review={{...base,validation:null,rows:[{...base.rows[0],previous_ytd:null,value:null,place:null,status:'missing_previous'},{...base.rows[0],competitor_id:'b',previous_ytd:0,value:16.5}]}}/>);
  expect(html).toContain('Referência: sem declaração');expect(html).toContain('Referência: 0%');expect(html).toContain('Sem dados para apuramento');
 });
});
