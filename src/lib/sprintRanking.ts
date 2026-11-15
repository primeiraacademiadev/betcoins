/** Presentation of the existing start/end sprint RPC only.
 * Does not select market outcomes or authorize settlement.
 */
export type SprintResult = {
 competitor_id: string;
 nickname: string;
 start_ytd: number;
 end_ytd: number;
 return_pct: number;
};

export function rankSprintResults(results: SprintResult[]): Array<SprintResult & {place:number}> {
 // PostgreSQL supplies an exact numeric delta rounded to four decimal places.
 // Keep that precision for ties; formatting to two decimals is presentation only.
 const sorted = results.slice().sort((a,b) =>
  Number(b.return_pct)-Number(a.return_pct) ||
  (a.competitor_id < b.competitor_id ? -1 : a.competitor_id > b.competitor_id ? 1 : 0));
 let place = 0;
 return sorted.map((row,index) => {
  if(index===0 || Number(row.return_pct)!==Number(sorted[index-1].return_pct))place=index+1;
  return {...row,place};
 });
}
