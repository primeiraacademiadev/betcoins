import {useEffect,useState} from 'react';
import {rpc} from '../lib/supabase';
import {observeRequest} from '../lib/competition';
import {modeLabel,type MarketClassificationRow,type MarketMode} from '../lib/marketModes';
import {ScoreAuditDetails} from './FinalDeclarations';
import {EntryReferenceDetails} from './EntryBaselines';
export type OccurrenceResult={id:string|null;mode:MarketMode;unit:'%'|'pp';status:'frozen'|'waiting_final_results';rows:MarketClassificationRow[];recorded_at:string|null};
export function OccurrenceResultsDetails({results}:{results:OccurrenceResult[]}){
 return <>{results.map(r=><div className="occurrence-result" key={r.mode}><h3>{modeLabel(r.mode)}</h3>{r.status!=='frozen'?<p>Dados finais indisponíveis / por apurar. Faltam o fecho ou as referências necessárias.</p>:<><p className="footnote">Estatísticas finais congeladas em {new Date(r.recorded_at!).toLocaleString('pt-PT')}. A validação e a liquidação são operações separadas.</p>{r.rows.map(row=><div className="rank-row" key={row.competitor_id}><span>{row.place??'—'} · {row.nickname}<ScoreAuditDetails row={row}/><EntryReferenceDetails row={row}/></span><strong>{row.value===null?'Sem dados para apuramento':Number(row.value).toFixed(4)+' '+r.unit}</strong></div>)}</>}</div>)}</>;
}
export function OccurrenceResults({occurrenceId,revision}:{occurrenceId:string;revision?:unknown}){
 const [results,setResults]=useState<OccurrenceResult[]|null>(null),[failed,setFailed]=useState(false),[refresh,setRefresh]=useState(0);
 useEffect(()=>{setResults(null);setFailed(false);return observeRequest(rpc<OccurrenceResult[]>('get_occurrence_results',{p_occurrence:occurrenceId}),setResults,()=>setFailed(true))},[occurrenceId,revision,refresh]);
 return <section className="panel"><h2>Estatísticas finais da ocorrência</h2>{results?<OccurrenceResultsDetails results={results}/>:<p role="status">{failed?'Estatísticas indisponíveis. Atualiza para tentar novamente.':'A consultar as estatísticas finais…'}</p>}<button className="button secondary" onClick={()=>setRefresh(x=>x+1)}>Atualizar estatísticas</button></section>;
}
