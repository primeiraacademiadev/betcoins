import {useEffect,useState} from 'react';
import {rpc} from '../lib/supabase';
import type {MarketCategory} from '../lib/domain';
import {observeRequest} from '../lib/competition';
import {type MarketClassification} from '../lib/marketModes';
import {ClassificationDetails,resolutionMessage} from './MarketSettlement';
export function PreviousPeriodNotice({championship,sprint}:{championship:string;sprint:string|null}){
 const [previous,setPrevious]=useState<{name?:string;ends_at?:string;unavailable?:boolean}|null>(null),[failed,setFailed]=useState(false);
 useEffect(()=>{
  setPrevious(null);setFailed(false);
  if(!championship)return;
  return observeRequest(rpc<{name?:string;ends_at?:string;unavailable?:boolean}>('get_previous_market_period',{p_championship:championship,p_sprint:sprint}),setPrevious,()=>setFailed(true));
 },[championship,sprint]);
 return <p className="footnote" role="status">{failed?'Não foi possível consultar o período anterior.':!championship?'Seleciona o período atual.':!previous?'A consultar o período anterior…':previous.unavailable?'Não existe um período anterior único registado. Não é possível criar esta modalidade.':'Referência: '+previous.name+' · fecho '+new Date(previous.ends_at!).toLocaleString('pt-PT')+'. O snapshot de fecho terá de existir antes da validação.'}</p>;
}
export function PublicMarketClassification({marketId,category,revision}:{marketId:string;category?:MarketCategory;revision?:unknown}){
 const [review,setReview]=useState<MarketClassification|null>(null),[failed,setFailed]=useState(false);
 useEffect(()=>{
  setReview(null);setFailed(false);
  return observeRequest(rpc<MarketClassification>('get_market_classification',{p_market:marketId}),setReview,()=>setFailed(true));
 },[marketId,revision]);
 return <section className="panel"><h2>Classificação desta aposta</h2>{review?<>{review.status!=='validated'&&<p className="footnote" role="status">{review.status==='ready_for_validation'?'Snapshots disponíveis — aguarda revisão e validação.':resolutionMessage(review.status)}</p>}<ClassificationDetails review={review} category={category}/></>:<p role="status">{failed?'Classificação indisponível. Atualiza os dados.':'A consultar os snapshots…'}</p>}</section>;
}
