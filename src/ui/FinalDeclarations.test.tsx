import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {ScoreAuditDetails,PendingFinalSummary} from './FinalDeclarations';
import {validFinalYtd,finalDeadlineLabel,type PendingFinal} from '../lib/finalDeclarations';
const round:PendingFinal={id:'r',championship_id:'c',cutoff_at:'2026-11-20T21:00Z',deadline_at:null,periods:['Semana 47','Mês 11'],expired:false};
describe('mandatory final declarations',()=>{
 it('explains one declaration for coincident periods and chronological priority',()=>{
  const html=renderToStaticMarkup(<PendingFinalSummary round={round} first={false}/>);
  expect(html).toContain('Semana 47');expect(html).toContain('Mês 11');expect(html).toContain('mais antigo');expect(html).toContain('Sem prazo fixado');
 });
 it('distinguishes expired deadlines from an open administrative window',()=>{
  expect(finalDeadlineLabel({...round,deadline_at:'2026-11-21T10:00Z',expired:true})).toContain('Prazo encerrado');
  expect(finalDeadlineLabel(round)).toContain('gestão encerrar');
 });
 it('accepts actual zero and -100 but rejects invalid or overprecise YTD',()=>{
  for(const v of ['0','-100','16.5001'])expect(validFinalYtd(v)).toBe(true);
  for(const v of ['','NaN','Infinity','-101','100001','12.12345'])expect(validFinalYtd(v)).toBe(false);
 });
 it('shows original 12, local -1 and effective 11 without relabelling the original',()=>{
  const html=renderToStaticMarkup(<ScoreAuditDetails row={{declared_ytd:12,end_ytd:11,penalty_pp:1,score_origin:'missing_final'}}/>);
  expect(html).toContain('Fecho não declarado / penalizado');expect(html).toContain('Original 12.0000%');expect(html).toContain('−1 pp');expect(html).toContain('Efetivo 11.0000%');expect(html).toContain('apenas a este fecho');
 });
 it('does not invent a zero or penalty for someone without a first declaration',()=>{
  const html=renderToStaticMarkup(<ScoreAuditDetails row={{score_origin:'missing_baseline',end_ytd:null,penalty_pp:0}}/>);
  expect(html).toContain('Sem YTD conhecido');expect(html).not.toContain('0.0000');expect(html).not.toContain('−1');
 });
});
