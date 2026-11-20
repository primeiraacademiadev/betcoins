# #5 — mercados P2P e liquidação

Atualizado em 20/11/2026. Esta matriz descreve o modelo atual, após os PRs
#33–#45; as entregas por migração são histórico técnico, não novas pendências.

## Estado atual

O fluxo regular de mercados P2P está implementado e testado no código:
BACK/LAY, aceitação parcial, reservas, cancelamento do remanescente, revenda,
validação e liquidação idempotente. As duas modalidades e as bets recorrentes
já foram entregues; a #11 está encerrada. Não existe requisito de compatibilidade
ou reconciliação legada. Reversões financeiras ficam fora do MVP.

A #5 continua aberta pelo tratamento financeiro de empate/zero.
O comportamento executável mantém-se: **empate/zero bloqueado**, sem pagamentos,
devoluções, tesouraria ou vencedor escolhido manualmente.
A [proposta financeira](TIE_ZERO_PROPOSAL.md) é uma decisão a rever antes de implementar.

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
| Empate/zero | Bloqueado no servidor e interface; proposta financeira não implementada nem aprovada |
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
  Os testes existentes demonstram o bloqueio do empate, não uma liquidação de zero.

Os percursos históricos de migração testam a evolução do esquema.
Não criam obrigação de compatibilidade de produto. Esta revisão não consulta
nem altera o esquema remoto: publicação do frontend e CI verde não comprovam
quais migrações estão instaladas no Supabase.

## Próxima decisão da #5

Rever a proposta de empate/zero: âmbito do empate relevante, perda de BACK e LAY,
destino dos colaterais, P&L após revenda e comunicação antes da contratação.
Só após aprovação se pode preparar implementação e testes específicos.
Não ativar por esta revisão. Sem migrações remotas.

Backups/quotas foram adiados no encerramento da #8; reversões/reabertura
financeira ficam fora do MVP. Não são acrescentados à aceitação desta proposta.
