import type {ScoreAudit} from './finalDeclarations';
import type {Competitor} from './domain';
export type Capture = {id:string;cutoff_at:string;captured_at:string;captured_by:string};
export type CompetitionRow = ScoreAudit & {
 competitor_id:string;nickname:string;start_ytd:number|null;end_ytd:number|null;
 start_declared_at:string|null;end_declared_at:string|null;
 start_source_id:number|null;end_source_id:number|null;
 status:'complete'|'missing_start'|'missing_end';value:number|null;place:number|null;
};
export type CompetitionReview = {
 starts_at:string;ends_at:string;legacy:boolean;start_capture:Capture|null;end_capture:Capture|null;
 validation:{id:string;validated_at:string;validated_by:string;note:string}|null;
 rows:CompetitionRow[];can_capture_start:boolean;can_capture_end:boolean;can_validate:boolean;
};

/** Cancel delivery on a period/account change or unmount, including late errors. */
export function observeRequest<T>(request:Promise<T>,onValue:(value:T)=>void,onError:(error:unknown)=>void){
 let active=true;
 void request.then(value=>{if(active)onValue(value);},error=>{if(active)onError(error);});
 return ()=>{active=false;};
}
export function rankCurrentCompetitors(rows:Competitor[]):Array<Competitor & {place:number|null}>{
 const declared=rows.filter(r=>r.updated_at!==null&&r.ytd!==null).sort((a,b)=>Number(b.ytd)-Number(a.ytd)||a.id.localeCompare(b.id));
 let place=0;
 return [...declared.map((row,index)=>{
  if(index===0||Number(row.ytd)!==Number(declared[index-1].ytd))place=index+1;
  return {...row,place};
 }),...rows.filter(r=>r.updated_at===null||r.ytd===null).map(row=>({...row,place:null}))];
}
export function competitionError(error:unknown):string|null {
 const code=(error as {code?:string})?.code;
 const errors:Record<string,string>={
  BC001:'O registo já está congelado e não pode ser alterado.',
  BC002:'O período selecionado não é válido. Atualiza os dados.',
  BC003:'O instante de referência ainda não foi atingido.',
  BC004:'Este sprint tem capturas antigas sem proveniência verificável. Está disponível apenas para consulta.',
  BC005:'Captura primeiro o snapshot inicial.',
  BC006:'Escreve uma nota de validação entre 10 e 2000 caracteres.',
  BC007:'Ainda não existem snapshots completos com dados apuráveis para validar.'
 };
 return code?errors[code]??null:null;
}
