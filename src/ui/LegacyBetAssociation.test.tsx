import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {AssociationPreview,LegacyBetAssociation,type AssociationPlan} from './LegacyBetAssociation';
import {marketsForOccurrence} from '../lib/recurringBets';
import type {Market} from '../lib/domain';
const plan:AssociationPlan={fingerprint:'f',status:'ready',can_apply:true,historical:false,paused:true,occupied_by:null,outcomes:[{},{}]};
describe('reviewed association of legacy contracts',()=>{
 it('explains the operational effect of a paused definition',()=>{const h=renderToStaticMarkup(<AssociationPreview plan={plan}/>);expect(h).toContain('negociação fica suspensa');expect(h).toContain('recolha de fecho');expect(h).toContain('Mantêm-se os 2 outcomes');});
 it('distinguishes archive organization from new final obligations',()=>{const h=renderToStaticMarkup(<AssociationPreview plan={{...plan,historical:true}}/>);expect(h).toContain('apenas organização e consulta');expect(h).not.toContain('negociação fica suspensa');expect(h).toContain('Empate/zero continua bloqueado');});
 it('shows slot collisions without proposing deletion or merger',()=>{const h=renderToStaticMarkup(<AssociationPreview plan={{...plan,status:'slot_occupied',can_apply:false}}/>);expect(h).toContain('sem fundir contratos');});
 it('requires preview before allowing association',()=>{const h=renderToStaticMarkup(<LegacyBetAssociation championships={[]} markets={[]} definitions={[]} occurrences={[]} busy={false} act={async()=>{}}/>);expect(h).toContain('Pré-visualizar associação');expect(h).not.toContain('Associar mercado revisto');});
 it('moves the existing identity to the recurring filter without duplication',()=>{const original:Market={id:'legacy',title:'Contrato',kind:'weekly',category:'winner',state:'open',closes_at:'2026-11-20T21:00Z',mode:'snapshot_value'};const associated={...original,definition_id:'d',occurrence_id:'o'};expect(marketsForOccurrence([associated],'','')).toEqual([]);expect(marketsForOccurrence([associated],'d','o')).toEqual([associated]);expect(marketsForOccurrence([associated],'d','other')).toEqual([]);});
});
