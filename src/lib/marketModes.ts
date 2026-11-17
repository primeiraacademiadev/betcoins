import type {EntryReference} from './entryBaselines';
import type {ScoreAudit} from './finalDeclarations';
export type MarketMode='snapshot_value'|'snapshot_delta_previous';
export function modeLabel(mode:string|null|undefined,_kind?:string):string {
 if(mode==='snapshot_value')return 'Valor YTD no snapshot de fecho (%)';
 if(mode==='snapshot_delta_previous')return 'Variação desde o fecho do período anterior (pp)';
 return 'Modalidade indisponível';
}
export type MarketClassificationRow=ScoreAudit & EntryReference & {competitor_id:string;nickname:string;end_ytd:number|null;previous_ytd:number|null;value:number|null;place:number|null;status:string};
export type MarketClassification={status:string;mode:MarketMode;unit:'%'|'pp';rows:MarketClassificationRow[];can_validate:boolean;
 current_capture:{id:string;cutoff_at:string}|null;previous_capture:{id:string;cutoff_at:string}|null;
 validation:{id:string;note:string;validated_at:string}|null};
