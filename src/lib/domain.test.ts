import { describe, it, expect } from 'vitest';
import { sprintReturn, liability, impliedProbability, resalePnl } from './domain';
describe('regras económicas', () => {
 it('retorno do sprint é composto e não diferença de YTD', () => expect(sprintReturn(10,21)).toBeCloseTo(10));
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
