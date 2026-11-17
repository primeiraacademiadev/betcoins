import {EntryReferenceDetails} from './EntryBaselines';
import type {EntryReference} from '../lib/entryBaselines';
import {useEffect,useState} from 'react';
import {rpc} from '../lib/supabase';
import type {MarketCategory} from '../lib/domain';
import {highlightedCompetitors} from '../lib/marketResults';
import {observeRequest} from '../lib/competition';
type Preview={status:string;unit:string;rows:Array<EntryReference & {competitor_id:string;nickname:string;updated_at:string|null;value:number|null;place:number|null}>};
export function RecurringProvisional({marketId,category,revision}:{marketId:string;category?:MarketCategory;revision?:unknown}){
 const [preview,setPreview]=useState<Preview|null>(null);
 useEffect(()=>{
  setPreview(null);
  return observeRequest(rpc<Preview>('get_bet_provisional_rankings',{p_market:marketId}),setPreview,()=>setPreview(null));
 },[marketId,revision]);
 if(!preview||preview.status!=='provisional')return null;
 const highlighted=highlightedCompetitors(preview.rows,category);
 return <section className="panel"><h2>Classificação provisória desta aposta</h2><p className="footnote">Usa as últimas declarações disponíveis. Para delta, a referência é o fecho anterior congelado; nas entradas a meio do período, é o primeiro YTD declarado. As janelas de participação podem ser diferentes. Não é um resultado validado nem autoriza liquidação.</p>{preview.rows.map(r=><div className={'rank-row'+(highlighted.has(r.competitor_id)?' target-row':'')} key={r.competitor_id}><span>{r.place??'—'} · {r.nickname}{highlighted.has(r.competitor_id)&&<small className="target-label">Posição desta aposta</small>}<small className="movement-date">{r.updated_at?'Declaração: '+new Date(r.updated_at).toLocaleString('pt-PT'):'Aguarda declaração'}</small><EntryReferenceDetails row={r}/></span><strong>{r.value===null?'Sem dados para apuramento':Number(r.value).toFixed(4)+' '+preview.unit}</strong></div>)}</section>;
}
