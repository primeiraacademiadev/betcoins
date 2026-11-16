export type EntryBaseline={championship_id:string;name:string;admitted_at:string;baseline_id:string|null;ytd:number|null;effective_at:string|null;source_kind:string|null;status:'active'|'awaiting_initial'};
export type EntryReference={reference_kind?:'entry_baseline'|'previous_snapshot'|null;reference_at?:string|null;entry_baseline_id?:string|null;entry_effective_at?:string|null;admitted_at?:string|null;participation_status?:string};
export function entryStatusLabel(entry:EntryBaseline):string {
 return entry.status==='active'?'Participação ativa':'Admitido — aguarda YTD inicial';
}
