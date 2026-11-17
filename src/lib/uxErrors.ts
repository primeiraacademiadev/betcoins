/** Stable user-facing error codes. Never render raw PostgreSQL details or identifiers. */
export type UXErrorCode =
 | 'ODD_TOO_LOW'|'ODD_PRECISION'|'STAKE_INVALID'|'BALANCE_INSUFFICIENT'
 | 'NOT_AUTHORIZED'|'SESSION_REQUIRED'|'MARKET_CLOSED'|'OFFER_UNAVAILABLE'
 | 'POSITION_UNAVAILABLE'|'APPLICATION_DECIDED'|'DUPLICATE_ACTION'
 | 'INVALID_NICKNAME'|'INVALID_DATE'|'INVALID_SELECTION'|'INVALID_PRICE'
 | 'PREVIOUS_PERIOD_REQUIRED'|'BET_PAUSED'|'FINAL_REQUIRED'|'FINAL_CLOSED'|'FINAL_ADMIN'|'INITIAL_IMMUTABLE'|'INITIAL_PARTICIPANTS'
 | 'COLLISION_BLOCKED'|'MARKET_REPLACED'|'ASSOCIATION_BLOCKED'|'LEGACY_REVIEW'|'PREVIEW_CHANGED'|'SETTLEMENT_BLOCKED'|'MARKET_PERIOD_REQUIRED'
 | 'INVALID_LOT'|'INVALID_YTD'|'NETWORK_UNCERTAIN'|'SERVICE_UNAVAILABLE'|'UNKNOWN';
