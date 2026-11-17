import type {Market,MarketKind} from './domain';
import type {MarketMode} from './marketModes';
export type BetDefinition={id:string;championship_id:string;kind:MarketKind;mode:MarketMode;active:boolean};
export type BetOccurrence={id:string;championship_id:string;kind:MarketKind;period_key:string;name:string;starts_at:string;ends_at:string;sprint_id:string|null;previous_occurrence_id:string|null};
export function occurrenceStatus(o:BetOccurrence,markets:Market[],now=Date.now()):string {
 const own=markets.filter(m=>m.occurrence_id===o.id);
 if(own.length>0&&own.every(m=>m.state==='settled'))return 'Liquidada';
 if(Date.parse(o.ends_at)<=now)return own.length?'Em apuramento':'Histórico — sem mercados gerados';
 return Date.parse(o.starts_at)>now?'Futura':'Em curso';
}
export function marketsForOccurrence(markets:Market[],definition:string,occurrence:string):Market[]{
 if(!definition)return [];
 return markets.filter(m=>m.definition_id===definition&&m.occurrence_id===occurrence);
}
export function marketTradingBlocked(market:Market|undefined,definitions:BetDefinition[],now=Date.now()):boolean {
 if(!market||market.state!=='open'||Date.parse(market.closes_at)<=now)return true;
 return definitions.some(d=>d.id===market.definition_id&&!d.active);
}

export function recurrenceKindLabel(kind:string){return ({annual:"Anual",monthly:"Mensal",weekly:"Semanal"} as Record<string,string>)[kind]??kind;}
