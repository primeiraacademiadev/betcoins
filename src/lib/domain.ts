export type MarketKind = 'annual' | 'weekly' | 'monthly';
export type MarketCategory = 'winner' | 'second' | 'last';
export type OrderSide = 'back' | 'lay';
export type Profile = { id: string; nickname: string; role: 'spectator'|'competitor'|'admin' };
export type Championship = { id: string; name: string; ends_at: string };
export type Competitor = { id: string; nickname: string; ytd: number | null; updated_at: string | null };
export type Market = { id: string; title: string; kind: MarketKind; category: MarketCategory; closes_at: string; state: string; winner_outcome_id?: string | null; mode?: 'snapshot_value'|'snapshot_delta_previous'|null; previous_closes_at?:string|null; championship_id?:string|null;sprint_id?:string|null;definition_id?:string|null;occurrence_id?:string|null;entry_reference_enabled?:boolean;entry_starts_at?:string|null;replaced_by_market_id?:string|null };
export type Outcome = { id: string; market_id: string; label: string; competitor_id: string };
export type Offer = { id: string; market_id: string; outcome_id: string; owner_id: string; side: OrderSide; odds: number; stake_remaining: number; created_at: string };
export type Position = { id: string; trade_id: string; owner_id: string; side: OrderSide; outcome_id: string; market_id: string; stake: number; liability: number; cost_basis?: number; status: string };
export type Listing = { id: string; position_id: string; seller_id: string; price: number; state: string; created_at: string; side:'back'|'lay';market_id:string;outcome_id:string;stake:number;liability:number;outcome_label:string;market_title:string };
export type PositionSale = { listing_id:string;position_id:string;seller_id:string;buyer_id:string;seller_cost_basis:number;sale_price:number;realized_pnl:number;traded_at:string };
export type PositionSettlement = { position_id:string;owner_id:string;payoff:number;final_cost_basis:number;realized_pnl:number;settled_at:string };
export type LedgerEntry = { id:number;reason:string;reference:string;available_delta:number;reserved_delta:number;created_at:string };
export type Wallet = { available: number; reserved: number; total_issued: number };
export type Ranking = { owner_id: string; nickname: string; available: number; reserved: number; issued: number; wealth: number; relative_pct: number|null; realized_resale_pnl: number; open_positions: number|null; exposure: number|null; valuation_status: string };
export type Application = { id: string; candidate_id: string; nickname: string; state: string; yes_votes: number; eligible_votes: number };
export function sprintReturn(start: number, end: number): number {
  if (!Number.isFinite(start) || !Number.isFinite(end)) throw new Error('YTD inválido.');
  return end - start;
}
export function impliedProbability(odds: number): number { if (odds <= 1) throw new Error('Odd inválida'); return 100 / odds; }
export function liability(stake: number, odds: number): number {
  if (!Number.isInteger(stake) || stake <= 0 || !Number.isFinite(odds) || odds <= 1) throw new Error('Oferta inválida');
  return Math.round(stake * (odds - 1) * 100) / 100;
}
/** Conditions and collateral from the ACCEPTING player's perspective. */
export function acceptanceTerms(offeredSide: OrderSide, stake: number, odds: number) {
 const liabilityValue=liability(stake,odds);
 const side:OrderSide=offeredSide==='back'?'lay':'back';
 const risk=side==='back'?stake:liabilityValue;
 const profit=side==='back'?liabilityValue:stake;
 return {side,risk,profit,payout:stake+liabilityValue};
}
export function formatCoins(value: number) { return new Intl.NumberFormat('pt-PT', {maximumFractionDigits:2}).format(value); }
/** Economic P&L on a completed secondary sale, independent of collateral transfers. */
export function resalePnl(salePrice: number, acquisitionCost: number): number {
 if (!Number.isFinite(salePrice) || salePrice <= 0 || !Number.isFinite(acquisitionCost) || acquisitionCost < 0) throw new Error('Preço ou custo de aquisição inválido.');
 return Math.round((salePrice-acquisitionCost)*100)/100;
}

/** Smallest whole-stake lot with whole-coin liability and exact-cent cost basis. */
export function resaleLotStep(stake: number, liability: number, costBasis: number): number {
 const cents = (n:number) => Math.round(n * 100);
 if (!Number.isSafeInteger(stake) || stake <= 0 ||
  !Number.isFinite(liability) || liability < 0 || !Number.isFinite(costBasis) || costBasis < 0 ||
  Math.abs(cents(liability)-liability*100)>1e-7 ||
  Math.abs(cents(costBasis)-costBasis*100)>1e-7) throw new Error('Posição inválida para fracionamento');
 const gcd=(a:number,b:number):number=>{while(b){[a,b]=[b,a%b];}return a;};
 const lcm=(a:number,b:number)=>a/gcd(a,b)*b;
 const liabilityStep=(stake*100)/gcd(stake*100,cents(liability));
 const basisStep=stake/gcd(stake,cents(costBasis));
 const step=lcm(liabilityStep,basisStep);
 return step<=stake?step:stake;
}

/** Gross cash returned at resolution to the final owner, NOT the collateral balance. */
export function positionPayoff(stake: number, liability: number): number {
 if (!Number.isFinite(stake) || !Number.isFinite(liability) || stake<=0 || liability<0) throw new Error('Posição inválida');
 return Math.round((stake+liability)*100)/100;
}
/** P&L for final owner after resolution, based on their actual acquisition cost. */
export function positionSettlementPnl(payoff: number, costBasis: number): number {
 if(!Number.isFinite(payoff)||payoff<0||!Number.isFinite(costBasis)||costBasis<0) throw new Error('Liquidação inválida');
 return Math.round((payoff-costBasis)*100)/100;
}
