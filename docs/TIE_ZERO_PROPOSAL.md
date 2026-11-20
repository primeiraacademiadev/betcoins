# #5 — devolução integral de colateral em empate/zero

Decisão do operador em 20/11/2026: devolver integralmente o colateral ao
**titular atual**, sem desfazer revendas. Tesouraria recebe zero.
A anterior proposta de perda dos dois lados e transferência para tesouraria foi
rejeitada e substituída por esta decisão.

Estado técnico: implementação preparada na migração 18 e na interface, por
autorização do operador em 20/11/2026; validação em CI em curso. Sem instalação
remota: antes da migração 18, o servidor continua a bloquear empate/zero. Mantêm-se as duas
modalidades; nenhuma migração remota é executada.

## Regra financeira definida

No empate relevante, devolver a stake reservada de BACK e a responsabilidade
reservada de LAY aos titulares atuais dos respetivos lotes. Não há vencedor,
ganho regular de aposta, perda de colateral, taxa ou transferência para tesouraria.
Não criar nem destruir BetCoins.

LAY não ganha o total dos dois colaterais por ter apostado contra um outcome
empatado: recebe apenas a responsabilidade que lhe pertence. BACK recebe apenas
a sua stake. As liquidações regulares com vencedor único não mudam.

A devolução é integral quanto ao colateral; não significa voltar à titularidade
original, desfazer compras/vendas ou garantir P&L zero a quem comprou uma posição.
As operações de revenda já concluídas mantêm preço, titularidade e P&L realizado.

Esta decisão substitui a antiga regra documental de «ambos perdem como zero da
roleta». O nome empate/zero pode identificar o motivo, mas a interface deve dizer
explicitamente «devolução integral do colateral ao titular atual».

## Âmbito aprovado para o empate

Aplicar a devolução ao **mercado inteiro** quando o lugar que esse mercado prevê
não tem resultado único por empate relevante, incluindo posições relativas a
concorrentes fora do empate. O operador autorizou expressamente a aplicação ao mercado inteiro em
20/11/2026, mantendo pagamentos e titularidade atuais.

- Primeiro lugar partilhado: devolver no mercado de primeiro.
- Último lugar partilhado: devolver no mercado de último.
- Ranking 1,1,3: devolver no mercado de segundo, inexistente devido ao empate.
- Empate apenas noutro lugar, sem afetar o lugar previsto: resolução regular.
- Falta de score/referência, ausência de validação ou participantes insuficientes:
  continuar bloqueado; não assumir que há empate.
- Usar a classificação validada e congelada própria da modalidade
  `snapshot_value` ou `snapshot_delta_previous`, nunca YTD corrente.

A resolução por empate deve ser explícita e auditada, sem inventar um outcome
vencedor nem permitir que o administrador a use para corrigir resultados livremente.

## Exemplo sem revenda

Stake BACK 10 ฿, odd 1,20 e responsabilidade LAY 2 ฿; total reservado 12 ฿.

| Resolução | BACK recebe | LAY recebe | Tesouraria recebe | P&L BACK / LAY |
| --- | ---: | ---: | ---: | --- |
| Outcome escolhido vence | 12 | 0 | 0 | +2 / −2 |
| Outro outcome vence | 0 | 12 | 0 | −10 / +10 |
| Empate relevante | 10 | 2 | 0 | 0 / 0 |

Na devolução, a reserva de BACK diminui 10 e o seu disponível aumenta 10; a
reserva de LAY diminui 2 e o seu disponível aumenta 2. Não há novo débito,
emissão ou crédito de tesouraria. A soma disponível + reservado mantém-se
por titular e globalmente neste exemplo.

## Revenda, custo e P&L

Cada lote recebe o respetivo colateral no titular atual: stake no lado BACK,
responsabilidade no lado LAY. P&L final = colateral devolvido − custo de
aquisição do lote. Não confundir preço da revenda com colateral.

Exemplo confirmado pelo operador: BACK inicial com custo 10 vendido por 7.
O vendedor mantém P&L realizado de −3; o comprador tem custo 7, recebe os 10
de colateral e realiza +3. A revenda não é desfeita e o preço 7 não é devolvido.
O lado LAY recebe os seus 2; a tesouraria recebe 0. A soma de P&L desta cadeia
BACK é zero (−3 + 3); os resultados individuais continuam diferentes.

