export type MarketKind = 'annual' | 'weekly' | 'monthly';
export type MarketCategory = 'winner' | 'second' | 'last';
export type OrderSide = 'back' | 'lay';
export type Profile = { id: string; nickname: string; role: 'spectator'|'competitor'|'admin' };
export type Championship = { id: string; name: string; ends_at: string };
export type Competitor = { id: string; nickname: string; ytd: number; updated_at: string | null };
export type Market = { id: string; title: string; kind: MarketKind; category: MarketCategory; closes_at: string; state: string; winner_outcome_id?: string | null };
export type Outcome = { id: string; market_id: string; label: string; competitor_id: string };
export type Offer = { id: string; market_id: string; outcome_id: string; owner_id: string; side: OrderSide; odds: number; stake_remaining: number; created_at: string };
export type Position = { id: string; trade_id: string; owner_id: string; side: OrderSide; outcome_id: string; market_id: string; stake: number; liability: number; status: string };
export type Listing = { id: string; position_id: string; seller_id: string; price: number; state: string; created_at: string };
export type Wallet = { available: number; reserved: number; total_issued: number };
export type Ranking = { nickname: string; available: number; reserved: number; issued: number };
export type Application = { id: string; candidate_id: string; nickname: string; state: string; yes_votes: number; eligible_votes: number };
export function sprintReturn(start: number, end: number): number {
  if (start <= -100) throw new Error('O YTD inicial não pode ser inferior ou igual a -100%.');
  return ((1 + end / 100) / (1 + start / 100) - 1) * 100;
}
export function impliedProbability(odds: number): number { if (odds <= 1) throw new Error('Odd inválida'); return 100 / odds; }
export function liability(stake: number, odds: number): number {
  if (!Number.isInteger(stake) || stake <= 0 || !Number.isFinite(odds) || odds <= 1) throw new Error('Oferta inválida');
  return Math.round(stake * (odds - 1) * 100) / 100;
}
export function formatCoins(value: number) { return new Intl.NumberFormat('pt-PT', {maximumFractionDigits:2}).format(value); }
