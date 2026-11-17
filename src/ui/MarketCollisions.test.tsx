import {describe,it,expect} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {CollisionPreview,CollisionReview,ReplacedMarkets,type CollisionPlan} from './MarketCollisions';
import {marketsForOccurrence,marketTradingBlocked} from '../lib/recurringBets';
import type {Market} from '../lib/domain';
const legacy:Market={id:'l',title:'Contrato legado',kind:'weekly',category:'winner',state:'open',closes_at:'2026-12-31T23:59:59Z',definition_id:'d',occurrence_id:'o'};
const generated:Market={...legacy,id:'g',title:'Mercado gerado',definition_id:null,occurrence_id:null,replaced_by_market_id:'l'};
const plan:CollisionPlan={fingerprint:'f',status:'ready',can_apply:true,paused:false,generated_market_id:'g',legacy_market_id:'l',legacy:{before_market:legacy},generated:{before_market:generated}};
describe('legacy/generated market collisions',()=>{
 it('identifies both contracts and explains preservation without financial merger',()=>{const h=renderToStaticMarkup(<CollisionPreview plan={plan}/>);expect(h).toContain('Contrato legado');expect(h).toContain('Mercado gerado');expect(h).toContain('Não se apagam mercados');expect(h).toContain('Não há fusão de posições');expect(h).toContain('Empate/zero continua bloqueado');});
 it('explains why even an offer history prevents replacement',()=>{const h=renderToStaticMarkup(<CollisionPreview plan={{...plan,status:'generated_contracts_preserved',can_apply:false}}/>);expect(h).toContain('ambos os contratos são preservados');});
 it('warns about the existing suspension',()=>{expect(renderToStaticMarkup(<CollisionPreview plan={{...plan,paused:true}}/>)).toContain('legado fica suspenso');});
 it('requires a dedicated collision preview before exposing apply',()=>{const h=renderToStaticMarkup(<CollisionReview params={{p_market:'l',p_definition:'d',p_occurrence:'o'}} busy={false} act={async()=>{}} onResolved={()=>{}}/>);expect(h).toContain('Rever colisão com o gerado');expect(h).not.toContain('Manter legado e arquivar gerado intacto');});
 it('excludes the archived generated identity from trading and normal market lists',()=>{expect(marketsForOccurrence([generated,legacy],'','')).toEqual([]);expect(marketsForOccurrence([generated,legacy],'d','o')).toEqual([legacy]);expect(marketTradingBlocked(generated,[],Date.parse('2026-11-17'))).toBe(true);});
 it('keeps an archive reference to the surviving market',()=>{const h=renderToStaticMarkup(<ReplacedMarkets markets={[generated,legacy]} onOpen={()=>{}}/>);expect(h).toContain('Gerados substituídos');expect(h).toContain('Substituído por Contrato legado');expect(h).toContain('Consultar mercado mantido');});
});
