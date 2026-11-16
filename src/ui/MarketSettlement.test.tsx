import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {ResolutionDetails,resolutionMessage} from './MarketSettlement';
describe('validated settlement presentation',()=>{
 it('explains a relevant tie without promising refunds or a technical tiebreak',()=>{
  expect(resolutionMessage('tie_unsupported')).toContain('liquidação bloqueada');
  expect(resolutionMessage('tie_unsupported')).toContain('zero');
 });
 it.each(['unlinked','awaiting_validation','incomplete','universe_changed','period_mismatch'])('explains why %s is blocked',status=>{
  const html=renderToStaticMarkup(<ResolutionDetails result={{status}} winner="Escolha manual"/>);
  expect(html).not.toContain('Resultado validado:');
  expect(html).not.toContain('Escolha manual');
  expect(html).toContain('role="status"');
 });
 it('shows the server-derived winner safely and identifies the existing sprint criterion',()=>{
  const html=renderToStaticMarkup(<ResolutionDetails result={{status:'ready',criterion:'sprint_delta_start_end'}} winner="A <B>"/>);
  expect(html).toContain('A &lt;B&gt;');
  expect(html).toContain('próprio sprint');
  expect(html).toContain('ainda não estão disponíveis');
 });
 it('does not interpret an unknown status as permission to settle',()=>{
  expect(resolutionMessage('new_state')).toContain('indisponível');
 });
});
