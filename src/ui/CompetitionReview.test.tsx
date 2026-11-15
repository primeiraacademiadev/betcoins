import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {CompetitionRows} from './CompetitionReview';
import type {CompetitionReview} from '../lib/competition';
const review:CompetitionReview={
 starts_at:'2026-11-01T00:00:00Z',ends_at:'2026-11-08T00:00:00Z',legacy:false,start_capture:null,
 end_capture:{id:'end',cutoff_at:'2026-11-08T00:00:00Z',captured_at:'2026-11-09T00:00:00Z',captured_by:'admin'},
 validation:null,can_capture_start:false,can_capture_end:false,can_validate:true,
 rows:[{competitor_id:'missing',nickname:'Sem score',start_ytd:null,end_ytd:null,start_declared_at:null,end_declared_at:null,start_source_id:null,end_source_id:null,status:'missing_end',value:null,place:null},
 {competitor_id:'zero',nickname:'Zero declarado',start_ytd:0,end_ytd:0,start_declared_at:'2026-11-01T00:00:00Z',end_declared_at:'2026-11-07T00:00:00Z',start_source_id:1,end_source_id:2,status:'complete',value:0,place:1}]
};
describe('competition review rendering',()=>{
 it('distinguishes captured from validated, and absent scores from real zero',()=>{
  const html=renderToStaticMarkup(<CompetitionRows review={review} isSprint/>);
  expect(html).toContain('aguarda validação');
  expect(html).toContain('Sem classificação: falta declaração até ao fecho');
  expect(html).toContain('Final: —');
  expect(html).toContain('0.0000 pp');
  expect(html).not.toContain('Classificação final validada');
 });
 it('shows the immutable validation note and uses annual percentage units',()=>{
  const html=renderToStaticMarkup(<CompetitionRows review={{...review,validation:{id:'v',validated_at:'2026-11-10T00:00:00Z',validated_by:'admin',note:'Revisto <sem alterar>'}}} isSprint={false}/>);
  expect(html).toContain('Classificação final validada');
  expect(html).toContain('Revisto &lt;sem alterar&gt;');
  expect(html).toContain('0.0000%');
  expect(html).not.toContain('0.0000 pp');
 });
});
