import {useEffect,useState} from 'react';
import type {Market} from '../lib/domain';
import {rpc} from '../lib/supabase';
import {observeRequest} from '../lib/competition';

export type Resolution={status:string;validation_id?:string;winner_outcome_id?:string;criterion?:string};
export function resolutionMessage(status:string):string {
 const messages:Record<string,string>={
  ready:'Classificação validada. O resultado é determinado pelos dados congelados.',
  settled:'Mercado liquidado.',
  unlinked:'Mercado antigo sem período associado. A liquidação exige reconciliação própria.',
  awaiting_validation:'Aguarda captura e validação final da classificação.',
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
  {result.criterion&&<p className="footnote">Critério: {result.criterion==='annual_ytd'?'YTD absoluto no fecho anual':'ΔYTD entre início e fim do próprio sprint (pp)'}. As modalidades adicionais de aposta ainda não estão disponíveis.</p>}</>;
}
export function MarketSettlement({market,outcomeLabels,busy,onSettle}:{market:Market;outcomeLabels:Record<string,string>;busy:boolean;onSettle:(winner:string)=>void}){
 const [result,setResult]=useState<Resolution|null>(null),[revision,setRevision]=useState(0),[failed,setFailed]=useState(false);
 useEffect(()=>{
  setResult(null);setFailed(false);
  return observeRequest(rpc<Resolution>('get_market_resolution',{p_market:market.id}),setResult,()=>setFailed(true));
 },[market.id,revision]);
 const winner=result?.winner_outcome_id;
 return <div className="panel"><h3>{market.title}</h3>
  <p className="footnote">Fecho: {new Date(market.closes_at).toLocaleString('pt-PT')}</p>
  {result?<ResolutionDetails result={result} winner={winner?outcomeLabels[winner]:undefined}/>:<p role="status">{failed?'Apuramento indisponível até à atualização da base de dados ou da ligação.':'A consultar o apuramento…'}</p>}
  <button className="button secondary" disabled={busy} onClick={()=>setRevision(x=>x+1)}>Atualizar apuramento</button>{' '}
  <button className="button" disabled={busy||result?.status!=='ready'||!winner||!outcomeLabels[winner]||Date.parse(market.closes_at)>Date.now()} onClick={()=>{
   if(winner&&window.confirm('Liquidar definitivamente com o resultado validado: '+outcomeLabels[winner]+'?'))onSettle(winner);
  }}>Liquidar resultado validado</button>
 </div>;
}
