import {useState} from 'react';
import {rpc} from '../lib/supabase';
import {modeLabel,type MarketMode} from '../lib/marketModes';
import type {Market,MarketKind} from '../lib/domain';
import {recurrenceKindLabel,occurrenceStatus,type BetDefinition,type BetOccurrence} from '../lib/recurringBets';
export function OccurrencePicker({definitions,occurrences,markets,definition,occurrence,onSelect}:{definitions:BetDefinition[];occurrences:BetOccurrence[];markets:Market[];definition:string;occurrence:string;onSelect:(definition:string,occurrence:string)=>void}){
 const d=definitions.find(x=>x.id===definition);
 const choices=occurrences.filter(o=>o.championship_id===d?.championship_id&&o.kind===d?.kind).sort((a,b)=>a.starts_at.localeCompare(b.starts_at));
 return <section className="panel"><h2>Bets e calendário</h2><div className="form-row"><label>Bet<select value={definition} onChange={e=>{
  const next=definitions.find(x=>x.id===e.target.value);const periods=occurrences.filter(o=>o.championship_id===next?.championship_id&&o.kind===next?.kind).sort((a,b)=>a.starts_at.localeCompare(b.starts_at));
  const current=periods.find(o=>Date.parse(o.ends_at)>Date.now());onSelect(e.target.value,current?.id||periods.at(-1)?.id||'');
 }}><option value="">Mercados anteriores / individuais</option>{definitions.map(x=><option key={x.id} value={x.id}>{recurrenceKindLabel(x.kind)} · {modeLabel(x.mode)}{x.active?'':' · Suspensa'}</option>)}</select></label>
 {d&&<label>Ocorrência<select value={occurrence} onChange={e=>onSelect(definition,e.target.value)}><option value="">Selecionar período</option>{choices.map(o=><option key={o.id} value={o.id}>{o.name} · {occurrenceStatus(o,markets.filter(m=>m.definition_id===d.id))}</option>)}</select></label>}</div>{d&&choices.length>0&&<button className="button secondary" onClick={()=>{const current=choices.find(o=>Date.parse(o.ends_at)>Date.now());onSelect(d.id,current?.id||choices.at(-1)!.id)}}>Ir para o período corrente</button>}
 {d&&<p className="footnote">Os concorrentes admitidos podem entrar nos mercados ainda negociáveis. As ofertas e posições existentes mantêm-se; o universo de resultados pode aumentar. Empates relevantes bloqueiam a liquidação.</p>}
 {choices.find(o=>o.id===occurrence)&&<p className="footnote">Início: {new Date(choices.find(o=>o.id===occurrence)!.starts_at).toLocaleString('pt-PT')} · Fecho: {new Date(choices.find(o=>o.id===occurrence)!.ends_at).toLocaleString('pt-PT')}. Períodos passados são apenas consultáveis.</p>}
 </section>;
}
type Act=(fn:()=>Promise<unknown>,message:string)=>Promise<void>;
export function RecurringBets({championships,definitions,occurrences,markets,busy,act}:{championships:Array<{id:string;name:string}>;definitions:BetDefinition[];occurrences:BetOccurrence[];markets:Market[];busy:boolean;act:Act}){
 const [champ,setChamp]=useState(''),[kind,setKind]=useState<MarketKind>('weekly'),[mode,setMode]=useState<MarketMode>('snapshot_value');
 const [report,setReport]=useState<{new_markets:number;new_occurrences:number;new_outcomes:number;blocked_occurrences:number}|null>(null);
 async function configure(k:MarketKind,md:MarketMode,active:boolean){
  await act(async()=>setReport(await rpc('configure_recurring_bet',{p_championship:champ,p_kind:k,p_mode:md,p_active:active})),'Definição atualizada e calendário reconciliado.');
 }
 return <section className="panel"><h2>Bets recorrentes e calendário</h2><label>Campeonato<select value={champ} onChange={e=>{setChamp(e.target.value);setReport(null)}}><option value="">Selecionar campeonato</option>{championships.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
 <div className="form-row"><label>Periodicidade<select value={kind} onChange={e=>setKind(e.target.value as MarketKind)}><option value="weekly">Semanal</option><option value="monthly">Mensal</option><option value="annual">Anual</option></select></label><label>Modalidade<select value={mode} onChange={e=>setMode(e.target.value as MarketMode)}><option value="snapshot_value">Valor no fecho (%)</option><option value="snapshot_delta_previous">Diferença do fecho anterior (pp)</option></select></label></div>
 <p className="footnote">Gera antecipadamente 1.º, 2.º e último até ao fim do campeonato de 2026, sem duplicar. Semanas fecham na última sessão NYSE; meses usam Europe/Lisbon. Períodos passados ficam no calendário sem apostas retroativas. São necessários dois concorrentes e, para delta, um período anterior identificado.</p>
 <button className="button" disabled={busy||!champ} onClick={()=>void configure(kind,mode,true)}>Ativar e gerar mercados</button>{' '}<button className="button secondary" disabled={busy||!champ} onClick={()=>void act(async()=>setReport(await rpc('regenerate_bet_markets',{p_championship:champ})),'Calendário reconciliado sem duplicações.')}>Reconciliar calendário</button>
 {report&&<p className="footnote" role="status">Novas ocorrências: {report.new_occurrences} · mercados: {report.new_markets} · outcomes: {report.new_outcomes} · ocorrências sem participantes ou referência suficiente: {report.blocked_occurrences}.</p>}
 {definitions.filter(d=>d.championship_id===champ).map(d=><div className="offer" key={d.id}><div><strong>{recurrenceKindLabel(d.kind)} · {modeLabel(d.mode)}</strong><small>{d.active?'Ativa':'Suspensa'} · {markets.filter(m=>m.definition_id===d.id).length} mercados</small></div><button className="button secondary" disabled={busy} onClick={()=>void configure(d.kind,d.mode,!d.active)}>{d.active?'Suspender negociação':'Retomar e reconciliar'}</button></div>)}
 <div className="market-pills">{occurrences.filter(o=>o.championship_id===champ).sort((a,b)=>a.starts_at.localeCompare(b.starts_at)).map(o=><span className="market-pill" key={o.id}>{o.name} · {new Date(o.ends_at).toLocaleString('pt-PT')} · {occurrenceStatus(o,markets)}</span>)}</div>
 </section>;
}
