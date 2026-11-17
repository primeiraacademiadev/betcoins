import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {LegacyPreview,type LegacyPlan,LegacyMarkets} from './LegacyMarkets';
const plan:LegacyPlan={fingerprint:'f',status:'ready',can_apply:true,eligible:[{},{}],remove:[{id:'x',label:'Sem declaração'}],add:[{competitor_id:'a',label:'Entrada auditada'}]};
describe('legacy market reconciliation presentation',()=>{
 it('shows the exact outcome changes for review',()=>{const h=renderToStaticMarkup(<LegacyPreview plan={plan}/>);expect(h).toContain('Retirar outcomes sem entrada efetiva: Sem declaração');expect(h).toContain('Acrescentar outcomes com YTD inicial: Entrada auditada');expect(h).toContain('Participações efetivas: 2');});
 it('explains why financial contracts require a separate decision',()=>{const h=renderToStaticMarkup(<LegacyPreview plan={{...plan,status:'contracts_preserved',can_apply:false}}/>);expect(h).toContain('sem alteração automática');expect(h).toContain('Empate/zero continua bloqueado');});
 it('distinguishes unavailable data and historical preservation',()=>{expect(renderToStaticMarkup(<LegacyPreview plan={{...plan,status:'awaiting_initial_scores'}}/>)).toContain('Faltam duas participações');expect(renderToStaticMarkup(<LegacyPreview plan={{...plan,status:'historical_preserved'}}/>)).toContain('período fechado');});
 it('requires an explicit preview and does not expose apply on initial render',()=>{const h=renderToStaticMarkup(<LegacyMarkets markets={[]} championships={[]} sprints={[]} busy={false} act={async()=>{}}/>);expect(h).toContain('Pré-visualizar reconciliação');expect(h).toContain('Valor no fecho (%)');expect(h).toContain('Variação no período (pp)');expect(h).not.toContain('Aplicar reconciliação revista');});
});
