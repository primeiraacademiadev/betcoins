import {describe,it,expect} from 'vitest';
import {highlightedCompetitors} from './marketResults';
describe('highlighting the position paid by each market',()=>{
 const rows=[{competitor_id:'a',place:1,value:18},{competitor_id:'b',place:2,value:16},{competitor_id:'c',place:3,value:3}];
 it('distinguishes first, second and last on one shared classification',()=>{expect([...highlightedCompetitors(rows,'winner')]).toEqual(['a']);expect([...highlightedCompetitors(rows,'second')]).toEqual(['b']);expect([...highlightedCompetitors(rows,'last')]).toEqual(['c']);});
 it('does not invent second place from a first-place tie; last remains independent',()=>{const tied=[rows[0],{...rows[1],place:1,value:18},rows[2]];expect([...highlightedCompetitors(tied,'winner')]).toEqual(['a','b']);expect([...highlightedCompetitors(tied,'second')]).toEqual([]);expect([...highlightedCompetitors(tied,'last')]).toEqual(['c']);});
 it('distinguishes a real zero from missing scores',()=>{expect([...highlightedCompetitors([{competitor_id:'z',place:1,value:0},{competitor_id:'n',place:null,value:null}],'winner')]).toEqual(['z']);});
});
