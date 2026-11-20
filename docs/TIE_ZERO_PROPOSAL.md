# #5 — proposta de empate/zero em BACK/LAY

Estado em 20/11/2026: **proposta para aprovação, não implementada**.
Empate/zero continua bloqueado. Nenhuma migração ou alteração financeira é
executada por este documento. Mantêm-se as duas modalidades existentes.

## Regra proposta

Tratar zero como terceiro estado de resolução, distinto de um outcome vencedor
e de anulação. Na resolução regular, BACK ganha quando o outcome escolhido vence;
LAY ganha quando existe outro vencedor único. No zero, ambos perdem o colateral
da parte correspondida: stake de BACK e responsabilidade de LAY.

Isto exige tornar explícita a condição do LAY: apostar contra um outcome só paga
perante uma resolução regular a favor de outro outcome. O empate não passa a ser
uma vitória do LAY. Essa condição deve ser visível antes de colocar/aceitar ofertas
e antes de comprar uma posição.

Proponho aplicar zero ao **mercado inteiro** quando o lugar que esse mercado
prevê não tem resultado único por empate relevante. Nesse mercado, todas as
posições correspondidas perdem, mesmo as relativas a concorrentes fora do empate.
Não aplicar zero apenas a alguns contratos dentro do mesmo mercado.

- Primeiro lugar partilhado: zero no mercado de primeiro.
- Último lugar partilhado: zero no mercado de último.
- Ranking 1,1,3: zero no mercado de segundo, pois o lugar falta devido ao empate.
- Empate apenas noutro lugar, sem afetar o lugar previsto: resolução regular.
- Falta de score/referência, ausência de validação ou participantes insuficientes:
  continuar bloqueado; não converter em zero.
- Aplicar o mesmo critério nas modalidades de valor e diferença. Usar a
  classificação validada e congelada própria do mercado; nunca YTD corrente.

O âmbito de mercado inteiro e o comportamento LAY são decisões propostas
explicitamente, não consequências já aprovadas da expressão «zero da roleta».

## Destino dos valores

Criar, numa implementação futura aprovada, uma conta técnica de tesouraria que
receba exatamente os colaterais perdidos. Não queimar nem emitir BetCoins.
A plataforma continua sem financiar ganhos ou oferecer contraparte: a tesouraria
apenas recebe o valor de zero; não publica ofertas, negoceia nem recebe dotações.

Proponho que os valores fiquem retidos nessa conta, sem levantamentos, distribuição
ou reutilização automática. Um destino posterior exige decisão separada.
A conta não tem login de jogador, não entra nos rankings e não é carteira pessoal
de um administrador. Os movimentos e total recebido devem ser auditáveis.

Reservas de ofertas não correspondidas não são apostas perdidas: libertar apenas
o remanescente, como na liquidação regular. Posições ainda anunciadas para revenda
pertencem ao titular atual; anúncios sem compra concluída expiram/cancelam, sem
criar pagamento ou dupla libertação de colateral.

## Exemplo completo

Stake BACK 10 ฿, odd 1,20 e responsabilidade LAY 2 ฿; total reservado 12 ฿.
Valores abaixo são pagamentos da liquidação, sem considerar revendas.

| Resolução | BACK recebe | LAY recebe | Tesouraria recebe | P&L BACK / LAY |
| --- | ---: | ---: | ---: | --- |
| Outcome escolhido vence | 12 | 0 | 0 | +2 / −2 |
| Outro outcome vence, sem zero | 0 | 12 | 0 | −10 / +10 |
| Empate/zero relevante | 0 | 0 | 12 | −10 / −2 |

No zero, a reserva de BACK diminui 10 e a de LAY diminui 2; o saldo disponível
dos jogadores não sofre novo débito, porque o risco já foi reservado. O disponível
da tesouraria aumenta 12. A soma de disponível + reservado de todas as carteiras,
incluindo a tesouraria, mantém-se. Não se deve debitar duas vezes a mesma perda.

Os rankings de jogadores podem perder património agregado por transferência
para a tesouraria; a reconciliação global deve incluí-la. Não apresentar essa
transferência como emissão, taxa regular ou perda inexplicada de moeda.

## Revenda, custo e P&L

O risco e o pagamento pertencem ao titular atual de cada lote. No zero,
pagamento final = 0 e P&L final = −custo de aquisição do lote, de acordo com
a contabilidade já existente. Não confundir custo de aquisição com colateral.

Exemplo: BACK inicial com custo 10 é vendido integralmente por 7. O vendedor
realizou −3; o comprador tem custo 7. Se houver zero, o comprador recebe 0 e
realiza −7. A tesouraria recebe os 10 de colateral BACK e os 2 de LAY, não os 7
da compra, que já foram pagos ao vendedor. O P&L da venda não é revertido.

Revendas parciais conservam os lotes e a precisão monetária existentes: zero
liquida cada lote uma única vez ao titular final. Somar custos/perdas não substitui
a reconciliação dos colaterais e transferências efetivas.

## Condições de implementação futura

1. Aprovar as decisões deste documento antes de alterar código ou esquema.
   Depois, explicitar a regra nos termos e nas confirmações BACK/LAY/revenda.
   Não mudar silenciosamente condições de posições já contratadas; posições
   sem essa condição aceite permanecem bloqueadas para zero. Dados só de teste
   podem ser descartados numa operação identificada, sem criar compatibilidade legada.
2. Persistir resolução zero explícita, fonte validada, versão da regra, administrador,
   data, titulares/lotes e movimentos de tesouraria; nunca inventar vencedor.
3. Transferir reservas e registar P&L numa transação única com autorização,
   locks, precisão e idempotência equivalentes à liquidação regular.
   Falta da conta técnica ou de invariantes deve falhar sem alterações parciais.
4. Impedir escrita direta, emissão/dotações e negociação pela tesouraria;
   mostrar aos jogadores perda possível, motivo e valor da resolução zero.
5. Manter ausência de dados e decisões não validadas bloqueadas. Zero não é
   uma ferramenta administrativa para resolver incidentes ou corrigir resultados.
   Reversões e reabertura financeira ficam fora do MVP.

## Testes necessários após aprovação

Estes são critérios futuros, não testes novos já executados:

- Duas modalidades × três lugares: empate relevante, empate irrelevante,
  1,1,3 e último partilhado; ausências e universo insuficiente continuam bloqueados.
- Exemplo 10/1,20/2 e outros valores/lotes válidos: pagamento zero a ambos,
  tesouraria exata, reservas libertadas e moeda conservada sem novo débito.
- Ofertas parcialmente aceites: apenas colateral correspondido transferido;
  remanescente devolvido uma vez. Zero sem negócios não gera receita.
- Revenda integral/parcial e titulares distintos em cada lado: P&L por custo,
  vendas anteriores intactas, anúncios sem dupla utilização de reservas.
- Liquidações repetidas/concorrentes, corrida com cancelamento e compra no corte:
  uma resolução, nenhuma receita duplicada, falha integral se inválido.
- Autorização/RLS, conta técnica excluída de dotações/rankings/negociação,
  reconciliação incluindo tesouraria e auditoria legível.
- Interface nas duas larguras: termos e risco antes de BACK/LAY/compra,
  apresentação do zero e regressão da liquidação regular.

## Decisões a aprovar

A recomendação é: zero ao mercado inteiro apenas por empate relevante; BACK e
LAY perdem o respetivo colateral; conta técnica recebe e retém o total; P&L dos
titulares segue o custo; sem devolução, emissão ou reversão. Até haver aprovação,
implementação, testes e instalação autorizada, o comportamento mantém-se bloqueado.
