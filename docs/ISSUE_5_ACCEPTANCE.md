# #5 — mercados P2P e liquidação

Atualizado em 20/11/2026. Esta matriz descreve o modelo atual, após os PRs
#33–#45; as entregas por migração são histórico técnico, não novas pendências.

## Estado atual

O fluxo regular de mercados P2P está implementado e testado no código:
BACK/LAY, aceitação parcial, reservas, cancelamento do remanescente, revenda,
validação e liquidação idempotente. As duas modalidades e as bets recorrentes
já foram entregues; a #11 está encerrada. Não existe requisito de compatibilidade
ou reconciliação legada. Reversões financeiras ficam fora do MVP.

A #5 acompanha agora a implementação autorizada de devolução por empate ao mercado inteiro (migração 18).
Na versão anterior à migração 18, empate/zero continua bloqueado. Com a migração
18 instalada num ambiente autorizado, a RPC própria devolve colateral ao titular
atual após classificação validada; sem tesouraria ou vencedor escolhido manualmente.
O [tratamento financeiro revisto](TIE_ZERO_PROPOSAL.md) devolve integralmente o colateral ao titular atual, por decisão do operador, sem desfazer revendas. Implementação preparada no código e na migração 18; sem execução remota.

| Critério | Estado e evidência |
| --- | --- |
| BACK/LAY e aceitação total/parcial | Implementado; testes SQL e financeiros no navegador, limites de stake/odds e proibição de autocontratação |
| Colateral e conservação | Implementado; risco de ambos os lados reservado, reconciliação de carteiras/ledger e conservação da moeda |
| Cancelamento | Devolve apenas a reserva do remanescente não correspondido, sem desfazer negócios; idempotente, permitido após corte |
| Revenda integral/parcial | Implementada; transfere titularidade/risco/colateral, mantém custo de aquisição e P&L das vendas anteriores |
| Concorrência e corte | Sessões PostgreSQL reais disputam saldo, aceitação, compra, cancelamento e liquidação; relógio validado após espera pelos locks |
| Classificação e liquidação | Resultado validado e fontes congeladas; autorização administrativa, auditoria, imutabilidade e repetição sem pagamentos duplicados |
| Duas modalidades | `snapshot_value`: YTD efetivo no fecho; `snapshot_delta_previous`: diferença em pp face ao original do fecho anterior, com exceção do baseline inicial aprovada na #11 |
| Calendário e elegibilidade | Bets recorrentes, geração idempotente, entradas a meio do período, declarações finais/penalizações e resultados por ocorrência entregues na #11 |
| Empate/zero | Migração 18 e RPC `refund_tied_market`: devolução ao mercado inteiro, aos titulares atuais, sem desfazer revendas. Sem migração instalada, mantém bloqueio. CI de devolução/concorrência e navegador em validação |
| Dados incompletos | Permanecem bloqueados; ausência de score, referência ou concorrentes suficientes não é zero |
| Interface e segurança | Modalidade e motivos de bloqueio visíveis; sem seleção arbitrária de vencedor, nem escrita direta de saldos/ledger/posições |

## Evidência de verificação

- `tests/db/markets.sql`, `market_modes.sql` e respetivas suites concorrentes:
  motor P2P, modalidades, corte, reconciliação, autorização e liquidação.
- `tests/db/issue_11_acceptance.sql` e `issue_11_acceptance_concurrency.py`:
  modelo recorrente atual, fontes congeladas, declarações, penalizações e baseline.
- [Testes financeiros no navegador](FINANCIAL_BROWSER_TESTS.md): aplicação completa,
  PostgREST/PostgreSQL reais no CI, duas modalidades e larguras 1280/390 px.
- PRs #43–#45 integrados; CI de main verde em
  [5efc0fe](https://github.com/primeiraacademiadev/betcoins/actions/runs/44724549155).
  As suites históricas anteriores à migração 18 demonstram o bloqueio. A nova
  suite `tie_refunds_concurrency.py` testa a devolução autorizada após a migração 18.

Os percursos históricos de migração testam a evolução do esquema.
Não criam obrigação de compatibilidade de produto. Esta revisão não consulta
nem altera o esquema remoto: publicação do frontend e CI verde não comprovam
quais migrações estão instaladas no Supabase.

## Entrega da devolução por empate

O operador autorizou aplicar a devolução ao mercado inteiro: stake BACK e
responsabilidade LAY aos titulares atuais, sem desfazer revendas. Implementação
preparada na migração `202611200001_tie_refunds.sql` e na interface. Testes em CI
cobrem colaterais, lotes/revendas, P&L, idempotência, autorização, concorrência,
liquidação regular e histórico. Confirmar CI antes de integrar a implementação.

Nenhuma migração remota é executada. Publicar o frontend não ativa a RPC num
Supabase sem a migração 18. Backups/quotas foram adiados na #8; reversões
administrativas/reabertura e desfazer revendas continuam fora do MVP.
