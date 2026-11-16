import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {EntrySummary,EntryReferenceDetails} from './EntryBaselines';
import type {EntryBaseline} from '../lib/entryBaselines';
const entry:EntryBaseline={championship_id:'c',name:'2026',admitted_at:'2026-11-18T10:00Z',baseline_id:null,ytd:null,effective_at:null,source_kind:null,status:'awaiting_initial'};
describe('initial baseline and partial-period presentation',()=>{
 it('distinguishes approval from effective participation without inventing zero',()=>{
  const html=renderToStaticMarkup(<EntrySummary entry={entry}/>);
  expect(html).toContain('Admitido — aguarda YTD inicial');expect(html).not.toContain('0.0000%');
 });
 it('shows a declared zero and the effective entry date as an immutable initial value',()=>{
  const html=renderToStaticMarkup(<EntrySummary entry={{...entry,baseline_id:'b',ytd:0,effective_at:'2026-11-18T12:00Z',status:'active'}}/>);
  expect(html).toContain('0.0000%');expect(html).toContain('Participação ativa');expect(html).toContain('YTD inicial imutável');
 });
 it('identifies partial windows instead of implying full-period comparison',()=>{
  const html=renderToStaticMarkup(<EntryReferenceDetails row={{reference_kind:'entry_baseline',reference_at:'2026-11-18T12:00Z',participation_status:'active'}}/>);
  expect(html).toContain('janela parcial');expect(html).toContain('datas de referência diferentes');
 });
 it('uses the previous close for later periods and does not label it as entry baseline',()=>{
  const html=renderToStaticMarkup(<EntryReferenceDetails row={{reference_kind:'previous_snapshot',reference_at:'2026-11-20T21:00Z',participation_status:'active'}}/>);
  expect(html).toContain('fecho do período anterior');expect(html).not.toContain('janela parcial');
 });
});
