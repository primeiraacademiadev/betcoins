import {useEffect,useState} from 'react';
import {rpc} from '../lib/supabase';
import {observeRequest} from '../lib/competition';
import {validFinalYtd,finalDeadlineLabel,type PendingFinal,type FinalRound,type ScoreAudit} from '../lib/finalDeclarations';
type Act=(fn:()=>Promise<unknown>,message:string)=>Promise<void>;
export function ScoreAuditDetails({row}:{row:ScoreAudit}){
 if(row.score_origin==='missing_baseline')return <small className="movement-date">Sem YTD conhecido: sem classificação.</small>;
 if(Number(row.penalty_pp)===1)return <small className="movement-date">Fecho não declarado / penalizado · Original {Number(row.declared_ytd).toFixed(4)}% · −1 pp · Efetivo {Number(row.end_ytd).toFixed(4)}%{row.source_declared_at&&' · Declaração de origem: '+new Date(row.source_declared_at).toLocaleString('pt-PT')}. A penalização pertence apenas a este fecho.</small>;
 if(row.score_origin==='final_declaration')return <small className="movement-date">Declaração final recebida{row.source_declared_at&&' em '+new Date(row.source_declared_at).toLocaleString('pt-PT')} · Sem penalização.</small>;
 return null;
}
export function PendingFinalSummary({round,first}:{round:PendingFinal;first:boolean}){
 return <><h3>YTD de fecho · {new Date(round.cutoff_at).toLocaleString('pt-PT')}</h3><p>{round.periods.join(' · ')}</p><p className="footnote">{finalDeadlineLabel(round)}</p>{!first&&<p className="footnote">Resolve primeiro o fecho mais antigo.</p>}{round.expired&&<p className="footnote">Aguarda o apuramento pela gestão. Uma omissão com YTD conhecido implica −1 pp apenas neste fecho.</p>}</>;
}
function ClosingForm({round,busy,act}:{round:PendingFinal;busy:boolean;act:Act}){
 const [value,setValue]=useState('');
 return <div><label>YTD relativo a este fecho (%)<input type="number" step=".0001" min={-100} max={100000} value={value} onChange={e=>setValue(e.target.value)}/></label><p className="footnote">Uma declaração serve todos os períodos acima. Fica imutável e não substitui o YTD corrente.</p><button className="button" disabled={busy||round.expired||!validFinalYtd(value)} onClick={()=>void act(()=>rpc('declare_final_score',{p_round:round.id,p_ytd:Number(value)}),'Declaração de fecho registada. O YTD corrente não foi alterado.')}>Confirmar YTD de fecho</button></div>;
}
export function FinalDeclarations({userId,revision,busy,act,onPending}:{userId:string;revision:unknown;busy:boolean;act:Act;onPending:(pending:boolean)=>void}){
 const [pending,setPending]=useState<PendingFinal[]|null>(null),[failed,setFailed]=useState(false);
 useEffect(()=>{
  setPending(null);setFailed(false);onPending(false);
  return observeRequest(rpc<PendingFinal[]>('get_my_final_declarations'),rows=>{setPending(rows);onPending(rows.length>0)},()=>{setFailed(true);onPending(false)});
 },[userId,revision,onPending]);
 if(failed)return <section className="warning"><p>As declarações finais estarão disponíveis após a atualização da base de dados. Se já foi instalada, atualiza a ligação.</p></section>;
 if(!pending?.length)return null;
 return <section className="panel" id="final-declarations"><h2>Declarações de fecho obrigatórias</h2><p>Antes de atualizar o YTD corrente, resolve estes fechos por ordem. Não uses um valor atual como se fosse histórico.</p>{pending.map((round,i)=><div className="panel" key={round.id}><PendingFinalSummary round={round} first={i===0}/>{i===0&&!round.expired&&<ClosingForm key={round.id} round={round} busy={busy} act={act}/>}</div>)}</section>;
}
function FinalRoundCard({round,busy,act,refresh}:{round:FinalRound;busy:boolean;act:Act;refresh:()=>void}){
 const [note,setNote]=useState(''),[deadline,setDeadline]=useState('');
 async function action(fn:()=>Promise<unknown>,message:string){await act(fn,message);refresh()}
 const deadlineValid=Number.isFinite(Date.parse(deadline))&&Date.parse(deadline)>Date.now();
 return <div className="panel"><h3>{round.periods.join(' · ')}</h3><p className="footnote">Referência: {new Date(round.cutoff_at).toLocaleString('pt-PT')} · Declararam {round.declared} de {round.members}.</p>{round.state==='finalized'?<p>Apuramento congelado em {new Date(round.finalized_at!).toLocaleString('pt-PT')}. A classificação e a liquidação dos mercados continuam a exigir validação.</p>:<><p className="footnote">{finalDeadlineLabel({...round,expired:round.deadline_at!==null&&Date.parse(round.deadline_at)<=Date.now()})}</p><label>Nota administrativa<textarea value={note} maxLength={2000} onChange={e=>setNote(e.target.value)}/></label>{!round.deadline_at&&<><label>Prazo para as declarações (hora local)<input type="datetime-local" value={deadline} onChange={e=>setDeadline(e.target.value)}/></label><button className="button secondary" disabled={busy||note.trim().length<10||!deadlineValid} onClick={()=>void action(()=>rpc('set_final_deadline',{p_round:round.id,p_deadline:new Date(deadline).toISOString(),p_note:note.trim()}),'Prazo fixado para este fecho.')}>Fixar prazo</button>{' '}</>}<button className="button" disabled={busy||note.trim().length<10||(round.deadline_at!==null&&Date.parse(round.deadline_at)>Date.now())} onClick={()=>{
  if(window.confirm('Encerrar a recolha e congelar os snapshots? Quem não declarou terá −1 pp sobre o último YTD conhecido, apenas neste fecho. Sem YTD conhecido fica sem classificação. Esta ação não liquida mercados.'))void action(()=>rpc('finalize_final_round',{p_round:round.id,p_note:note.trim()}),'Fecho apurado e snapshots congelados.');
 }}>Encerrar recolha e apurar</button></>}</div>;
}
export function FinalRoundManagement({championships,busy,act}:{championships:Array<{id:string;name:string}>;busy:boolean;act:Act}){
 const [champ,setChamp]=useState(''),[rounds,setRounds]=useState<FinalRound[]|null>(null),[revision,setRevision]=useState(0),[failed,setFailed]=useState(false);
 useEffect(()=>{
  setRounds(null);setFailed(false);if(!champ)return;
  return observeRequest(rpc<FinalRound[]>('get_final_rounds',{p_championship:champ}),setRounds,()=>setFailed(true));
 },[champ,revision]);
 return <section className="panel"><h2>Recolha e apuramento de declarações finais</h2><label>Campeonato<select value={champ} onChange={e=>setChamp(e.target.value)}><option value="">Selecionar</option>{championships.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label><button className="button secondary" disabled={busy||!champ} onClick={()=>setRevision(x=>x+1)}>Atualizar fechos</button>{failed&&<p role="status">Fechos indisponíveis até à atualização da base de dados ou da ligação.</p>}{rounds?.length===0&&<p>Não há fechos recorrentes publicados por tratar.</p>}{rounds?.map(r=><FinalRoundCard key={r.id+':'+revision} round={r} busy={busy} act={act} refresh={()=>setRevision(x=>x+1)}/>)}</section>;
}
