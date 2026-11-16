import {ScoreAuditDetails} from './FinalDeclarations';
import {useEffect,useState} from 'react';
import {rpc} from '../lib/supabase';
import {classifyError,errorText} from '../lib/uxErrors';
import {observeRequest,competitionError,type CompetitionReview as Review} from '../lib/competition';
import {rankSprintResults,type SprintResult} from '../lib/sprintRanking';

const date=(value:string|null)=>value?new Date(value).toLocaleString('pt-PT'):'Sem declaração';
const score=(value:number|null)=>value===null?'—':Number(value).toFixed(4)+'%';
export function CompetitionRows({review,isSprint}:{review:Review;isSprint:boolean}){
 return <>
  <p className="footnote" role="status">{review.validation?'Classificação final validada':review.end_capture?'Capturada — aguarda validação':'Aguarda captura de fecho'} · Referência: {date(review.ends_at)}</p>
  {review.validation&&<p className="footnote">Validada em {date(review.validation.validated_at)}. Nota: {review.validation.note}</p>}
  {review.start_capture&&<p className="footnote">Snapshot inicial: limite {date(review.start_capture.cutoff_at)} · Capturado em {date(review.start_capture.captured_at)}</p>}
  {review.end_capture&&<p className="footnote">Snapshot final: limite {date(review.end_capture.cutoff_at)} · Capturado em {date(review.end_capture.captured_at)}</p>}
  {review.rows.map(row=><div className="rank-row competition-row" key={row.competitor_id}>
   <span className="rank-number">{row.place===null?'—':row.place+'.'}</span>
   <span className="rank-name">{row.nickname}
    {isSprint&&<small className="movement-date">Inicial: {score(row.start_ytd)} · Declarado: {date(row.start_declared_at)}</small>}
    <small className="movement-date">Final: {score(row.end_ytd)} · Declarado: {date(row.end_declared_at)}</small>
    <ScoreAuditDetails row={row}/>
    {row.status!=='complete'&&<small className="movement-date">Sem classificação: {row.status==='missing_start'?'falta referência inicial (inclui entradas a meio do período)':'falta declaração até ao fecho'}.</small>}
   </span>
   <strong>{row.value===null?'—':Number(row.value).toFixed(4)+(isSprint?' pp':'%')}</strong>
  </div>)}
  {!review.rows.length&&<p className="footnote">Ainda não há dados apurados. Não são usados valores atuais para inventar resultados históricos.</p>}
 </>;
}

// Parent keys this component by account and period, so no old result renders
// even in the interval before the new effect runs.
export function CompetitionReview({championshipId,sprintId=null,isAdmin,revision}:{championshipId:string;sprintId?:string|null;isAdmin:boolean;revision:unknown}){
 const [review,setReview]=useState<Review|null>(null),[error,setError]=useState(''),[unavailable,setUnavailable]=useState(false);
 const [refresh,setRefresh]=useState(0),[busy,setBusy]=useState(false),[note,setNote]=useState(''),[ack,setAck]=useState(false);
 const [legacyRows,setLegacyRows]=useState<SprintResult[]>([]);
 useEffect(()=>{
  setReview(null);setError('');setUnavailable(false);setAck(false);setLegacyRows([]);
  let cancelLegacy=()=>{};
  const legacy=()=>{if(sprintId)cancelLegacy=observeRequest(rpc<SprintResult[]>('get_sprint_rankings',{p_sprint:sprintId}),setLegacyRows,e=>setError(errorText(classifyError(e))));};
  const cancel=observeRequest(rpc<Review>('get_competition_review',{p_championship:championshipId,p_sprint:sprintId}),value=>{
   setReview(value);if(value.legacy)legacy();
  },e=>{
   if((e as {code?:string})?.code==='PGRST202'){setUnavailable(true);legacy();}
   else setError(competitionError(e)||errorText(classifyError(e)));
  });
  return()=>{cancel();cancelLegacy();};
 },[championshipId,sprintId,revision,refresh]);
 async function act(name:string,params:Record<string,unknown>){
  setBusy(true);setError('');
  try{await rpc(name,params);setRefresh(n=>n+1);setAck(false);setNote('');}
  catch(e){setError(competitionError(e)||errorText(classifyError(e)));}
  finally{setBusy(false);}
 }
 const legacy=unavailable||review?.legacy;
 return <div className="competition-review">
  <p className="footnote">{sprintId?'ΔYTD entre início e fim do próprio sprint (pp).':'YTD no fecho anual (%).'} Declarações dos concorrentes, sem verificação por corretora. Empates mantêm o mesmo lugar; esta validação não liquida mercados.</p>
  <button className="button secondary" disabled={busy} onClick={()=>setRefresh(n=>n+1)}>Atualizar apuramento</button>
  {error&&<p className="field-error" role="alert">{error}</p>}
  {legacy?<>
   <p className="warning" role="status">{unavailable?'Apuramento auditado ainda indisponível nesta instalação.':'Snapshots antigos sem proveniência temporal verificável.'} Apenas consulta; não é possível validar esta classificação aqui.</p>
   {legacyRows.length>0&&<><p className="footnote">Pré-visualização antiga, não certificada:</p>{rankSprintResults(legacyRows).map(row=><div className="rank-row" key={row.competitor_id}><span>{row.place}.</span><span>{row.nickname}</span><strong>{Number(row.return_pct).toFixed(4)} pp</strong></div>)}</>}
  </>:review?<>
   <CompetitionRows review={review} isSprint={sprintId!==null}/>
   <p className="footnote">Cada valor provém da última declaração registada até ao limite indicado; consulta a sua data. Ausências ficam sem classificação, sem zero implícito, penalização ou correção retroativa.</p>
   {isAdmin&&!review.validation&&<div className="competition-actions">
    {review.can_capture_start&&<button className="button secondary" disabled={busy} onClick={()=>void act('capture_sprint',{p_sprint:sprintId,p_phase:'start'})}>Capturar referência inicial</button>}
    {review.can_capture_end&&<button className="button secondary" disabled={busy} onClick={()=>void act(sprintId?'capture_sprint':'capture_championship',sprintId?{p_sprint:sprintId,p_phase:'end'}:{p_championship:championshipId})}>Capturar fecho</button>}
    {review.can_validate&&<>
     <label>Nota de validação<textarea maxLength={2000} value={note} onChange={e=>setNote(e.target.value)} placeholder="Regista a revisão das declarações, datas e casos sem classificação."/></label>
     <label className="competition-ack"><input type="checkbox" checked={ack} onChange={e=>setAck(e.target.checked)}/> Revi as datas, os empates e os concorrentes sem classificação. Confirmo o registo final imutável, sem liquidação de apostas.</label>
     <button className="button" disabled={busy||!ack||note.trim().length<10} onClick={()=>void act('validate_competition',{p_championship:championshipId,p_sprint:sprintId,p_note:note.trim()})}>Validar classificação final</button>
    </>}
   </div>}
  </>:!error&&<p className="footnote" role="status">A carregar apuramento…</p>}
 </div>;
}
