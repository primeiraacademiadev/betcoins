import { describe, it, expect } from 'vitest';
import { sprintReturn, liability, impliedProbability, resalePnl } from './domain';
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
