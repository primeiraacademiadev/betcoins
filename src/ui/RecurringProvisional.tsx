import {useEffect,useState} from 'react';
import {rpc} from '../lib/supabase';
import {observeRequest} from '../lib/competition';
type Preview={status:string;unit:string;rows:Array<{competitor_id:string;nickname:string;updated_at:string|null;value:number|null;place:number|null}>};
export function RecurringProvisional({marketId}:{marketId:string}){
 const [preview,setPreview]=useState<Preview|null>(null);
 useEffect(()=>{
  setPreview(null);
  return observeRequest(rpc<Preview>('get_bet_provisional_rankings',{p_market:marketId}),setPreview,()=>setPreview(null));
 },[marketId]);
 if(!preview||preview.status!=='provisional')return null;
 return <section className="panel"><h2>Classificação provisória desta aposta</h2><p className="footnote">Usa as últimas declarações disponíveis. Para delta, a referência é o fecho anterior congelado. Não é um resultado validado nem autoriza liquidação.</p>{preview.rows.map(r=><div className="rank-row" key={r.competitor_id}><span>{r.place??'—'} · {r.nickname}<small className="movement-date">{r.updated_at?'Declaração: '+new Date(r.updated_at).toLocaleString('pt-PT'):'Aguarda declaração'}</small></span><strong>{r.value===null?'Sem dados para apuramento':Number(r.value).toFixed(4)+' '+preview.unit}</strong></div>)}</section>;
}