export type UXError = { code:UXErrorCode; title:string; explanation:string; action:string; field?:string };
const catalog:Record<UXErrorCode,Omit<UXError,'code'>> = {
 COLLISION_BLOCKED:{title:'Colisão preservada',explanation:'O gerado tem contratos, resultados ou uma identidade que não pode ser substituída.',action:'Revê a colisão na gestão. Não são fundidas posições nem devolvidas reservas.'},
 MARKET_REPLACED:{title:'Mercado substituído',explanation:'Este gerado está arquivado e não permite negociar, validar ou liquidar.',action:'Consulta o mercado legado mantido na secção Gerados substituídos.'},
 ASSOCIATION_BLOCKED:{title:'Associação bloqueada',explanation:'A ligação não é compatível, já está fixada ou a posição no calendário está ocupada.',action:'Pré-visualiza novamente e revê os motivos. Os contratos existentes mantêm-se.'},
 LEGACY_REVIEW:{title:'Mercado em revisão',explanation:'O contrato legado ou os participantes exigem reconciliação. As posições e reservas mantêm-se.',action:'Consulta a gestão. Podes cancelar ofertas não correspondidas; não há devoluções automáticas.'},
 PREVIEW_CHANGED:{title:'Revisão desatualizada',explanation:'O mercado ou as entradas mudaram desde a pré-visualização.',action:'Pré-visualiza novamente e revê as alterações antes de aplicar.'},
 INITIAL_IMMUTABLE:{title:'YTD inicial imutável',explanation:'O primeiro valor já foi registado e permanece como referência de entrada.',action:'Para um valor novo, usa a atualização do YTD corrente.'},
 INITIAL_PARTICIPANTS:{title:'Participações insuficientes',explanation:'É necessário que pelo menos dois concorrentes tenham declarado o primeiro YTD.',action:'Aguarda as declarações iniciais e reconcilia o calendário.'},
 FINAL_REQUIRED:{title:'Declaração de fecho pendente',explanation:'Antes de atualizar o YTD corrente, é necessário resolver o fecho mais antigo.',action:'Preenche a secção Declarações de fecho obrigatórias. Se o prazo terminou, aguarda o apuramento.'},
 FINAL_CLOSED:{title:'Prazo de fecho encerrado',explanation:'Já não é possível registar uma nova declaração para este fecho.',action:'Atualiza os dados e consulta o apuramento.'},
 FINAL_ADMIN:{title:'Recolha de fecho por concluir',explanation:'É necessário respeitar o prazo administrativo e apurar as declarações antes de capturar o fecho.',action:'Consulta Recolha e apuramento de declarações finais na gestão.'},
 BET_PAUSED:{title:'Negociação suspensa',explanation:'A gestão suspendeu esta bet. As posições e reservas existentes mantêm-se.',action:'Podes cancelar ofertas não correspondidas ou aguardar a retoma.'},
 PREVIOUS_PERIOD_REQUIRED:{title:'Falta o período anterior',explanation:'Esta modalidade exige um único período anterior registado, com snapshot de fecho auditável antes da validação.',action:'Revê o calendário. Não uses o início do sprint nem zero como substitutos.'},
 SETTLEMENT_BLOCKED:{title:'Liquidação bloqueada',explanation:'O mercado exige um resultado validado, completo, sem empate relevante e com participantes e período coincidentes.',action:'Consulta o apuramento; não escolhas um vencedor manualmente.'},
 MARKET_PERIOD_REQUIRED:{title:'Período necessário',explanation:'O mercado deve estar associado a um campeonato ou sprint válido e aberto.',action:'Atualiza a página e seleciona o período na gestão.'},
 ODD_TOO_LOW:{title:'Odd inválida',explanation:'A odd tem de ser superior a 1,00. Com 1,20 e stake de 10 ฿, BACK recebe 12 ฿ se acertar (2 ฿ de lucro líquido).',action:'Introduz uma odd entre 1,01 e 1000,00.',field:'odds'},
 ODD_PRECISION:{title:'Precisão da odd',explanation:'As odds admitem duas casas decimais, no máximo 1000,00.',action:'Por exemplo, utiliza 1,20.',field:'odds'},
 STAKE_INVALID:{title:'Stake inválida',explanation:'A stake BACK tem de ser um número inteiro superior a zero.',action:'Indica 1, 2, 3… BetCoins.',field:'stake'},
 BALANCE_INSUFFICIENT:{title:'Saldo insuficiente',explanation:'O capital disponível não cobre a reserva ou o preço desta operação.',action:'Reduz a stake/preço ou consulta o saldo disponível na Carteira.'},
 NOT_AUTHORIZED:{title:'Operação não permitida',explanation:'Esta conta não tem autorização para executar a operação.',action:'Verifica as tuas permissões ou contacta a gestão.'},
 SESSION_REQUIRED:{title:'Sessão necessária',explanation:'A operação exige autenticação.',action:'Inicia sessão e volta a tentar.'},
 MARKET_CLOSED:{title:'Mercado fechado',explanation:'O prazo terminou ou o mercado já foi liquidado.',action:'Atualiza os mercados e escolhe um mercado aberto.'},
 OFFER_UNAVAILABLE:{title:'Oferta indisponível',explanation:'A oferta foi preenchida, cancelada ou entretanto alterada.',action:'Atualiza o livro e escolhe uma oferta disponível.'},
 POSITION_UNAVAILABLE:{title:'Posição indisponível',explanation:'A posição já foi vendida, anunciada ou liquidada.',action:'Atualiza a Carteira ou o marketplace antes de repetir.'},
 APPLICATION_DECIDED:{title:'Candidatura indisponível',explanation:'A candidatura já foi decidida ou o voto já foi registado.',action:'Atualiza a lista de candidaturas.'},
 DUPLICATE_ACTION:{title:'Operação já registada',explanation:'Esta ação já foi concluída ou está em conflito com outra.',action:'Atualiza os dados antes de voltar a tentar.'},
 INVALID_NICKNAME:{title:'Nickname inválido',explanation:'O nome público deve ter entre 2 e 40 caracteres.',action:'Corrige o nickname na área A minha conta.',field:'nickname'},
 INVALID_DATE:{title:'Datas inválidas',explanation:'A data de fim tem de ser posterior ao início e o fecho deve cumprir as regras do campeonato.',action:'Revê as datas, a hora e o prazo do mercado.',field:'date'},
 INVALID_SELECTION:{title:'Seleção incompleta',explanation:'Falta selecionar uma opção ou pelo menos dois concorrentes distintos.',action:'Preenche os campos assinalados.',field:'selection'},
 INVALID_PRICE:{title:'Preço inválido',explanation:'O preço deve ser positivo e expresso em cêntimos (duas casas decimais).',action:'Indica um preço como 8,50 ฿.',field:'price'},
 INVALID_LOT:{title:'Lote inválido',explanation:'A revenda parcial exige quantidades inteiras que preservem exatamente a proporção do colateral e o custo.',action:'Escolhe um múltiplo do lote mínimo indicado.',field:'quantity'},
 INVALID_YTD:{title:'Valorização YTD inválida',explanation:'A valorização deve ser numérica, finita e não inferior a −100%.',action:'Corrige o valor YTD.',field:'score'},
 NETWORK_UNCERTAIN:{title:'Ligação interrompida',explanation:'Não foi possível confirmar se a operação chegou ao servidor.',action:'Atualiza o estado da carteira ou do mercado antes de repetir a operação.'},
 SERVICE_UNAVAILABLE:{title:'Serviço indisponível',explanation:'Não foi possível contactar o serviço neste momento.',action:'Verifica a ligação e tenta novamente depois de consultar o estado atual.'},
 UNKNOWN:{title:'Não foi possível concluir',explanation:'Não foi possível confirmar o resultado desta operação.',action:'Atualiza os dados antes de repetir; se persistir, comunica o problema à equipa.'},
};
export function errorFor(code:UXErrorCode):UXError{return {code,...catalog[code]};}
export function errorText(e:UXError):string{return e.title+' — '+e.explanation+' '+e.action;}
/** Classify by structured PostgREST/SQLSTATE code when possible; legacy text only as a fallback. */
export function classifyError(error:unknown):UXError {
 const e=error as {code?:unknown;message?:unknown;detailMessage?:unknown;status?:unknown};
 const code=typeof e?.code==='string'?e.code:'';
 const raw=typeof e?.detailMessage==='string'?e.detailMessage:e?.message;
 const text=typeof raw==='string'?raw.toLowerCase():'';
 if(code==='BK002')return errorFor('COLLISION_BLOCKED');
 if(code==='BK003')return errorFor('MARKET_REPLACED');
 if(code==='BA002'||code==='BA003')return errorFor('ASSOCIATION_BLOCKED');
 if(code==='BL001')return errorFor('PREVIEW_CHANGED');
 if(code==='BL002')return errorFor('LEGACY_REVIEW');
 if(code==='BE001')return errorFor('INITIAL_IMMUTABLE');
 if(code==='BE002')return errorFor('MARKET_PERIOD_REQUIRED');
 if(code==='BE003')return errorFor('INITIAL_PARTICIPANTS');
 if(code==='BF001')return errorFor('FINAL_REQUIRED');
 if(code==='BF002')return errorFor('FINAL_CLOSED');
 if(code==='BF003'||code==='BF005')return errorFor('FINAL_ADMIN');
 if(code==='BF004')return errorFor('INVALID_YTD');
 if(code==='BR001'||code==='BR002')return errorFor('MARKET_PERIOD_REQUIRED');
 if(code==='BR003')return errorFor('BET_PAUSED');
 if(code==='BP001')return errorFor('DUPLICATE_ACTION');
 if(code==='BP002')return errorFor('INVALID_SELECTION');
 if(code==='BP003')return errorFor('PREVIOUS_PERIOD_REQUIRED');
 if(code==='BP004')return errorFor('SETTLEMENT_BLOCKED');
 if(code==='BM001')return errorFor('MARKET_CLOSED');
 if(code==='BM002')return errorFor('INVALID_SELECTION');
 if(code==='BM003')return errorFor('MARKET_PERIOD_REQUIRED');
 if(code==='BM004')return errorFor('SETTLEMENT_BLOCKED');
 if(code==='23505')return errorFor('DUPLICATE_ACTION');
 if(code==='23514'&&(/wallets.*check|balance|saldo/i.test(text)))return errorFor('BALANCE_INSUFFICIENT');
 if(code==='23514')return errorFor('INVALID_SELECTION');
 if(code==='42501'||text.includes('sem permissão')||text.includes('permission denied')||text.includes('não permitido'))return errorFor('NOT_AUTHORIZED');
 if(code==='PGRST301'||text.includes('não autenticado')||text.includes('jwt expired'))return errorFor('SESSION_REQUIRED');
 if(code==='PGRST116'||text.includes('oferta indisponível')||text.includes('oferta já'))return errorFor('OFFER_UNAVAILABLE');
 if(text.includes('saldo')||text.includes('violates check constraint "wallets_')||text.includes('saldo insuficiente'))return errorFor('BALANCE_INSUFFICIENT');
 if(text.includes('mercado fechado')||text.includes('mercado encerrado')||text.includes('ainda não pode liquidar'))return errorFor('MARKET_CLOSED');
 if(text.includes('posição indisponível')||text.includes('anúncio indisponível')||text.includes('lote já não disponível'))return errorFor('POSITION_UNAVAILABLE');
 if(text.includes('candidatura já')||text.includes('voto já')||text.includes('candidatura encerrada'))return errorFor('APPLICATION_DECIDED');
 if(text.includes('nickname inválido'))return errorFor('INVALID_NICKNAME');
 if(text.includes('preço inválido'))return errorFor('INVALID_PRICE');
 if(text.includes('lote não divisível')||text.includes('responsabilidade não divisível')||text.includes('custo não divisível'))return errorFor('INVALID_LOT');
 if(text.includes('odd')&&text.includes('inválid'))return errorFor('ODD_TOO_LOW');
 if(text.includes('stake')&&text.includes('inválid'))return errorFor('STAKE_INVALID');
 if(text.includes('score inválido')||text.includes('ytd inválido'))return errorFor('INVALID_YTD');
 // Browser fetch failures can occur after the server accepted the transaction.
 if(error instanceof TypeError||/failed to fetch|networkerror|network request failed|load failed|fetch failed/.test(text))return errorFor('NETWORK_UNCERTAIN');
 if(e?.status===503||e?.status===502||e?.status===504||code==='PGRST002')return errorFor('SERVICE_UNAVAILABLE');
 return errorFor('UNKNOWN');
}
export function validateOdd(value:string):UXError|null {
 const n=Number(value);
 if(!value.trim()||!Number.isFinite(n)||n<=1)return errorFor('ODD_TOO_LOW');
 if(n>1000||Math.abs(Math.round(n*100)-n*100)>1e-7)return errorFor('ODD_PRECISION');
 return null;
}
export function validateStake(value:string):UXError|null {
 const n=Number(value);return value.trim()&&Number.isSafeInteger(n)&&n>0?null:errorFor('STAKE_INVALID');
}
export function validateYtd(value:string):UXError|null {
 const n=Number(value);return value.trim()&&Number.isFinite(n)&&n>=-100?null:errorFor('INVALID_YTD');
}
export function validateDateRange(start:string,end:string):UXError|null {
 const a=Date.parse(start),b=Date.parse(end);
 return Number.isFinite(a)&&Number.isFinite(b)&&a<b?null:errorFor('INVALID_DATE');
}
export function validatePrice(value:string):UXError|null {
 const n=Number(value);
 return value.trim()&&Number.isFinite(n)&&n>0&&n<=100000000&&Math.abs(Math.round(n*100)-n*100)<1e-7?null:errorFor('INVALID_PRICE');
}
