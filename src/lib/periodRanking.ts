/**
 * Pure, deterministic BetCoins period-classification rules.
 * These functions do not mutate snapshots or wallets.
 * PostgreSQL settlement must use the same semantics atomically.
 */
export type RankingMetric = 'ytd' | 'delta';
export type MarketPlace = 'winner' | 'second' | 'last';

export type PeriodScore = {
 competitorId: string;
 nickname: string;
 /** Last valid declared YTD at the occurrence's closing deadline, percentage. */
 declaredYtd: number;
 /** Baseline at the occurrence start, or first declaration for a mid-period entrant. */
 baselineYtd: number | null;
 /** True when the competitor did not submit the closing declaration. */
 missedClose: boolean;
};

export type RankedScore = PeriodScore & {
 /** The frozen, effective final YTD used for this occurrence. */
 effectiveYtd: number;
 /** Effective final minus baseline in percentage points. */
 deltaPp: number | null;
 /** Primary sorting value for the chosen metric. */
 value: number;
 /** Competition rank: 1,1,3, rather than arbitrarily breaking ties. */
 place: number;
};

export type RankingResult = {
 metric: RankingMetric;
 rows: RankedScore[];
 winners: Record<MarketPlace, string | null>;
 voidReasons: Partial<Record<MarketPlace, string>>;
};

const PENALTY_PP = 1;

/**
 * Uses only the scores frozen for one occurrence; never infers historical
 * declarations from today's YTD. Missing closing declarations suffer -1 pp,
 * confined to this occurrence's snapshot.
 */
export function classifyPeriod(scores: PeriodScore[], metric: RankingMetric): RankingResult {
 const seen = new Set<string>();
 const rows: RankedScore[] = scores.map(s => {
  if (!s.competitorId || seen.has(s.competitorId)) throw new Error('Concorrente duplicado ou sem identidade.');
  seen.add(s.competitorId);
  if (!Number.isFinite(s.declaredYtd) || s.declaredYtd < -100) throw new Error('YTD declarado inválido.');
  if (s.baselineYtd !== null && (!Number.isFinite(s.baselineYtd) || s.baselineYtd < -100)) throw new Error('Baseline inválido.');
  const effectiveYtd = s.declaredYtd - (s.missedClose ? PENALTY_PP : 0);
  const deltaPp = s.baselineYtd === null ? null : effectiveYtd - s.baselineYtd;
  if (metric === 'delta' && deltaPp === null) throw new Error('Falta o snapshot de referência do concorrente.');
  return {...s, effectiveYtd,deltaPp,value:metric==='ytd'?effectiveYtd:deltaPp!,place:0};
 });
 rows.sort((a,b)=>b.value-a.value || a.competitorId.localeCompare(b.competitorId));
 let position=0;
 for(let i=0;i<rows.length;i++){
  if(i===0 || rows[i].value!==rows[i-1].value)position=i+1;
  rows[i].place=position;
 }
 const first=rows.filter(r=>r.place===1);
 const second=rows.filter(r=>r.place===2);
 const min=rows.length?rows[rows.length-1].value:null;
 const last=rows.filter(r=>r.value===min);
 const winners:Record<MarketPlace,string|null>={
  winner:first.length===1?first[0].competitorId:null,
  second:first.length===1 && second.length===1?second[0].competitorId:null,
  last:last.length===1?last[0].competitorId:null
 };
 const voidReasons:Partial<Record<MarketPlace,string>>={};
 if(!winners.winner)voidReasons.winner=first.length>1?'Empate no primeiro lugar.':'Sem concorrentes.';
 if(!winners.second)voidReasons.second=first.length>1?'Empate no primeiro lugar anula também o segundo.':second.length>1?'Empate no segundo lugar.':'Sem segundo lugar inequívoco.';
 if(!winners.last)voidReasons.last=last.length>1?'Empate no último lugar.':'Sem concorrentes.';
 return {metric,rows,winners,voidReasons};
}

/** In a void market, refund the reserved collateral to current holders only.
 * Prices paid in past secondary trades remain executed and are not reversed.
 */
export function collateralToRefund(side:'back'|'lay',stake:number,liability:number):number{
 if(!Number.isFinite(stake)||stake<0||!Number.isFinite(liability)||liability<0)throw new Error('Colateral inválido.');
 return side==='back'?stake:liability;
}
