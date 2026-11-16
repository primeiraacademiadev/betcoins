# E4 / #5 — mercados P2P e liquidação validada

## Entrega e limite

A migração 10 (`202611160001_validated_market_settlement.sql`) é apenas versionada;
não foi executada no Supabase remoto. Requer as migrações 01–09. A publicação do
frontend não instala SQL. Sem a migração, o painel de apuramento indica indisponibilidade.

Esta entrega protege a liquidação regular existente. Não fecha integralmente a #5:
as modalidades `snapshot_value` e `snapshot_delta_previous` e o empate/zero da #1
continuam dependentes do desenho financeiro aprovado. Não existe tesouraria nova,
anulação por empate, devolução improvisada nem escolha técnica de um empatado.

| Critério | Comportamento e verificação |
| --- | --- |
| BACK/LAY e aceitação parcial | Motor existente preservado; testes SQL com ambos os lados, odds fracionárias, excesso de stake, autocontratação e entradas nulas/NaN |
| Colateral e conservação | Cancelamento devolve só a parte não correspondida; liquidação devolve o remanescente e paga os titulares atuais. Reconciliação de cada carteira e soma de moeda verificadas |
| Concorrência | Mutex transacional comum antes de mercado/oferta/posição/carteiras. Sessões reais disputam aceitações, saldo em mercados diferentes, compra, cancelamento e settlement |
| Fecho | Relógio real após espera pelo lock; testes iniciam transações antes do corte, retêm o lock até depois dele e tentam colocar/aceitar/revender/comprar |
| Resultado validado | O mercado identifica campeonato/sprint. O resultado vem exclusivamente das linhas imutáveis da validação E2 e do respetivo snapshot, com o mesmo instante de fecho e universo de concorrentes |
| Empates/ausências | Bloqueio explícito se faltar algum score, se houver empate no lugar relevante ou se o 2.º lugar não existir (1,1,3). Não inventa vencedor/zero/void |
| Autorização | Admin obrigatório na criação/liquidação; cores internas sem EXECUTE para clientes; escritas diretas bloqueadas e resolução imutável |
| Auditoria/idempotência | `market_resolutions` liga mercado, validação, outcome, administrador e data. Repetir a mesma liquidação nova não duplica pagamentos; resultado diferente ou legado é rejeitado |
| Revendas e P&L | Pagamento e custo do titular final preservados; resultado das vendas anteriores não é revertido |
| Interface | Retirada a seleção manual de vencedor; mostra motivo de bloqueio, critério existente e resultado calculado pelo servidor |

## Critérios existentes versus modalidades da #1

O anual existente usa YTD absoluto; os sprints existentes usam `end − start`
do próprio sprint, em pp. Isto **não** implementa os dois novos tipos de mercado
da #1, nem substitui a referência pelo snapshot do período anterior. A interface
torna esta distinção visível.

O resultado é calculado sobre o universo completo congelado. Se um novo admitido
aparecer no apuramento sem outcome no mercado, a liquidação bloqueia. A política
de atualização de outcomes e elegibilidade pertence à #11; não se exclui esse
concorrente silenciosamente nem se alteram apostas existentes nesta entrega.

## Instalação e mercados existentes

Antes de qualquer instalação autorizada: backup, revisão e teste numa cópia.
Aplicar 09 antes de 10. Não reaplicar a baseline numa base existente. A migração
10 é transacional e não contém fixtures de teste nem comandos de acesso remoto.

Os mercados antigos permanecem consultáveis/negociáveis até ao seu corte, mas
não recebem uma associação retroativa presumida. A liquidação desses mercados
fica bloqueada, exigindo um procedimento próprio de reconciliação. Resultados
já liquidados, carteiras e históricos não são recalculados. O endpoint legado de
criação pede a interface atualizada; os novos mercados usam período explícito,
hora de fecho do período e todos os concorrentes atuais.

Cancelar uma oferta própria não correspondida continua permitido depois do corte
e é idempotente. A criação, aceitação e revenda não são permitidas após o corte.
O mutex único é uma escolha conservadora para o volume do MVP; serializa operações
financeiras entre mercados. Dotações administrativas continuam a usar os locks
de carteira existentes; em caso de conflito transacional a operação falha inteira.

## Verificação

`tests/db/markets.sql`: nos três percursos de instalação/upgrade, depois dos testes
legados e da migração 09. Fixtures revertidas por ROLLBACK.
`tests/db/markets_concurrency.py`: sessões PostgreSQL reais, apenas localhost.
Testes de interface cobrem razões de bloqueio e apresentação do resultado.

Continuam fora desta entrega: geração recorrente (#11), resolução financeira de
empate/zero, modalidades adicionais da #1, void/reversão e migração de produção.

## Seguimento: migração 11

As duas modalidades adicionais estão agora preparadas no código da migração 11, com classificação validada própria e liquidação regular; ver [modalidades](SNAPSHOT_MARKET_MODES.md). A #5 continua aberta para empate/zero, reconciliação legada e dependências de calendário/elegibilidade. Esta secção atualiza o limite histórico da entrega 10 acima. Nenhuma destas migrações foi aplicada remotamente.
