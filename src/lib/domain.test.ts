import { describe, it, expect } from 'vitest';
import { sprintReturn, liability, impliedProbability } from './domain';
describe('regras económicas', () => {
 it('retorno do sprint é composto e não diferença de YTD', () => expect(sprintReturn(10,21)).toBeCloseTo(10));
 it('a responsabilidade lay é apenas o lucro back', () => expect(liability(10,1.2)).toBe(2));
 it('odds têm probabilidade implícita', () => expect(impliedProbability(2)).toBe(50));
 it('não aceita stake negativa', () => expect(() => liability(-1,2)).toThrow());
});
