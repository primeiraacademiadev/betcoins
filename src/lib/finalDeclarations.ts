export type PendingFinal={id:string;championship_id:string;cutoff_at:string;deadline_at:string|null;periods:string[];expired:boolean};
export type FinalRound=PendingFinal&{state:'collecting'|'finalized';members:number;declared:number;finalized_at:string|null};
export type ScoreAudit={declared_ytd?:number|null;penalty_pp?:number;score_origin?:string|null;source_declared_at?:string|null;source_cutoff_at?:string|null;end_ytd?:number|null};
export function validFinalYtd(text:string):boolean {
 const value=Number(text);
 return text.trim()!==''&&Number.isFinite(value)&&value>=-100&&value<=100000&&Math.abs(value*10000-Math.round(value*10000))<1e-6;
}
export function finalDeadlineLabel(round:PendingFinal):string {
 if(!round.deadline_at)return 'Sem prazo fixado — a recolha mantém-se aberta até a gestão encerrar.';
 return (round.expired?'Prazo encerrado: ':'Declarar antes de: ')+new Date(round.deadline_at).toLocaleString('pt-PT');
}
