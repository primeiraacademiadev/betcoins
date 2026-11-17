import { useEffect, useState, type ReactNode } from 'react';
import { ArrowRight, ChartNoAxesCombined, Check, CircleDollarSign, Coins, ExternalLink, LogIn, LogOut, Menu, Plus, RefreshCw, Shield, Trophy, Wallet as WalletIcon } from 'lucide-react';
import type { User } from '@supabase/supabase-js';
import { client, configured, rpc, selectRows } from '../lib/supabase';
import { useToast } from './ToastProvider';
import { classifyError, errorFor, errorText, validateOdd, validateStake, validatePrice, validateYtd, validateDateRange } from '../lib/uxErrors';
import { acceptanceTerms, formatCoins, positionPayoff, resaleLotStep, type PositionSale, type PositionSettlement, type Application, type Competitor, type LedgerEntry, type Listing, type Market, type Offer, type Outcome, type Position, type Ranking, type Wallet } from '../lib/domain';
type Sprint = {id:string;championship_id:string;name:string;kind:string;starts_at:string;ends_at:string;state:string};
import { rankCurrentCompetitors } from '../lib/competition';
import { CompetitionReview } from './CompetitionReview';
import { MarketSettlement } from './MarketSettlement';
import {modeLabel} from '../lib/marketModes';
import {OccurrencePicker,RecurringBets} from './RecurringBets';
import {RecurringProvisional} from './RecurringProvisional';
import {FinalDeclarations,FinalRoundManagement} from './FinalDeclarations';
import {EntryBaselines} from './EntryBaselines';
import {marketTradingBlocked,marketsForOccurrence,type BetDefinition,type BetOccurrence} from '../lib/recurringBets';
import {PublicMarketClassification} from './MarketModes';
import {MarketActivity} from './MarketActivity';
import {OccurrenceResults} from './OccurrenceResults';
type WalletReconciliation = {owner_id:string;nickname:string;actual_available:number;ledger_available:number;available_difference:number;actual_reserved:number;ledger_reserved:number;reserved_difference:number;actual_issued:number;ledger_issued:number;issued_difference:number;balanced:boolean};
type Tab = 'overview'|'markets'|'wallet'|'admissions'|'admin'|'account';
const title:Record<Tab,string> = {overview:'Campeonato',markets:'Mercados',wallet:'Carteira',admissions:'Admissões',admin:'Gestão',account:'A minha conta'};
function tradeTerms(side:'back'|'lay',stake:number,odds:number){const liability=Math.round(stake*(odds-1)*100)/100;return {risk:side==='back'?stake:liability,profit:side==='back'?liability:stake,payout:stake+liability};}
async function getSpectatorRankings(asOf:string|null):Promise<Ranking[]> {
 try {return await rpc<Ranking[]>('get_spectator_rankings',{p_as_of:asOf});}
 catch(error) {
  if(asOf!==null)throw error;
  // Maintain the published MVP until the incremental Supabase migration is applied.
  const old=await rpc<Array<{nickname:string;available:number;reserved:number;issued:number}>>('get_rankings');
  return old.map((r,i)=>({
   owner_id:'legacy-'+i+'-'+r.nickname,nickname:r.nickname,
   available:Number(r.available),reserved:Number(r.reserved),issued:Number(r.issued),
   wealth:Number(r.available)+Number(r.reserved),
   relative_pct:Number(r.issued)>0?
    100*(Number(r.available)+Number(r.reserved)-Number(r.issued))/Number(r.issued):null,
   realized_resale_pnl:0,open_positions:null,exposure:null,
   valuation_status:'contabilistico_legacy'
  }));
 }
}
function Coin({amount}:{amount:number}){return <span className="coin-amount"><span className="coin-glyph">฿</span> {formatCoins(amount)}</span>}
function Button({children,onClick,disabled=false,subtle=false}:{children:ReactNode;onClick:()=>void;disabled?:boolean;subtle?:boolean}){return <button className={subtle?'button secondary':'button'} onClick={onClick} disabled={disabled}>{children}</button>}
export function App(){
 const [user,setUser]=useState<User|null>(null),[tab,setTab]=useState<Tab>('overview'),[busy,setBusy]=useState(false),[authOpen,setAuthOpen]=useState(false);
 const toast=useToast();
 const [competitors,setCompetitors]=useState<Competitor[]>([]),[markets,setMarkets]=useState<Market[]>([]),[outcomes,setOutcomes]=useState<Outcome[]>([]),[offers,setOffers]=useState<Offer[]>([]),[positions,setPositions]=useState<Position[]>([]),[listings,setListings]=useState<Listing[]>([]),[wallet,setWallet]=useState<Wallet|null>(null),[rankings,setRankings]=useState<Ranking[]>([]),[apps,setApps]=useState<Application[]>([]);
 const [profile,setProfile]=useState<{nickname:string}|null>(null);
 const [reconciliation,setReconciliation]=useState<WalletReconciliation[]|null>(null);
 const [positionSales,setPositionSales]=useState<PositionSale[]>([]),[positionSettlements,setPositionSettlements]=useState<PositionSettlement[]>([]);
 const [ledger,setLedger]=useState<LedgerEntry[]>([]);const [isCompetitor,setIsCompetitor]=useState(false),[isAdmin,setIsAdmin]=useState(false);
 const [rankMode,setRankMode]=useState<'wealth'|'relative'>('wealth');
 const [rankWindow,setRankWindow]=useState<'now'|'week'|'month'>('now'),[rankAsOf,setRankAsOf]=useState<string|null>(null);
 const [sprints,setSprints]=useState<Sprint[]>([]),[selectedSprint,setSelectedSprint]=useState('');
 const [championships,setChampionships]=useState<Array<{id:string;name:string}>>([]);
 const [sprintName,setSprintName]=useState(''),[sprintKind,setSprintKind]=useState('weekly'),[sprintStart,setSprintStart]=useState(''),[sprintEnd,setSprintEnd]=useState('');
 const [acceptAmounts,setAcceptAmounts]=useState<Record<string,string>>({});
 const [definitions,setDefinitions]=useState<BetDefinition[]>([]),[occurrences,setOccurrences]=useState<BetOccurrence[]>([]);
 const [finalBlocking,setFinalBlocking]=useState(false),[entryBlocking,setEntryBlocking]=useState(false);
 const [categoryFilter,setCategoryFilter]=useState('all');
 const [selectedDefinition,setSelectedDefinition]=useState(''),[selectedOccurrence,setSelectedOccurrence]=useState('');
 async function load(){
  if(!client||!user)return;
  try {
   const [c,m,o,f,p,l,w,r,a,role] = await Promise.all([
     rpc<Competitor[]>('get_competitors'),selectRows<Market>('markets'),selectRows<Outcome>('outcomes'),
     selectRows<Offer>('offers'),selectRows<Position>('positions'),rpc<Listing[]>('get_active_listings'),
     rpc<Wallet>('get_wallet'),getSpectatorRankings(rankAsOf),rpc<Application[]>('get_applications'),rpc<{is_competitor:boolean;is_admin:boolean}>('my_roles')
   ]);
   const ownProfile=(await selectRows<{nickname:string}>('profiles',{column:'id',value:user.id}))[0]||null;setProfile(ownProfile);setNickname(ownProfile?.nickname||'');
   setSprints(await selectRows<Sprint>('sprints'));setChampionships(await selectRows<{id:string;name:string}>('championships'));setLedger(await selectRows<LedgerEntry>('ledger'));
   // Optional newer tables: preserve the existing wallet before Supabase migrations.
   const [sales,settled]=await Promise.allSettled([
     selectRows<PositionSale>('position_sales'), selectRows<PositionSettlement>('position_settlements')
   ]);
   const [defs,periods]=await Promise.allSettled([selectRows<BetDefinition>('bet_definitions'),selectRows<BetOccurrence>('bet_occurrences')]);
   setDefinitions(defs.status==='fulfilled'?defs.value:[]);setOccurrences(periods.status==='fulfilled'?periods.value:[]);
   setPositionSales(sales.status==='fulfilled'?sales.value:[]);
   setPositionSettlements(settled.status==='fulfilled'?settled.value:[]);setCompetitors(c||[]);setMarkets(m||[]);setOutcomes(o||[]);setOffers(f||[]);setPositions(p||[]);setListings(l||[]);setWallet(w);setRankings(r||[]);setApps(a||[]);setIsCompetitor(role?.is_competitor||false);setIsAdmin(role?.is_admin||false);
  }catch(e){toast.error(errorText(classifyError(e)))}
 }
 useEffect(()=>{if(!client)return;client.auth.getUser().then(({data})=>setUser(data.user));const {data:{subscription}}=client.auth.onAuthStateChange((_e,s)=>setUser(s?.user||null));return()=>subscription.unsubscribe()},[]);
 useEffect(()=>{setEntryBlocking(false);setFinalBlocking(false);if(user)void load();else {setWallet(null);setCompetitors([]);setProfile(null)}},[user]);
 async function act(fn:()=>Promise<unknown>, successMessage:string){setBusy(true);try{await fn();if(successMessage)toast.success(successMessage);await load()}catch(e){toast.error(errorText(classifyError(e)))}finally{setBusy(false)}}
 async function login(provider:'google'|'github'){if(!client)return;const {error}=await client.auth.signInWithOAuth({provider,options:{redirectTo:window.location.origin+import.meta.env.BASE_URL}});if(error)toast.error(errorText(classifyError(error)))}
 const [selectedMarket,setSelectedMarket]=useState<string>(''),[selectedOutcome,setSelectedOutcome]=useState<string>(''),[side,setSide]=useState<'back'|'lay'>('back'),[odds,setOdds]=useState('2'),[stake,setStake]=useState('10'),[score,setScore]=useState(''),[nickname,setNickname]=useState(''),[listingPrice,setListingPrice]=useState<Record<string,string>>({}),[listingQuantity,setListingQuantity]=useState<Record<string,string>>({});
 async function showRankingWindow(windowType:'now'|'week'|'month'){
  if(!user)return;
  const asOf=windowType==='now'?null:new Date(Date.now()-(windowType==='week'?7:30)*86400000).toISOString();
  try{
   const rows=await getSpectatorRankings(asOf);
   setRankings(rows);setRankWindow(windowType);setRankAsOf(asOf);
   if(asOf===null&&rows.some(r=>r.valuation_status==='contabilistico_legacy')){
    toast.warning('O ranking histórico e os detalhes económicos estarão disponíveis após a atualização da base de dados.');
   }
  }catch(e){toast.warning('Classificação histórica indisponível até à atualização da base de dados.');}
 }
 const proposedStake=Number(stake),proposedOdds=Number(odds);
 const oddError=validateOdd(odds),stakeError=validateStake(stake);
 const validOffer=!oddError&&!stakeError;
 const proposedTerms=validOffer?tradeTerms(side,proposedStake,proposedOdds):null;
 const offerInsufficient=proposedTerms!==null&&wallet!==null&&Number(wallet.available)<proposedTerms.risk;
 const ytdError=validateYtd(score);
 const sprintDateError=sprintStart||sprintEnd?validateDateRange(sprintStart,sprintEnd):null;
 const visibleMarkets=marketsForOccurrence(markets,selectedDefinition,selectedOccurrence).filter(m=>categoryFilter==='all'||m.category===categoryFilter);
 const current=visibleMarkets.find(m=>m.id===selectedMarket)||visibleMarkets[0];const marketOutcomes=outcomes.filter(o=>o.market_id===current?.id);const marketOffers=offers.filter(o=>o.market_id===current?.id && o.stake_remaining>0);
 const currentTradingBlocked=marketTradingBlocked(current,definitions);
 return <div className="app-shell">
  <aside className="sidebar"><div className="brand"><span className="brand-coin">฿</span><span>BET<span className="gold">COINS</span><small>INVESTMENT LEAGUE</small></span></div><div className="side-section">NAVEGAÇÃO</div>
   {(['overview','markets','wallet','admissions','admin'] as Tab[]).filter(t=>t!=='admin'||isAdmin).map(t=><button key={t} className={'nav '+(tab===t?'active':'')} onClick={()=>setTab(t)}>{t==='overview'?<Trophy/>:t==='markets'?<ChartNoAxesCombined/>:t==='wallet'?<WalletIcon/>:t==='admissions'?<Shield/>:<Menu/>}{title[t]}</button>)}
   <div className="sidebar-bottom"><div className="season"><span className="live-dot"/> TEMPORADA 2026 <small>Termina a 31 de dezembro</small></div><div className="sidebar-foot">BetCoins não tem valor monetário.</div></div></aside>
  <main className="main"><header className="topbar"><div className="breadcrumb">BETCOINS <span>/</span> {title[tab].toUpperCase()}</div><div className="top-actions">{user?<><button className="account-link" title="Gerir a minha conta" onClick={()=>setTab('account')}><span className="account-avatar" aria-hidden="true">{(profile?.nickname||user.email||'?').slice(0,1).toUpperCase()}</span><span className="user-label">{profile?.nickname||'A minha conta'}</span></button><button className="icon-button" title="Atualizar dados" onClick={()=>void load()}><RefreshCw size={18}/></button><button className="icon-button" title="Sair" onClick={()=>void client?.auth.signOut()}><LogOut size={18}/></button></>:configured?<button className="button auth-entry" type="button" aria-expanded={authOpen} aria-controls="auth-options" onClick={()=>setAuthOpen(v=>!v)}><LogIn size={16}/> Entrar / criar conta</button>:<span className="status-notice">Setup pendente</span>}</div></header>
   {!user&&configured&&authOpen&&<section id="auth-options" className="auth-options" aria-label="Entrar ou criar conta"><div className="auth-info"><strong>Entrar ou criar conta</strong><p>Já tens conta? Entras diretamente. É a primeira vez? A conta é criada automaticamente.</p><small>O acesso à plataforma é distinto da candidatura ao campeonato: depois de entrares, podes candidatar-te.</small></div><div className="auth-providers"><button type="button" className="button" onClick={()=>void login('google')}>Continuar com Google</button><button type="button" className="button secondary" onClick={()=>void login('github')}>Continuar com GitHub</button><button type="button" className="auth-close" onClick={()=>setAuthOpen(false)} aria-label="Fechar opções de autenticação">Fechar</button></div></section>}
   <div className="content">{user&&isCompetitor&&<EntryBaselines key={user.id+':entry'} userId={user.id} revision={competitors} busy={busy} act={act} onPending={setEntryBlocking}/>} {user&&isCompetitor&&<FinalDeclarations key={user.id} userId={user.id} revision={competitors} busy={busy} act={act} onPending={setFinalBlocking}/>}
   {!configured&&<section className="warning"><Shield size={18}/><div><strong>Pronto para ligar ao Supabase</strong><p>O frontend foi preparado, mas ainda não está ligado a qualquer base de dados. Consulte <code>SETUP.md</code> após a implementação.</p></div></section>}
   {tab==='overview'&&<><div className="heading"><div><div className="eyebrow">CAMPEONATO DE INVESTIDORES</div><h1>Que vença a melhor carteira<span className="gold">.</span></h1><p>O desempenho real decide o campeonato. As previsões decidem quem domina o mercado.</p></div><div className="date-pill"><span className="live-dot"/> CAMPEONATO 2026</div></div>
    <div className="stat-grid"><div className="stat"><span>CONCORRENTES</span><strong>{competitors.length}</strong><small>Em competição</small></div><div className="stat"><span>MERCADOS</span><strong>{markets.filter(m=>m.state==='open').length}</strong><small>Em negociação</small></div><div className="stat"><span>O TEU PATRIMÓNIO</span><strong>{wallet?<Coin amount={wallet.available+wallet.reserved}/>: '—'}</strong><small>Disponível + reservado (não marcado a mercado)</small></div></div>
    <div className="two-columns"><section className="panel"><div className="panel-head"><div><span className="eyebrow">01 / PERFORMANCE</span><h2>Leaderboard YTD · provisório</h2></div><Trophy size={20}/></div>{competitors.length?rankCurrentCompetitors(competitors).map(c=><div className="rank-row" key={c.id}><span className="rank-number">{c.place===null?'—':String(c.place).padStart(2,'0')}</span><span className="rank-name">{c.nickname}<small className="movement-date">{c.place===null?'Admitido — aguarda primeiro YTD':'Declaração: '+new Date(c.updated_at!).toLocaleString('pt-PT')}</small></span><strong>{c.place===null?'Sem declaração':Number(c.ytd).toFixed(4)+'%'}</strong></div>):<Empty text="Ainda não existem concorrentes aprovados."/>}</section><section className="panel"><div className="panel-head"><div><span className="eyebrow">02 / BETCOINS</span><h2>Top espectadores</h2></div><Coins size={20}/></div><div className="market-pills"><button className={'market-pill '+(rankMode==='wealth'?'selected':'')} onClick={()=>setRankMode('wealth')}>Maior património</button><button className={'market-pill '+(rankMode==='relative'?'selected':'')} onClick={()=>setRankMode('relative')}>Maior valorização</button></div>
    <div className="market-pills" aria-label="Período da classificação">
     <button className={'market-pill '+(rankWindow==='now'?'selected':'')} onClick={()=>void showRankingWindow('now')}>Atual</button>
     <button className={'market-pill '+(rankWindow==='week'?'selected':'')} onClick={()=>void showRankingWindow('week')}>Há 7 dias</button>
     <button className={'market-pill '+(rankWindow==='month'?'selected':'')} onClick={()=>void showRankingWindow('month')}>Há 30 dias</button>
    </div>
    {rankAsOf&&<p className="footnote">Classificação reconstruída a partir do ledger até {new Date(rankAsOf).toLocaleString('pt-PT')}.</p>}
    {rankings.length?[...rankings].sort((a,b)=>rankMode==='wealth'?Number(b.wealth)-Number(a.wealth):Number(b.relative_pct??-Infinity)-Number(a.relative_pct??-Infinity)).slice(0,20).map((r,i)=><div className="rank-row spectator-rank" key={r.owner_id}>
      <span className="rank-number">{String(i+1).padStart(2,'0')}</span>
      <div className="rank-name"><strong>{r.nickname}</strong>
       <small className="ranking-detail">Disponível: {formatCoins(Number(r.available))} ฿ · Reservado: {formatCoins(Number(r.reserved))} ฿ · Créditos: {formatCoins(Number(r.issued))} ฿</small>
       {r.valuation_status!=='contabilistico_legacy'&&<small className="ranking-detail">P&L realizado em revendas registadas: {formatCoins(Number(r.realized_resale_pnl))} ฿
        {r.open_positions!==null&&<> · Posições abertas: {r.open_positions} · Exposição em colateral: {formatCoins(Number(r.exposure||0))} ฿</>}
       </small>}
      </div>
      <strong className="ranking-value">{rankMode==='wealth'?<Coin amount={Number(r.wealth)}/>:r.relative_pct===null?'—':Number(r.relative_pct).toFixed(2)+'%'}</strong>
    </div>):<Empty text="Sem espectadores para a data selecionada."/>}
    {rankings.some(r=>r.valuation_status==='contabilistico_legacy')&&<p className="footnote">Ranking contabilístico básico disponível. Histórico, exposição e P&L de revendas aguardam migração da base de dados.</p>}
    <p className="footnote">Avaliação <strong>contabilística, sem cotação de mercado</strong>: património = disponível + reservado; valorização relativa = (património − créditos) / créditos. Posições abertas e exposição representam o estado atual (não são reconstruídas nas datas históricas). O P&L indicado inclui apenas revendas registadas; não representa o lucro total nem antecipa ganhos de apostas em aberto. A ausência de liquidez impede uma avaliação fiável ao preço de mercado.</p></section></div>
    {sprints.length>0&&<section className="panel"><div className="panel-head"><h2>Sprints semanais e mensais</h2></div><div className="market-pills">{sprints.map(sp=><button key={sp.id} className={'market-pill '+(selectedSprint===sp.id?'selected':'')} onClick={()=>setSelectedSprint(sp.id)}>{sp.name} · {sp.state}</button>)}</div>
     {user&&selectedSprint&&sprints.find(sp=>sp.id===selectedSprint)?<CompetitionReview key={user.id+':'+selectedSprint} championshipId={sprints.find(sp=>sp.id===selectedSprint)!.championship_id} sprintId={selectedSprint} isAdmin={isAdmin} revision={sprints}/>:<p className="footnote">Seleciona um sprint para consultar o apuramento.</p>}
    </section>}
    {user&&championships.map(ch=><section className="panel" key={ch.id}><div className="panel-head"><h2>Fecho anual · {ch.name}</h2></div><CompetitionReview key={user.id+':'+ch.id} championshipId={ch.id} isAdmin={isAdmin} revision={sprints}/></section>)}
    {isCompetitor&&<section className="panel"><div className="panel-head"><h2>Atualizar a minha valorização YTD</h2></div><div className="inline-form"><input aria-label="Valorização YTD em percentagem" type="number" step=".01" value={score} onChange={e=>setScore(e.target.value)}/>{ytdError&&<span className="field-error" role="alert">{errorText(ytdError)}</span>}<Button disabled={busy||Boolean(ytdError)||finalBlocking||entryBlocking} onClick={()=>void act(()=>rpc('set_my_score',{p_ytd:Number(score)}),'Valorização YTD atualizada.')}>Guardar score</Button></div><p className="footnote">O score é declarado pelo próprio concorrente e fica registado no histórico.</p></section>}
    <section className="callout"><div><span className="eyebrow">ENTRA NO JOGO</span><h2>1 000 BetCoins para começar.</h2><p>Negocia odds, compra posições e tenta antecipar o vencedor. Sem dinheiro real.</p></div><Button onClick={()=>setTab('markets')}>Explorar mercados <ArrowRight size={17}/></Button></section>
   </>}
   {tab==='markets'&&<><SectionTitle kicker="03 / TRADING FLOOR" title="Mercados de previsões" subtitle="Odds negociadas entre participantes. Sem banca e sem garantia de liquidez."/>
    <OccurrencePicker definitions={definitions} occurrences={occurrences} markets={markets} definition={selectedDefinition} occurrence={selectedOccurrence} onSelect={(d,o)=>{setSelectedDefinition(d);setSelectedOccurrence(o);setSelectedMarket('');setSelectedOutcome('')}}/><label>Resultado<select aria-label="Resultado" value={categoryFilter} onChange={e=>{setCategoryFilter(e.target.value);setSelectedMarket('');setSelectedOutcome('')}}><option value="all">Todos os lugares</option><option value="winner">1.º lugar</option><option value="second">2.º lugar</option><option value="last">Último lugar</option></select></label><div className="market-pills">{visibleMarkets.map(m=><button className={'market-pill '+(current?.id===m.id?'selected':'')} key={m.id} onClick={()=>{setSelectedMarket(m.id);setSelectedOutcome('')}}>{m.title}</button>)}</div>
    {!current?<Empty text="Sem mercados para este período. O histórico pode não ter snapshots ou mercados gerados; não são inventados resultados."/>:<><div className="market-summary"><div><span className="eyebrow">{current.kind.toUpperCase()} / {current.category.toUpperCase()}</span><h2>{current.title}</h2><p>{modeLabel(current.mode,current.kind)}</p>{current.entry_reference_enabled&&<p className="footnote">A participação começa no primeiro YTD declarado. Entradas a meio do período usam essa referência no delta e podem comparar janelas diferentes; os períodos seguintes usam o fecho anterior.</p>}{current.previous_closes_at&&<p>Snapshot anterior: {new Date(current.previous_closes_at).toLocaleString('pt-PT')}</p>}<p>Fecha: {new Date(current.closes_at).toLocaleString('pt-PT')} · {current.state}</p></div><span className="badge">{definitions.some(d=>d.id===current.definition_id&&!d.active)?'Negociação suspensa':current.state}</span></div>{current.definition_id&&<RecurringProvisional key={user?.id+':provisional:'+current.id} marketId={current.id} category={current.category} revision={competitors}/>} {current.mode&&<PublicMarketClassification key={user?.id+':'+current.id} marketId={current.id} category={current.category} revision={competitors}/>}{current.occurrence_id&&<OccurrenceResults key={user?.id+':occ:'+current.occurrence_id} occurrenceId={current.occurrence_id} revision={competitors}/>}<MarketActivity key={user?.id+':activity:'+current.id} marketId={current.id} revision={offers}/><div className="two-columns"><section className="panel"><div className="panel-head"><h2>Livro de ofertas</h2></div>{marketOffers.length?marketOffers.map(o=>{
      const n=Number(acceptAmounts[o.id]??o.stake_remaining);
      const takerSide=o.side==='back'?'lay':'back';
      const terms=Number.isInteger(n)&&n>0?acceptanceTerms(o.side,n,Number(o.odds)):null;
      const validQuantity=terms!==null&&n<=Number(o.stake_remaining);
      const enough=wallet!==null&&terms!==null&&Number(wallet.available)>=terms.risk;
      const predicted=marketOutcomes.find(c=>c.id===o.outcome_id)?.label||'o resultado indicado';
      const winCondition=takerSide==='back'?'acontecer':'não acontecer';
      return <div className="offer offer-explained" key={o.id}>
       <div className="offer-details">
        <strong>{predicted}</strong>
        <small>O autor oferece {o.side.toUpperCase()}; ao aceitar, TU assumes {takerSide.toUpperCase()} ({takerSide==='back'?'a favor':'contra'} de {predicted}). Odd {Number(o.odds).toFixed(2).replace('.',',')} · Stake BACK disponível {o.stake_remaining} ฿.</small>
        <small>Mercado P2P integralmente colateralizado: BACK reserva a stake; LAY reserva stake × (odd − 1). Não compras uma aposta ao autor: cada lado compromete o seu próprio colateral.</small>
        {o.owner_id!==user?.id&&<div className="trade-preview" role="status" aria-live="polite">
          {validQuantity&&terms?<>
            <strong>Para {n} ฿ de stake BACK:</strong>
            <span>Capital reservado por ti: {formatCoins(terms.risk)} ฿ · Lucro líquido se acertares: +{formatCoins(terms.profit)} ฿ · Perda máxima se falhares: −{formatCoins(terms.risk)} ฿ · Pagamento total se ganhares: {formatCoins(terms.payout)} ฿.</span>
            <span>Ganhas se {predicted} {winCondition}; caso contrário perdes o capital reservado. Saldo disponível após reserva: {wallet?formatCoins(Number(wallet.available)-terms.risk)+' ฿':'indisponível'}.</span>
            {!enough&&wallet&&<span className="field-error">{errorText(errorFor('BALANCE_INSUFFICIENT'))}</span>}
          </>:<span className="field-error">{errorText(errorFor('STAKE_INVALID'))} A quantidade não pode ultrapassar {o.stake_remaining} ฿.</span>}
        </div>}
       </div>
       {o.owner_id===user?.id?<Button subtle disabled={busy} onClick={()=>void act(()=>rpc('cancel_offer',{p_offer:o.id}),'Oferta cancelada; reserva libertada.')}>Cancelar</Button>
       :<div className="position-sale">
        <input aria-label={'Stake BACK a aceitar para '+predicted} type="number" min="1" max={o.stake_remaining} step="1"
         aria-invalid={!validQuantity} value={acceptAmounts[o.id]??String(o.stake_remaining)}
         onChange={e=>setAcceptAmounts({...acceptAmounts,[o.id]:e.target.value})}/>
        <Button disabled={!user||busy||currentTradingBlocked||!validQuantity||!enough} subtle onClick={()=>{
          if(!terms)return;
          if(window.confirm('ACEITAR OFERTA P2P\nPrevisão: '+predicted+'.\nA tua posição: '+takerSide.toUpperCase()+' ('+(takerSide==='back'?'a favor':'contra')+').\nOdd: '+Number(o.odds).toFixed(2).replace('.',',')+'. Stake BACK: '+n+' ฿.\nCapital reservado: '+formatCoins(terms.risk)+' ฿.\nSe '+predicted+' '+winCondition+': pagamento total '+formatCoins(terms.payout)+' ฿ e lucro líquido +'+formatCoins(terms.profit)+' ฿.\nCaso contrário: pagamento 0 ฿ e perda máxima −'+formatCoins(terms.risk)+' ฿.\nDisponível: '+formatCoins(Number(wallet?.available||0))+' → '+formatCoins(Number(wallet?.available||0)-terms.risk)+' ฿.\nConfirmas?'))
           void act(()=>rpc('accept_offer',{p_offer:o.id,p_stake:n}),'Oferta aceite; posição criada.');
        }}>Aceitar</Button>
       </div>}
      </div>;
     }):<Empty text="Ainda sem ofertas. Sê o primeiro a publicar."/>}</section><section className="panel"><div className="panel-head"><h2>Colocar oferta</h2></div>{user?<><label>Resultado<select value={selectedOutcome} onChange={e=>setSelectedOutcome(e.target.value)}><option value="">Selecionar</option>{marketOutcomes.map(o=><option key={o.id} value={o.id}>{o.label}</option>)}</select></label><label>Posição<select value={side} onChange={e=>setSide(e.target.value as 'back'|'lay')}><option value="back">BACK · A favor</option><option value="lay">LAY · Contra</option></select></label><div className="form-row"><label>Odd decimal<input type="number" min="1.01" step=".01" aria-invalid={Boolean(oddError)} aria-describedby={oddError?'odd-help':undefined} value={odds} onChange={e=>setOdds(e.target.value)}/>{oddError&&<small id="odd-help" className="field-error" role="alert">{errorText(oddError)}</small>}</label><label>Stake (฿)<input type="number" min="1" step="1" aria-invalid={Boolean(stakeError)} aria-describedby={stakeError?'stake-help':undefined} value={stake} onChange={e=>setStake(e.target.value)}/>{stakeError&&<small id="stake-help" className="field-error" role="alert">{errorText(stakeError)}</small>}</label></div><p className="footnote">BACK: ganhas se o resultado acontecer. LAY: ganhas se não acontecer. A stake é a aposta BACK; para LAY, a responsabilidade é stake × (odd − 1).</p>{proposedTerms?<p className="trade-preview" role="status">Risco máximo: <strong>{formatCoins(proposedTerms.risk)} ฿</strong> · Lucro líquido se acertares: <strong>{formatCoins(proposedTerms.profit)} ฿</strong> · Pagamento bruto no acerto: <strong>{formatCoins(proposedTerms.payout)} ฿</strong>. O risco fica reservado até ao cancelamento, negociação ou liquidação.</p>:null}{offerInsufficient&&<p className="field-error" role="alert">{errorText(errorFor('BALANCE_INSUFFICIENT'))}</p>}<Button disabled={busy||!selectedOutcome||!validOffer||offerInsufficient||currentTradingBlocked} onClick={()=>{if(window.confirm('Publicar oferta '+side.toUpperCase()+'?\nRisco máximo reservado: '+formatCoins(proposedTerms!.risk)+' ฿.\nLucro líquido potencial: '+formatCoins(proposedTerms!.profit)+' ฿.'))void act(()=>rpc('place_offer',{p_outcome:selectedOutcome,p_side:side,p_odds:proposedOdds,p_stake:proposedStake}),'Oferta publicada no mercado.')}}><Plus size={16}/> Publicar oferta</Button></>:<Empty text="Inicia sessão para criar ofertas."/>}</section></div><section className="panel"><div className="panel-head"><h2>Mercado secundário · posições à venda</h2></div>{listings.filter(l=>l.market_id===current.id).length?listings.filter(l=>l.market_id===current.id).map(l=><div className="offer" key={l.id}><div><strong>{l.market_title} · {l.outcome_label} · {l.side.toUpperCase()}</strong><small>Preço {formatCoins(l.price)} ฿ · Pagamento bruto se acertar: {formatCoins(Number(l.stake)+Number(l.liability))} ฿ · Risco económico máximo do comprador: {formatCoins(l.price)} ฿ · Lucro líquido se a posição vencer: {formatCoins(Number(l.stake)+Number(l.liability)-Number(l.price))} ฿ · Se perder: −{formatCoins(l.price)} ฿</small></div><Button subtle disabled={busy||!user||(l.seller_id!==user?.id&&currentTradingBlocked)} onClick={()=>{if(l.seller_id===user?.id){void act(()=>rpc('cancel_listing',{p_listing:l.id}),'Anúncio de venda cancelado.');return;}if(window.confirm('Comprar posição secundária '+l.side.toUpperCase()+' por '+formatCoins(l.price)+' ฿?\nA titularidade, o payoff e o colateral da posição passam para ti.\nLucro líquido se vencer: '+formatCoins(Number(l.stake)+Number(l.liability)-Number(l.price))+' ฿.\nPerda se não vencer: '+formatCoins(l.price)+' ฿.'))void act(()=>rpc('buy_position',{p_listing:l.id}),'Posição comprada; titularidade e colateral transferidos.')}}>{l.seller_id===user?.id?'Cancelar':'Comprar'}</Button></div>):<Empty text="Nenhuma posição à venda neste momento."/>}</section></>}
   </>}
   {tab==='wallet'&&<><SectionTitle kicker="04 / A TUA ECONOMIA" title="Carteira BetCoins" subtitle="Movimentos auditáveis e posições de mercado. A moeda não tem valor real."/><div className="stat-grid"><div className="stat"><span>DISPONÍVEL</span><strong>{wallet?<Coin amount={wallet.available}/>: '—'}</strong></div><div className="stat"><span>RESERVADO</span><strong>{wallet?<Coin amount={wallet.reserved}/>: '—'}</strong></div><div className="stat"><span>CRÉDITOS ATRIBUÍDOS</span><strong>{wallet?<Coin amount={wallet.total_issued}/>: '—'}</strong></div></div>
   <div className="two-columns"><section className="panel"><div className="panel-head"><h2>As minhas posições</h2></div>{positions.length?positions.map(p=>{
    const minimum=resaleLotStep(Number(p.stake),Number(p.liability),Number(p.cost_basis??(p.side==='back'?p.stake:p.liability)));
    const qty=Number(listingQuantity[p.id]??p.stake);
    const price=Number(listingPrice[p.id]);
    const validQuantity=Number.isInteger(qty)&&qty>=minimum&&qty<=p.stake&&qty%minimum===0;
    const validPrice=!validatePrice(listingPrice[p.id]||'');
    const allocatedBasis=Number(p.cost_basis??(p.side==='back'?p.stake:p.liability))*qty/p.stake;
    return <div className="position" key={p.id}>
      <div><strong>{outcomes.find(o=>o.id===p.outcome_id)?.label||'Previsão'} · {p.side.toUpperCase()}</strong>
       <small>Stake {p.stake} · Responsabilidade {formatCoins(Number(p.liability))} ฿ · {p.status}</small>
       <small>Custo económico: {formatCoins(Number(p.cost_basis??(p.side==='back'?p.stake:p.liability)))} ฿ · Colateral: {formatCoins(p.side==='back'?Number(p.stake):Number(p.liability))} ฿ · Pagamento se acertar: {formatCoins(positionPayoff(Number(p.stake),Number(p.liability)))} ฿</small>
       {p.status==='open'&&<small>Lucro líquido potencial: {formatCoins(positionPayoff(Number(p.stake),Number(p.liability))-Number(p.cost_basis??(p.side==='back'?p.stake:p.liability)))} ฿ · Perda máxima económica: {formatCoins(Number(p.cost_basis??(p.side==='back'?p.stake:p.liability)))} ฿</small>}
       {positionSettlements.find(x=>x.position_id===p.id)&&<small>Resultado realizado na liquidação: {formatCoins(Number(positionSettlements.find(x=>x.position_id===p.id)!.realized_pnl))} ฿</small>}
       {p.status==='open'&&<small>Lote mínimo: {minimum} stake · {formatCoins(Number(p.liability)*minimum/p.stake)} ฿ de responsabilidade. Apenas múltiplos exatos.</small>}
      </div>
      {p.status==='open'&&<div className="position-sale">
        <input aria-label="Quantidade de stake para revenda" aria-invalid={!validQuantity} title="Stake a vender" type="number" min={minimum} max={p.stake} step={minimum} value={listingQuantity[p.id]??String(p.stake)} onChange={e=>setListingQuantity({...listingQuantity,[p.id]:e.target.value})}/>
        <input aria-label="Preço total de revenda" aria-invalid={!validPrice} placeholder="Preço ฿" type="number" min=".01" step=".01" value={listingPrice[p.id]||''} onChange={e=>setListingPrice({...listingPrice,[p.id]:e.target.value})}/>
        {!validQuantity&&<small className="field-error" role="alert">{errorText(errorFor('INVALID_LOT'))}</small>}{!validPrice&&listingPrice[p.id]&&<small className="field-error" role="alert">{errorText(errorFor('INVALID_PRICE'))}</small>}<Button subtle disabled={busy||!validQuantity||!validPrice||marketTradingBlocked(markets.find(m=>m.id===p.market_id),definitions)} onClick={()=>{
          const liabilitySlice=Number(p.liability)*qty/p.stake;
          const result=price-allocatedBasis;
          if(!window.confirm('Publicar revenda de '+qty+' stake e '+formatCoins(liabilitySlice)+' ฿ de responsabilidade por '+formatCoins(price)+' ฿?\nCusto do lote: '+formatCoins(allocatedBasis)+' ฿.\nResultado se vendido: '+formatCoins(result)+' ฿.\nO colateral só muda quando houver comprador.'))return;
          void act(async()=>{
            try{await rpc('list_position',{p_position:p.id,p_price:price,p_stake:qty});}
            catch(e){
              const failure=e as {code?:string;detailMessage?:string};
              if(qty!==p.stake||(failure.code!=='PGRST202'&&!/schema cache|function.*does not exist/i.test(failure.detailMessage||'')))throw e;
              await rpc('list_position',{p_position:p.id,p_price:price});
            }
          },'Lote colocado à venda.');
        }}>Vender</Button>
      </div>}
    </div>;
  }):<Empty text="Ainda não tens posições."/>}</section></div><section className="panel"><div className="panel-head"><h2>Resultados económicos e revendas</h2></div>
    <p className="footnote">Resultados realizados nas revendas e nas liquidações, separados dos saldos contabilísticos. As dotações de BetCoins não são lucros.</p>
    {positionSales.filter(x=>x.seller_id===user?.id).map(x=><div className="rank-row" key={x.listing_id}><span className="rank-name">Revenda · {new Date(x.traded_at).toLocaleString('pt-PT')}<small className="movement-date">Preço {formatCoins(Number(x.sale_price))} ฿ · Custo {formatCoins(Number(x.seller_cost_basis))} ฿</small></span><strong className={Number(x.realized_pnl)>=0?'positive':'negative'}>{formatCoins(Number(x.realized_pnl))} ฿</strong></div>)}
    {positionSettlements.map(x=><div className="rank-row" key={x.position_id}><span className="rank-name">Liquidação · {new Date(x.settled_at).toLocaleString('pt-PT')}<small className="movement-date">Pagamento {formatCoins(Number(x.payoff))} ฿ · Custo {formatCoins(Number(x.final_cost_basis))} ฿</small></span><strong className={Number(x.realized_pnl)>=0?'positive':'negative'}>{formatCoins(Number(x.realized_pnl))} ฿</strong></div>)}
    {!positionSales.some(x=>x.seller_id===user?.id)&&!positionSettlements.length&&<Empty text="Sem resultados realizados registados."/>}
   </section><section className="panel"><div className="panel-head"><h2>Histórico de movimentos</h2></div>{ledger.length?ledger.slice().reverse().slice(0,30).map(e=><div className="rank-row" key={e.id}><span className="rank-name">{e.reason.replaceAll('_',' ')}<small className="movement-date">{new Date(e.created_at).toLocaleString('pt-PT')}</small></span><strong className={e.available_delta>=0?'positive':'negative'}>{e.available_delta>0?'+':''}{formatCoins(e.available_delta)} ฿</strong></div>):<Empty text="Ainda sem movimentos registados."/>}</section>
   </>}
   {tab==='admissions'&&<><SectionTitle kicker="05 / COMUNIDADE" title="Admissões ao campeonato" subtitle="Os concorrentes decidem por maioria quem pode entrar."/><div className="two-columns"><section className="panel"><div className="panel-head"><h2>Candidaturas</h2></div>{apps.map(a=><div key={a.id} className="offer"><div><strong>{a.nickname}</strong><small>{a.yes_votes} votos favoráveis de {a.eligible_votes} eleitores · {a.state}</small></div>{isCompetitor&&a.state==='pending'&&<div className="position-sale"><Button subtle disabled={busy} onClick={()=>void act(()=>rpc('vote_application',{p_application:a.id,p_approve:true}),'Voto favorável registado.')}><Check size={15}/> Sim</Button><Button subtle disabled={busy} onClick={()=>void act(()=>rpc('vote_application',{p_application:a.id,p_approve:false}),'Voto desfavorável registado.')}>Não</Button></div>}</div>)}{!apps.length&&<Empty text="Sem candidaturas pendentes."/>}</section><section className="panel"><div className="panel-head"><h2>Participar</h2></div>{!user?<Empty text="Inicia sessão para te candidatares."/>:<><p className="footnote">A candidatura usa o nickname do teu perfil: <strong>{profile?.nickname||'Por definir'}</strong>. <button className="text-link" onClick={()=>setTab('account')}>Gerir perfil</button></p><Button disabled={busy||!profile?.nickname||profile.nickname.trim().length<2} onClick={()=>void act(()=>rpc('apply_competitor'),'Candidatura submetida para votação.')}>Candidatar-me</Button></>}</section></div></>}
   {tab==='account'&&<><SectionTitle kicker="PERFIL" title="A minha conta" subtitle="Identidade e preferências do teu perfil público."/><section className="panel"><div className="panel-head"><h2>Perfil público</h2></div>{user?<><label>Nickname<input aria-label="Nickname público" aria-invalid={nickname.trim().length<2||nickname.trim().length>40} aria-describedby="nickname-help" maxLength={40} value={nickname} onChange={e=>setNickname(e.target.value)} placeholder="Nome público" /></label><p id="nickname-help" className="footnote">Entre 2 e 40 caracteres. O nome é utilizado em candidaturas, classificações e mercados.</p>{(nickname.trim().length<2||nickname.trim().length>40)&&<p className="field-error" role="alert">{errorText(errorFor('INVALID_NICKNAME'))}</p>}<Button disabled={busy||nickname.trim().length<2||nickname.trim().length>40||nickname.trim()===profile?.nickname} onClick={()=>void act(()=>rpc('update_nickname',{p_nickname:nickname.trim()}),'Nickname atualizado no perfil.')}>Guardar nickname</Button></>:<Empty text="Inicia sessão para gerir o teu perfil."/>}</section>{user&&<section className="panel"><div className="panel-head"><h2>Autenticação</h2></div><p className="footnote">Email da conta: {user.email||'Não disponível'}</p><p className="footnote">Identidades associadas: {(user.identities||[]).map(i=>i.provider).join(', ')||user.app_metadata.provider||'Não disponível'}</p><Button subtle onClick={()=>void client?.auth.signOut()}><LogOut size={16}/> Terminar sessão</Button></section>}</>}
   {tab==='admin'&&isAdmin&&<><SectionTitle kicker="06 / OPERAÇÕES" title="Gestão do campeonato" subtitle="Ações auditadas e restritas à administração."/><div className="panel"><div className="panel-head"><h2>Créditos semanais</h2></div><p className="footnote">Credita 1 000 ฿ por semana aos espectadores elegíveis, incluindo semanas em atraso desde o registo, dentro do campeonato. Nunca duplica créditos já atribuídos.</p><Button disabled={busy} onClick={()=>void act(async()=>{const count=await rpc<number>('grant_weekly');toast.success(count>0?`Foram atribuídas ${count} dotações semanais.`:'Não existem dotações semanais por atribuir.');},'')}>Distribuir dotações pendentes</Button></div><section className="panel"><div className="panel-head"><h2>Reconciliação de carteiras</h2></div><p className="footnote">Compara disponível, reservado e total emitido de cada carteira com os movimentos registados no ledger. Não altera saldos.</p><Button subtle disabled={busy} onClick={()=>void act(async()=>{setReconciliation(await rpc<WalletReconciliation[]>('reconcile_wallets'));},'Reconciliação concluída.')}>Verificar carteiras</Button>{reconciliation&&<><p className="footnote" role="status">Carteiras verificadas: {reconciliation.length}. Divergências encontradas: <strong>{reconciliation.filter(x=>!x.balanced).length}</strong>.</p>{reconciliation.filter(x=>!x.balanced).map(x=><div className="offer" key={x.owner_id}><div><strong>{x.nickname}</strong><small>Diferenças — disponível: {formatCoins(Number(x.available_difference))} ฿; reservado: {formatCoins(Number(x.reserved_difference))} ฿; emitido: {formatCoins(Number(x.issued_difference))} ฿.</small></div><span className="badge">Rever</span></div>)}{reconciliation.length>0&&reconciliation.every(x=>x.balanced)&&<p className="footnote">Nenhuma divergência detetada.</p>}</>}</section><section className="panel"><h2>Sprints e snapshots</h2><div className="form-row"><label>Nome<input value={sprintName} onChange={e=>setSprintName(e.target.value)} placeholder="Semana 47"/></label><label>Tipo<select value={sprintKind} onChange={e=>setSprintKind(e.target.value)}><option value="weekly">Semanal</option><option value="monthly">Mensal</option></select></label></div><div className="form-row"><label>Início<input type="datetime-local" value={sprintStart} onChange={e=>setSprintStart(e.target.value)}/></label><label>Fim<input type="datetime-local" value={sprintEnd} onChange={e=>setSprintEnd(e.target.value)}/></label></div>{sprintDateError&&<p className="field-error" role="alert">{errorText(sprintDateError)}</p>}<Button disabled={busy||!sprintName.trim()||Boolean(sprintDateError)||!sprintStart||!sprintEnd} onClick={()=>void act(()=>rpc('create_sprint',{p_name:sprintName,p_kind:sprintKind,p_start:new Date(sprintStart).toISOString(),p_end:new Date(sprintEnd).toISOString()}),'Sprint criado.')}>Criar sprint</Button>{sprints.map(sp=><div key={sp.id} className="offer"><div><strong>{sp.name}</strong><small>{sp.state} · {new Date(sp.ends_at).toLocaleString('pt-PT')}</small></div><Button subtle onClick={()=>{setSelectedSprint(sp.id);setTab('overview')}}>Rever snapshots e validação</Button></div>)}</section><div className="two-columns"><section className="panel"><h2>Atualizar o meu YTD</h2><label>Valorização YTD (%)<input type="number" step=".01" value={score} onChange={e=>setScore(e.target.value)}/></label>{ytdError&&<span className="field-error" role="alert">{errorText(ytdError)}</span>}<Button disabled={busy||Boolean(ytdError)||finalBlocking||entryBlocking} onClick={()=>void act(()=>rpc('set_my_score',{p_ytd:Number(score)}),'Valorização YTD atualizada.')}>Guardar score</Button><p className="footnote">Cada concorrente também pode atualizar o seu score no painel de perfil; administradores não alteram scores alheios.</p></section><RecurringBets championships={championships} definitions={definitions} occurrences={occurrences} markets={markets} busy={busy} act={act}/></div><FinalRoundManagement championships={championships} busy={busy} act={act}/><section className="panel"><div className="panel-head"><h2>Liquidar mercados</h2></div><p className="footnote">Só é possível liquidar depois do prazo de fecho e com a classificação final validada. Irreversível nesta versão.</p>{markets.filter(m=>m.state==='open').map(m=><MarketSettlement key={user?.id+':'+m.id} market={m} outcomeLabels={Object.fromEntries(outcomes.filter(o=>o.market_id===m.id).map(o=>[o.id,o.label]))} busy={busy} onValidate={note=>act(()=>rpc('validate_market_classification',{p_market:m.id,p_note:note}),'Classificação do mercado validada.')} onSettle={winner=>void act(()=>rpc('settle_market',{p_market:m.id,p_winner:winner}),'Mercado liquidado com resultado validado.')} />)}</section></>}
   <footer><span>© BETCOINS · INVESTMENT LEAGUE 2026</span><span>100% FICTÍCIO · SEM DINHEIRO REAL</span></footer></div></main></div>
}
function Empty({text}:{text:string}){return <div className="empty"><CircleDollarSign size={26}/><span>{text}</span></div>}
function SectionTitle({kicker,title,subtitle}:{kicker:string;title:string;subtitle:string}){return <div className="heading"><div><div className="eyebrow">{kicker}</div><h1>{title}<span className="gold">.</span></h1><p>{subtitle}</p></div><ExternalLink size={19} className="muted"/></div>}
