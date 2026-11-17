import type {MarketCategory} from './domain';
export type RankValue={competitor_id:string;place:number|null;value:number|null};
export function highlightedCompetitors(rows:RankValue[],category?:MarketCategory):Set<string>{
 const complete=rows.filter(r=>r.value!==null&&r.place!==null);
 if(!category||!complete.length)return new Set();
 const target=category==='second'?complete.find(r=>r.place===2)?.value:category==='last'?Math.min(...complete.map(r=>Number(r.value))):Math.max(...complete.map(r=>Number(r.value)));
 return new Set(complete.filter(r=>r.value===target).map(r=>r.competitor_id));
}
export type ActivityEvent={id:string;at:string;kind:'offer'|'trade';label:string;side:'back'|'lay'|null;odds:number;stake:number|null;liability:number|null;state:'open'|'cancelled'|'filled'|null;stake_remaining:number|null};
export type ActivityPage={events:ActivityEvent[];has_more:boolean;next_cursor:{at:string;id:string}|null;market_state:string;closes_at:string;resolution:{status:'settled';winner:string;resolved_at:string}|null};
