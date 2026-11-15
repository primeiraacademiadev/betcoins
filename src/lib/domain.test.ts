import { describe, it, expect } from 'vitest';
import { sprintReturn, liability, impliedProbability, resalePnl, resaleLotStep, positionPayoff, positionSettlementPnl } from './domain';
describe('regras económicas', () => {
 it('variação do sprint é a diferença de YTD em pontos percentuais', () => expect(sprintReturn(10,21)).toBe(11));
 it('a diferença de YTD suporta perdas completas e valores negativos', () => expect(sprintReturn(-100,-85)).toBe(15));
 it('rejeita valores de YTD não finitos', () => expect(() => sprintReturn(Number.NaN,3)).toThrow());
 it('a responsabilidade lay é apenas o lucro back', () => expect(liability(10,1.2)).toBe(2));
 it('odds têm probabilidade implícita', () => expect(impliedProbability(2)).toBe(50));
 it('não aceita stake negativa', () => expect(() => liability(-1,2)).toThrow());
});

describe('revenda de posições', () => {
 it('apura perda na venda abaixo do custo', () => expect(resalePnl(8,10)).toBe(-2));
 it('apura ganho na venda acima do custo', () => expect(resalePnl(15,10)).toBe(5));
 it('apura ganho em revenda sucessiva pelo custo do titular atual', () => expect(resalePnl(11,8)).toBe(3));
 it('não aceita preço de venda inválido', () => expect(() => resalePnl(0,8)).toThrow());
});

describe('lotes indivisíveis', () => {
 it('10:30 permite lotes 1:3', () => expect(resaleLotStep(10,30,10)).toBe(1));
 it('30:10 permite 3:1, mas não 1:1/3', () => expect(resaleLotStep(30,10,30)).toBe(3));
 it('20:12 permite 5:3', () => expect(resaleLotStep(20,12,20)).toBe(5));
 it('7:3 só permite venda integral', () => expect(resaleLotStep(7,3,7)).toBe(7));
 it('inclui custo de aquisição na indivisibilidade', () => expect(resaleLotStep(10,30,0.03)).toBe(10));
 it('rejeita valores fracionados em cêntimos', () => expect(() => resaleLotStep(10,1.005,10)).toThrow());
});

describe('liquidação económica de posições', () => {
 it('comprador BACK a 8 recebe 12 e lucra 4', () => expect(positionSettlementPnl(positionPayoff(10,2),8)).toBe(4));
 it('comprador BACK a 8 perde 8 se não vencer', () => expect(positionSettlementPnl(0,8)).toBe(-8));
 it('LAY que não acerta recebe zero e perde o custo', () => expect(positionSettlementPnl(0,3)).toBe(-3));
 it('separa resultado de revenda do resultado posterior do comprador', () => {expect(resalePnl(8,10)).toBe(-2);expect(positionSettlementPnl(12,8)).toBe(4);});
});
