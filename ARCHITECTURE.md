# BetCoins — Notas de arquitetura e invariantes

## Estrutura
- `src/ui`: interface React, operações no Supabase.
- `src/lib/domain.ts`: tipos, apresentação e regras matemáticas puras.
- `src/lib/supabase.ts`: cliente anónimo e chamadas RPC.
- `supabase/migrations`: tabelas, políticas, funções de negócio e snapshots dos sprints.
- `SETUP.md`: preparação da fase de integração externa.

## Identidade e integridade
O Supabase Auth fornece `auth.uid()`. Não aceitamos `owner_id` como argumento de transações sensíveis. As tabelas não aceitam INSERT/UPDATE/DELETE diretos por `authenticated`, e todas as mutações passam por funções `security definer` com `search_path` vazio, validações e restrição de EXECUTE.

As alterações financeiras passam por `transfer_coins`, um helper de acesso interno. O ledger é append-only do ponto de vista do cliente. Cada movimento tem referência própria.

## Modelo económico
As apostas são pares `back / lay` integralmente cobertos. Uma stake de 10 a odd 1.20 reserva 10 do lado BACK e 2 do lado LAY. A liquidação distribui as 12 moedas existentes, sem emissão. Um anúncio de revenda transfere uma das duas posições existentes. O comprador paga o preço e recebe o colateral já existente do vendedor; este liberta a reserva e recebe o preço. A soma dos saldos disponíveis e reservados de todos os jogadores permanece constante em cada operação P2P.

Uma oferta com stake não correspondida conserva a reserva do proponente; cancelar ou fechar o mercado liberta a fração não executada.

Os únicos eventos que aumentam o fornecimento total são o grant inicial e o grant semanal aos espectadores. O crédito semanal requer execução administrativa e é idempotente por conta/semana UTC.

## Segurança concorrente
As funções de trading bloqueiam o mercado antes de alterar ofertas/posições, prevenindo transações após settlement. O matching bloqueia a oferta `FOR UPDATE`, e a revenda bloqueia listing e posição. Constraints e checks impedem gastos acima do saldo disponível.

Para produção, testar deadlocks intercarteiras, reentradas, roundings e falhas no meio das transações, usando duas sessões PostgreSQL concorrentes reais.

## Regras em aberto
- A política de empates, abandono e falta de score do campeonato.
- Precisão temporal/schedule de snapshots semanais e mensais.
- Uma métrica de mark-to-market credível quando houver liquidez.
- Transferências fracionadas de posições e os correspondentes colaterais.
- Reversões administrativas após liquidação; neste MVP o settlement é final.

## Plano de testes
1. Unitários das fórmulas de YTD, odds e colateral.
2. SQL de integração num projeto descartável: matrícula, voto, carteira, offers, match, cancelamento, revenda e settlement.
3. Casos adversariais usando dois utilizadores autenticados e sessões paralelas.
4. Testes manuais de UI em browser e mobile.

**Os testes SQL E2E exigem um Supabase de teste e não podem ser executados enquanto não fizeres o setup.**
