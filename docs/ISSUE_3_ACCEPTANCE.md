# Issue #3 — matriz de aceitação E2

Implementação no PR #32. A instalação remota é uma operação separada: a migração 09 foi preparada no repositório, **não aplicada ao Supabase remoto**. O CI usa exclusivamente PostgreSQL descartável.

| Critério | Implementação | Evidência automatizada |
| --- | --- | --- |
| Candidaturas e votos de admitidos | Eleitorado congelado, maioria absoluta, rejeição quando impossível, sem autovoto; timestamps de decisão/admissão do servidor | `tests/db/competition.sql`: eleitorados par/ímpar, abstenções, votos duplicados, rejeição, eleitor admitido depois da candidatura, permissões |
| Concorrência de votação | Advisory lock comum às candidaturas/admissões; uma decisão e uma admissão | `competition_concurrency.py`: dois votos iguais e dois votos decisivos em sessões PostgreSQL simultâneas |
| YTD auditado | `set_my_score` guarda histórico e data efetiva após adquirir o lock; ausência é NULL, 0 declarado é válido | SQL: declaração inicial, limites, NaN, histórico e proibição de alteração; teste concorrente atravessa um limite de período |
| Ranking anual | Provisório com dados declarados; fecho absoluto YTD congelado, posterior validação administrativa | SQL: classificação anual distinta do delta do sprint; testes UI: ausências e zero, estado final e unidades |
| Sprints semanal/mensal | Capturas identificadas nos limites, origem `score_history.id`, timestamp e valor persistidos; delta em pp | SQL: ambos os tipos, limites inclusivos, versões declaradas no mesmo instante ordenadas pelo ID, exclusão de declarações posteriores, início −100%, delta 12 → 16,5 = 4,5 pp |
| Scores em falta | Registo explícito sem classificação; nunca inventar 0, penalização ou referência anterior à admissão | SQL: sem declaração e entrada a meio do período; UI mostra motivos e datas |
| Apuramento reproduzível | Fonte e valores imutáveis; ranking 1,1,3; alterações correntes não mudam os resultados | SQL: atualizações posteriores, triggers de imutabilidade, empates; testes de ordenação/precisão |
| Validação final | Captura ≠ validação; nota, autor, data e todas as linhas persistidas, incluindo as não classificadas | SQL: bloqueio sem dados/sem nota, idempotência e imutabilidade; concorrência de validações; UI exige revisão explícita |
| Compatibilidade | Histórico legado preservado sem certificar origem desconhecida; novos controlos indisponíveis antes da migração | Três percursos CI: migrações individuais, baseline + 08, upgrade 03–08, todos seguidos de 09 e regressões E2 |

## Protocolo de apuramento

1. A captura fixa **a última declaração auditada registada até ao limite inclusivo**. `cutoff_at` é o limite, `declared_at` é a data do valor, `captured_at` é a execução administrativa; não são confundidos.
2. Uma captura administrativa tardia consulta o histórico real, nunca `competitors.ytd` corrente. Pode recuperar um limite passado apenas quando há declarações auditadas; sem elas regista ausência. A data da declaração fica visível para a gestão avaliar a atualidade dos dados.
3. O universo de cada captura inclui apenas concorrentes admitidos até ao limite. Quem entra durante o sprint pode ter snapshot final mas não inicial: fica sem classificação Δ nesse sprint, explicitamente, sem baseline artificial. Não se cria aqui uma regra de elegibilidade de apostas.
4. Para o sprint, só pares inicial/final permitem calcular o delta. Para o anual basta o valor do fecho. Ausências permanecem no resultado como não classificadas. Um conjunto sem qualquer linha classificável não pode ser validado.
5. A gestão revê datas, valores, empates e ausências e confirma a classificação com nota. Validar congela o conjunto apresentado, incluindo ausências; não transforma dados ausentes em resultados conhecidos. O controlo não verifica declarações com corretoras.
6. Captura e validação repetidas devolvem o registo existente. Marcadores de captura existem mesmo quando não há concorrentes, impedindo repopular silenciosamente um snapshot vazio.
7. Snapshots anteriores à migração 09 permanecem consultáveis, sem atribuição retroativa de proveniência ou certificação. Não são reescritos pela migração.

## Fronteira com #1, #5 e #11

Esta entrega fecha a implementação E2 de inscrições, classificação e validação auditada. **Não declara produção migrada** e não fecha os épicos de mercados/recorrência.

- O delta existente continua a ser `end − start` do próprio sprint. As duas modalidades de mercado aprovadas na #1 — valor absoluto do snapshot e diferença entre snapshot anterior e fecho atual — continuam sem suporte no modelo/geração/settlement de mercados.
- Empates partilham classificação. Não se escolhe um vencedor, não se anula o mercado e não se devolve colateral por esta operação. Empate/zero continua a exigir desenho financeiro na #5.
- Horário de geração automática, penalizações, declarações tardias de fecho e regras de mercado para entradas a meio do período permanecem nas decisões de produto da #1/#11. Esta entrega não ativa o helper experimental `periodRanking.ts` nem as suas propostas de penalização/void.
- A associação de mercados à classificação validada e o bloqueio/automatização do settlement pertencem à #5/#11. As funções financeiras não são alteradas.

Instalação manual e limitações: [COMPETITION_OPERATIONS.md](COMPETITION_OPERATIONS.md).
