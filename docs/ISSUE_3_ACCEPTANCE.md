# Issue #3 — auditoria de aceitação (15-11-2026)

Estado: **parcial; manter aberta**. Referência: regras canónicas da #1.

## Cobertura existente

- Candidaturas e eleitorado congelado: apply_competitor / vote_application, com maioria absoluta, exclusão do candidato e serialização por advisory lock.
- YTD corrente e histórico: set_my_score grava score_history; get_competitors fornece o ranking anual corrente.
- Sprints semanais/mensais: create_sprint, capture_sprint e get_sprint_rankings.
- O smoke SQL testa uma admissão e o delta aritmético 12,5 → 24 = 11,5 pp. Isto não cobre todos os casos adversariais.
- A apresentação de sprints passa a preservar lugares empatados (1,1,3), mostrar os dois valores congelados e distinguir carregamento, erro e ausência de pares. Respostas tardias de outra seleção são ignoradas.
- Testes unitários cobrem empates, deltas negativos, precisão de quatro casas e preservação dos dados de origem.

## Bloqueios para fecho

1. capture_sprint copia competitors.ytd, incluindo o zero predefinido de concorrentes sem primeira declaração (updated_at nulo). Falta distinguir dados ausentes de um zero declarado e definir o tratamento, sem inventar penalizações.
2. A janela inicial permite captura durante todo o sprint; o snapshot final pode ser capturado depois do fecho com o YTD corrente. Falta garantir proveniência temporal nos limites, sem reconstrução retroativa indevida.
3. Falta registo persistido de validação oficial/final do campeonato e sprints. state=closed representa captura/fecho, não aprovação auditada de uma classificação.
4. Faltam testes de maioria/rejeição, eleitorado alterado, votos duplicados/concorrentes, autorização de snapshots, dados em falta, limites e imutabilidade após novas declarações.

Estes pontos exigem trabalho adicional e, para parte do modelo, migração evolutiva revista. Este PR não executa nem acrescenta migrações remotas e não fecha a issue.

## Limites preservados

O ranking existente usa start/end do próprio sprint. Não implementa as duas modalidades de mercado aprovadas: valor absoluto do snapshot e diferença entre snapshot anterior e fecho atual. Estas permanecem na #11.

Mostrar empate num ranking não autoriza settlement. A regra empate/zero da #1 permanece sem suporte financeiro; não anular, devolver colateral ou escolher vencedor como substituto. O helper experimental periodRanking.ts não está integrado neste fluxo e não constitui implementação aprovada das propostas de penalização/void da #11.

A #5 depende de resultado validado e desenho do empate/zero; a #8 inclui testes adversariais/E2E e operação; a #11 exige evolução ampla de modelo/calendário. A #3 foi priorizada pelo âmbito mais delimitado, mas os critérios ainda não estão todos satisfeitos.
