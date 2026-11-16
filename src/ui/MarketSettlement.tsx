import {ScoreAuditDetails} from './FinalDeclarations';
import {useEffect,useState} from 'react';
import type {Market} from '../lib/domain';
import {rpc} from '../lib/supabase';
import {observeRequest} from '../lib/competition';
import {modeLabel,type MarketClassification} from '../lib/marketModes';

export type Resolution={status:string;validation_id?:string;winner_outcome_id?:string;criterion?:string};
export function resolutionMessage(status:string):string {
 const messages:Record<string,string>={
  ready:'Classificação validada. O resultado é determinado pelos dados congelados.',
  settled:'Mercado liquidado.',
  unlinked:'Mercado antigo sem período associado. A liquidação exige reconciliação própria.',
  awaiting_validation:'Aguarda captura e validação final da classificação.',
  waiting_current_snapshot:'Aguarda o snapshot de fecho deste período.',
  waiting_previous_snapshot:'Aguarda o snapshot de fecho do período anterior. Não se assume zero nem se usa o início do sprint.',
  incomplete:'Existem concorrentes sem dados completos. Não é possível apurar o resultado.',
  universe_changed:'Os participantes do mercado diferem da classificação. É necessária revisão da elegibilidade.',
  period_mismatch:'O fecho do mercado não corresponde ao snapshot validado. É necessária revisão.',
  tie_unsupported:'Empate relevante: liquidação bloqueada. A regra de zero ainda não tem suporte financeiro.',
 };
 return messages[status]??'Apuramento indisponível. Atualiza os dados antes de tentar novamente.';
}
export function ResolutionDetails({result,winner}:{result:Resolution;winner?:string}){
 return <><p className="footnote" role="status">{resolutionMessage(result.status)}</p>
  {result.status==='ready'&&<p>Resultado validado: <strong>{winner}</strong></p>}
  {result.criterion&&<p className="footnote">Critério: {modeLabel(result.criterion,result.criterion==='annual_ytd'?'annual':undefined)}.</p>}</>;
}
export function ClassificationDetails({review}:{review:MarketClassification}){
 return <><p className="footnote">{review.validation?'Classificação validada e imutável':'Classificação por validar'} · {modeLabel(review.mode)}</p>
  {review.current_capture&&<p className="footnote">Fecho atual: {new Date(review.current_capture.cutoff_at).toLocaleString('pt-PT')}</p>}
  {review.previous_capture&&<p className="footnote">Fecho anterior: {new Date(review.previous_capture.cutoff_at).toLocaleString('pt-PT')}</p>}
  {review.rows.map(row=><div className="rank-row" key={row.competitor_id}><span>{row.place??'—'} · {row.nickname}<small className="movement-date">Fecho: {row.end_ytd===null?'sem declaração':row.end_ytd+'%'}{review.mode==='snapshot_delta_previous'&&' · Anterior: '+(row.previous_ytd===null?'sem declaração':row.previous_ytd+'%')}</small><ScoreAuditDetails row={row}/></span><strong>{row.status==='complete'&&row.value!==null?Number(row.value).toFixed(4)+' '+review.unit:'Sem dados para apuramento'}</strong></div>)}
  {review.validation&&<p className="footnote">Nota de validação: {review.validation.note}</p>}</>;
}
export function MarketSettlement({market,outcomeLabels,busy,onSettle,onValidate}:{market:Market;outcomeLabels:Record<string,string>;busy:boolean;onSettle:(winner:string)=>void;onValidate?:(note:string)=>Promise<void>}){
 const [result,setResult]=useState<Resolution|null>(null),[revision,setRevision]=useState(0),[failed,setFailed]=useState(false);
 const [review,setReview]=useState<MarketClassification|null>(null),[note,setNote]=useState(''),[confirmed,setConfirmed]=useState(false);
 useEffect(()=>{
  setResult(null);setFailed(false);
  return observeRequest(rpc<Resolution>('get_market_resolution',{p_market:market.id}),setResult,()=>setFailed(true));
 },[market.id,revision]);
 useEffect(()=>{
  setReview(null);setNote('');setConfirmed(false);
  if(!market.mode)return;
  return observeRequest(rpc<MarketClassification>('get_market_classification',{p_market:market.id}),setReview,()=>setFailed(true));
 },[market.id,market.mode,revision]);
 const winner=result?.winner_outcome_id;
 return <div className="panel"><h3>{market.title}</h3>
  <p className="footnote">Fecho: {new Date(market.closes_at).toLocaleString('pt-PT')}</p>
  {result?<ResolutionDetails result={result} winner={winner?outcomeLabels[winner]:undefined}/>:<p role="status">{failed?'Apuramento indisponível até à atualização da base de dados ou da ligação.':'A consultar o apuramento…'}</p>}
  {review&&<ClassificationDetails review={review}/>}
  {review?.can_validate&&onValidate&&<div><label>Nota da revisão<textarea value={note} maxLength={2000} onChange={e=>setNote(e.target.value)}/></label><label><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/> Revi o critério, os snapshots e os resultados.</label><button className="button" disabled={busy||!confirmed||note.trim().length<10} onClick={()=>void onValidate(note.trim()).then(()=>setRevision(x=>x+1))}>Validar classificação do mercado</button></div>}
  <button className="button secondary" disabled={busy} onClick={()=>setRevision(x=>x+1)}>Atualizar apuramento</button>{' '}
  <button className="button" disabled={busy||result?.status!=='ready'||!winner||!outcomeLabels[winner]||Date.parse(market.closes_at)>Date.now()} onClick={()=>{
   if(winner&&window.confirm('Liquidar definitivamente com o resultado validado: '+outcomeLabels[winner]+'?'))onSettle(winner);
  }}>Liquidar resultado validado</button>
 </div>;
}
