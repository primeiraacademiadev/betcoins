import { describe, it, expect } from 'vitest';
import { classifyError, errorFor, errorText, validateOdd, validateStake, validateYtd, validatePrice, validateDateRange } from './uxErrors';

describe('validação contextual', () => {
 it('odd 1,00 é inválida antes da RPC, com exemplo de 12 ฿ e lucro 2 ฿', () => {
  const error=validateOdd('1.00');
  expect(error?.code).toBe('ODD_TOO_LOW');
  expect(errorText(error!)).toContain('12 ฿');
  expect(errorText(error!)).toContain('2 ฿');
  expect(error?.field).toBe('odds');
 });
 it('aceita 1,20 e 1000,00; rejeita odd com mais de duas casas', () => {
  expect(validateOdd('1.20')).toBeNull();
  expect(validateOdd('1000')).toBeNull();
  expect(validateOdd('1.234')?.code).toBe('ODD_PRECISION');
 });
 it('stake não pode ser decimal, zero ou vazia', () => {
  for(const value of ['1.5','0','','-3']) expect(validateStake(value)?.code).toBe('STAKE_INVALID');
  expect(validateStake('10')).toBeNull();
 });
 it('YTD não pode ser menor que −100 nem NaN', () => {
  expect(validateYtd('-100')).toBeNull();
  expect(validateYtd('-101')?.code).toBe('INVALID_YTD');
  expect(validateYtd('')?.code).toBe('INVALID_YTD');
 });
 it('preço exige cêntimos exatos', () => {
  expect(validatePrice('4.20')).toBeNull();
  expect(validatePrice('4.201')?.code).toBe('INVALID_PRICE');
 });
 it('datas devem ser válidas e por ordem', () => {
  expect(validateDateRange('2026-11-16T10:00','2026-11-17T10:00')).toBeNull();
  expect(validateDateRange('2026-11-17T10:00','2026-11-16T10:00')?.code).toBe('INVALID_DATE');
 });
});
describe('catálogo de erros RPC', () => {
 it('não confunde saldo insuficiente com falta de autorização', () => {
  expect(classifyError({code:'23514', detailMessage:'saldo insuficiente'}).code).toBe('INVALID_SELECTION');
  expect(classifyError({code:'42501',detailMessage:'permission denied'}).code).toBe('NOT_AUTHORIZED');
  expect(classifyError({detailMessage:'saldo insuficiente'}).code).toBe('BALANCE_INSUFFICIENT');
 });
 it('identifica conflitos, mercados fechados e posições já vendidas', () => {
  expect(classifyError({detailMessage:'Oferta indisponível'}).code).toBe('OFFER_UNAVAILABLE');
  expect(classifyError({detailMessage:'Mercado fechado'}).code).toBe('MARKET_CLOSED');
  expect(classifyError({detailMessage:'Posição indisponível'}).code).toBe('POSITION_UNAVAILABLE');
 });
 it('erros de rede não afirmam que a operação falhou', () => {
  const x=classifyError(new TypeError('Failed to fetch'));
  expect(x.code).toBe('NETWORK_UNCERTAIN');
  expect(errorText(x)).toContain('antes de repetir');
 });
 it('erros desconhecidos nunca devolvem SQL nem detalhes sensíveis', () => {
  const x=classifyError({code:'XX123',detailMessage:'secret password=123; SQL select * from auth.users'});
  expect(x.code).toBe('UNKNOWN');
  expect(errorText(x)).not.toMatch(/password|auth\.users|select \*/i);
 });
 it('há ação corretiva, explicação e título para todos os códigos', () => {
  for(const code of ['ODD_TOO_LOW','BALANCE_INSUFFICIENT','NOT_AUTHORIZED','NETWORK_UNCERTAIN','UNKNOWN'] as const) {
   const e=errorFor(code);
   expect(e.title.length).toBeGreaterThan(4);
   expect(e.explanation.length).toBeGreaterThan(12);
   expect(e.action.length).toBeGreaterThan(10);
  }
 });
});
