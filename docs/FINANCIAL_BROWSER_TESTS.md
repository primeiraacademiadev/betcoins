# Fluxos financeiros no navegador — #8

## Contrato do ensaio

`npm run test:financial` usa a aplicação completa (`src/main.tsx`), o cliente
Supabase real, HTTP, PostgREST 16.6 e PostgreSQL 16 descartáveis no CI. Todas as
leituras e mutações financeiras passam pelas RPCs e políticas RLS reais. Não há
implementação alternativa de saldos, ofertas, posições ou pagamentos nos testes.

O ensaio identificou que a view antiga `my_positions`, criada antes da coluna de
custo, não expunha `cost_basis`. A carteira passa a consultar `positions`, que já
tem SELECT e RLS por titular. O navegador verifica o preço pago na revenda e o
lucro potencial apresentado; uma compra por 6 de uma posição com payoff 6 mostra
custo 6 e lucro potencial 0, preservando a privacidade. Não exige migração nova.

Apenas a identidade de entrada é controlada: o endpoint Auth devolve os quatro
utilizadores fictícios da fixture. JWTs são assinados com uma chave aleatória por
job; o PostgREST valida a assinatura e assume `authenticated`, através de um
gateway sem herança de privilégios. O navegador nunca recebe a chave de assinatura
nem credenciais PostgreSQL. Esta suite não testa OAuth nem o serviço GoTrue real.

O job tem a sua própria base `betcoins`, exclusivamente em localhost. Instala aí as
migrações versionadas, sem credenciais Supabase e sem acesso à base remota. A
preparação recusa execução fora do CI, hosts/destinos alternativos e redirecionamento
libpq. Entre testes limpa somente dados desse ambiente descartável. O calendário,
os resultados e as liquidações respeitam o relógio real; não são desativados
triggers, reescritos snapshots ou inventadas classificações congeladas.

## Cenários

Cada cenário corre nas duas modalidades (`snapshot_value` e
`snapshot_delta_previous`) e em Chromium a 1280 e 390 px:

1. Publicação BACK/LAY e confirmação dos riscos; desistência da confirmação sem
   posição criada; aceitação parcial, colateral dos dois lados e cancelamento do
   remanescente; lote de revenda inválido e válido, compra parcial, transferência
   de titularidade/custo e P&L realizado; saldo insuficiente bloqueado na interface
   e rejeitado pelo servidor; escrita financeira indevida e JWT inválido recusados;
   isolamento das carteiras e reconciliação final.
2. O servidor aceita uma oferta e a resposta é perdida. O navegador pede atualização
   antes de repetir; a atualização mostra a posição e a reserva; repetir a mesma
   aceitação já preenchida é rejeitado sem novo ledger ou posição.
3. Fecho real de duas ocorrências curtas, declarações finais e apuramento real na
   preparação. No navegador, a administração valida e liquida o resultado congelado.
   As modalidades têm vencedores diferentes. Repetir a liquidação não paga de novo;
   o empate fica bloqueado na interface e na RPC, sem movimentos; um utilizador
   comum não liquida; carteiras e P&L correspondem aos pagamentos.

As duas janelas de navegador são contextos isolados por identidade. Os testes
verificam que o conteúdo cabe na largura escolhida e bloqueiam pedidos para
serviços externos. Em falha, guardam capturas e traces apenas com dados sintéticos.
O teste de resposta perdida interrompe somente a entrega de uma resposta real;
não substitui o resultado financeiro nem altera saldos.

## Limites

A suite financeira complementa as sessões concorrentes reais e o ensaio de
restauro. Não certifica OAuth, Storage, limites do plano, notificações de quota nem
recuperação do Supabase hospedado. Não implementa reversões financeiras e não
contorna empate/zero. Não cria compatibilidade legada e não executa migrações
no Supabase remoto. `vite.financial.config.ts` é exclusivamente de testes; o build
e a publicação normais continuam a usar `vite.config.ts`.


## Devolução por empate — migração 18

Os cenários de liquidação passam a cobrir a devolução ao mercado inteiro nas duas
modalidades e a 1280/390 px: BACK 10/odd 1,20, LAY 2, remanescente não correspondido,
revenda integral por 7 e revenda parcial posterior por 4. Verificam confirmação e
cancelamento do diálogo, autorização, repetição idempotente, titulares finais,
P&L/custos e histórico público. As revendas não são desfeitas. Antes da migração
18, empate/zero permanece bloqueado; nenhum teste executa migrações remotas.