O mesmo critério aplica-se a LAY: um lote com responsabilidade 2 comprado por
1,50 recebe 2 e realiza +0,50; a venda anterior mantém o seu resultado.
Revendas sucessivas ou parciais preservam todos os preços e custos: cada lote
paga apenas o colateral que lhe corresponde, uma vez, ao titular final.

Ofertas não correspondidas libertam o remanescente reservado como já sucede.
Anúncios de revenda sem compra concluída não mudam titularidade; devem terminar
sem novos pagamentos, devoluções de preço ou dupla libertação de reservas.

## Implementação preparada e invariantes

1. Aplicar o âmbito aprovado acima e apresentar claramente a regra de devolução
   antes de BACK/LAY/compra. Não alterar silenciosamente condições de apostas
   existentes; sem instalação da migração 18, a devolução permanece bloqueada no servidor.
   Dados só de teste podem ser descartados numa operação identificada; não existe
   obrigação de compatibilidade legada.
2. Persistir motivo de devolução, fonte validada, administrador, data,
   titulares/lotes, colaterais, custos e movimentos compensatórios. Manter ledger
   e histórico imutáveis: registar a devolução, não apagar o negócio.
3. Libertar reservas, creditar os titulares atuais e registar P&L numa única
   transação autorizada, com locks, precisão e idempotência. Falha de invariantes
   não pode deixar devoluções parciais ou saldos negativos.
4. Não criar conta de tesouraria para este fluxo, nem usar emissão/dotações para
   pagar a devolução. O pagamento vem exclusivamente do colateral já reservado.
5. Manter dados incompletos e classificações não validadas bloqueados.
   Reversão administrativa de liquidações, reabertura e desfazer revendas continuam
   fora do MVP. A devolução por empate aqui definida é uma resolução específica,
   não uma autorização genérica de reversão.

## Verificação

`tests/db/tie_refunds_concurrency.py` cobre fontes reais, duas modalidades e três
lugares nos três percursos de instalação do CI. Os fluxos financeiros no navegador
cobrem devolução e P&L após revenda a 1280/390 px. A confirmação dos resultados
depende da conclusão do CI deste PR; os critérios são:

- Duas modalidades × três lugares: empate relevante, empate irrelevante,
  1,1,3 e último partilhado; ausências e universo insuficiente continuam bloqueados.
- Exemplo 10/1,20/2: BACK recebe 10, LAY 2, tesouraria 0; reservas chegam a zero,
  disponíveis reconciliam e moeda é conservada. Sem revendas, P&L de ambos é zero.
- Ofertas parcialmente aceites: devolver exatamente colateral correspondido e
  remanescente reservado, sem duplicação. Mercado sem negócios não cria movimentos
  financeiros fictícios.
- BACK de 10 vendido por 7: vendedor mantém −3, comprador recebe 10 e realiza +3.
  Cobrir também LAY, cadeias e lotes parciais, titulares distintos e arredondamentos.
- Anúncios de revenda terminam sem devolver preços de compras já executadas.
- Devoluções repetidas/concorrentes e corrida com cancelamento/compra no corte:
  uma resolução, nenhuma devolução duplicada, falha integral se inválido.
- Autorização/RLS, ledger imutável, auditoria e reconciliação por carteira/global.
- Interface desktop/telemóvel mostra o colateral devolvido e distingue-o de
  lucro/preço de aquisição; regressão completa da liquidação regular.

## Instalação e limite

Migração `202611200001_tie_refunds.sql`, dependente de 01–17, apenas versionada.
A RPC administrativa `refund_tied_market` exige fecho e empate relevante validado;
é idempotente. A liquidação regular continua separada e rejeita empate.
`market_resolutions.resolution_kind` e `position_settlements.settlement_kind`
identificam `tie_refund`, sem vencedor inventado nem tesouraria.

Nenhuma migração foi executada no Supabase remoto. CI e publicação do frontend
não instalam SQL; não apresentar a migração como instalada. As duas modalidades
são preservadas. Reversões administrativas de liquidações continuam fora do MVP.
