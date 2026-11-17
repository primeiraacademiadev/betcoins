import {useEffect,useState} from 'react';
import {rpc} from '../lib/supabase';
import {observeRequest} from '../lib/competition';
import {validFinalYtd} from '../lib/finalDeclarations';
import {entryStatusLabel,type EntryBaseline,type EntryReference} from '../lib/entryBaselines';
type Act=(fn:()=>Promise<unknown>,message:string)=>Promise<void>;
export function EntryReferenceDetails({row}:{row:EntryReference}){
 if(row.participation_status==='awaiting_initial')return <small className="movement-date">Admitido — aguarda YTD inicial. Ainda sem participação efetiva.</small>;
 if(row.participation_status==='not_yet_entered')return <small className="movement-date">A entrada é posterior a este fecho; não participa retroativamente.</small>;
 if(row.reference_kind==='entry_baseline')return <small className="movement-date">Referência: YTD inicial da entrada em {new Date(row.reference_at!).toLocaleString('pt-PT')}. Variação desde a entrada; janela parcial. Os concorrentes podem ter datas de referência diferentes.</small>;
 if(row.reference_kind==='previous_snapshot')return <small className="movement-date">Referência: fecho do período anterior{row.reference_at&&' em '+new Date(row.reference_at).toLocaleString('pt-PT')}.</small>;
 return null;
}
export function EntrySummary({entry}:{entry:EntryBaseline}){
 return <><h3>{entry.name} · {entryStatusLabel(entry)}</h3><p className="footnote">Admissão: {new Date(entry.admitted_at).toLocaleString('pt-PT')}</p>{entry.baseline_id&&<p>YTD inicial imutável: <strong>{Number(entry.ytd).toFixed(4)}%</strong> · Participação desde {new Date(entry.effective_at!).toLocaleString('pt-PT')}.{entry.source_kind==='audited_history'&&' Referência preservada do primeiro registo auditado.'}</p>}</>;
}
function EntryForm({entry,busy,act}:{entry:EntryBaseline;busy:boolean;act:Act}){
 const [value,setValue]=useState('');
 return <div><p>A admissão está aprovada. Declara o primeiro YTD para iniciar a participação. Esse valor fica como referência imutável; as atualizações seguintes são separadas.</p><label>Primeiro YTD declarado (%)<input type="number" step=".0001" min={-100} max={100000} value={value} onChange={e=>setValue(e.target.value)}/></label><button className="button" disabled={busy||!validFinalYtd(value)} onClick={()=>void act(()=>rpc('declare_initial_ytd',{p_championship:entry.championship_id,p_ytd:Number(value)}),'YTD inicial registado; participação ativada nos mercados ainda negociáveis.')}>Declarar YTD inicial e participar</button></div>;
}
export function EntryBaselines({userId,revision,busy,act,onPending}:{userId:string;revision:unknown;busy:boolean;act:Act;onPending:(pending:boolean)=>void}){
 const [entries,setEntries]=useState<EntryBaseline[]|null>(null),[failed,setFailed]=useState(false);
 useEffect(()=>{
  setEntries(null);setFailed(false);onPending(false);
  return observeRequest(rpc<EntryBaseline[]>('get_my_entry_baselines'),rows=>{setEntries(rows);onPending(rows.some(r=>r.status==='awaiting_initial'))},()=>{setFailed(true);onPending(false)});
 },[userId,revision,onPending]);
 if(failed)return <section className="warning"><p>A referência inicial estará disponível após a atualização da base de dados. Se já foi instalada, atualiza a ligação.</p></section>;
 if(!entries?.length)return null;
 return <section className="panel"><h2>Participação e YTD inicial</h2>{entries.map(entry=><div className="panel" key={entry.championship_id}><EntrySummary entry={entry}/>{entry.status==='awaiting_initial'&&<EntryForm entry={entry} busy={busy} act={act}/>}</div>)}</section>;
}
