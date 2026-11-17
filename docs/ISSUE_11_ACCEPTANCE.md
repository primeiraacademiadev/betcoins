# #11 — aceitação do modelo atual

Âmbito revisto em 17/11/2026: não existem casos legados nem obrigação de
compatibilidade para trás. O PR #40 foi refeito sobre o código integrado até #39;
o tratamento de colisões e a migração de arquivo de gerados foram retirados.
Dados exclusivamente de teste não conformes podem ser removidos numa operação
identificada; esta entrega não apaga dados remotos nem executa migrações remotas.

Mantêm-se duas modalidades: YTD efetivo no fecho (%) e diferença em pontos percentuais
face ao original do fecho anterior, usando o baseline apenas no período da entrada.
Empate/zero permanece bloqueado. Propostas antigas de anular/devolver colaterais
ficam substituídas por esta instrução; não são requisitos pendentes desta entrega.

## Matriz dos 30 critérios

«Coberto» significa implementação e testes versionados; integração do PR e instalação
remota são estados distintos. Os testes SQL usam PostgreSQL descartável em localhost.

| N.º | Critério vigente e evidência | Estado |
|---|---|---|
| 1 | Geração idempotente de definições e ocorrências até ao fim de 2026; `recurring_bets.sql`, `recurring_bets_concurrency.py`. | Coberto |
| 2 | Participação automática após primeiro YTD, não só aprovação; `entry_baselines.sql` e concorrência de admissão/score. | Coberto |
| 3 | Entradas não alteram períodos fechados, posições ou pagamentos; testes de recorrência e baseline. | Coberto |
| 4 | Novas ofertas, matching e revenda bloqueados após corte verificado depois do lock; testes P2P/recorrência/fecho. | Coberto |
| 5 | Modalidade absoluta usa YTD efetivo no fecho. A decisão posterior acrescentou delta como modalidade distinta; `market_modes*` e aceitação concorrente. | Coberto, redação original substituída |
| 6 | Gestão por definição/calendário, sem selecionar concorrentes; `RecurringBets`, testes de apresentação e navegador. Ferramentas de reconciliação/associação legada saem da gestão. | Coberto |
| 7 | Segurança, idempotência e conservação do modelo atual nos três percursos SQL; não é exigido converter dados de testes antigos. | Coberto no âmbito revisto |
| 8 | Seleção de qualquer ocorrência; histórico consultável sem negociar; testes de navegador e guards de corte. | Coberto |
| 9 | Histórico usa snapshots/validações e estatísticas imutáveis; updates posteriores a 99/100 não alteram os resultados. | Coberto |
| 10 | Estatísticas partilhadas por ocorrência/modalidade e destaque de 1.º/2.º/último; igualdade com todas as validações e testes de destaque/empate. | Coberto |
| 11 | Histórico sem dados mostra indisponibilidade, nunca YTD atual ou zero inventado; SQL, apresentação e navegador. | Coberto |
| 12 | Navegação, mudança de modalidade, regresso ao período corrente, leitura e ausência de overflow testados em Chromium a 1280 e 390 px. | Coberto |
| 13 | Rankings absolutos/delta separados com as mesmas fontes; aceitação com seis definições e três lugares por definição. | Coberto |
| 14 | Vencedores distintos por valor e delta; testes de modalidades/entrada e aceitação concorrente. | Coberto |
| 15 | Sem referência auditável, delta não valida nem liquida; entrada genuína no primeiro período é a exceção aprovada, não zero por omissão. | Coberto no critério revisto |
| 16 | Nova modalidade não redefine o contrato absoluto; modos explícitos e imutáveis. | Coberto |
| 17 | Entrada 12 → fecho 15 = +3 pp; `entry_baselines.sql`. | Coberto |
| 18 | Período seguinte 15 → 17 = +2 pp, sem reutilizar 12; `entry_baselines.sql`. | Coberto |
| 19 | Aprovação sem score mantém ausência e solicita primeiro YTD; testes de entrada/apresentação. | Coberto |
| 20 | Origem e datas de admissão, baseline e fecho distinguíveis; snapshots/declarações/baseline imutáveis. Correções retroativas não permitidas. | Coberto |
| 21 | Updates livres antes do fecho; declaração final pendente bloqueia update corrente e é resolvida por ordem; testes de fecho e aceitação. | Coberto |
| 22 | Última sessão NYSE, feriados, fechos antecipados e DST; `recurring_bets.sql` verifica datas oficiais versionadas de 2026. | Coberto |
| 23 | Omissão usa último original −1 pp, com origem visível; aceitação usa 4 → 3 e testes de fecho verificam 12 → 11. | Coberto |
| 24 | Penalização local não altera original/baseline nem se propaga ao delta seguinte; testes de fecho e entrada. | Coberto |
| 25 | A anulação/devolução proposta foi substituída pela instrução de bloquear empate/zero. Testes confirmam ledger e posições intactos. | Substituído, sem devoluções |
| 26 | Migração 17 persiste rankings, valores, referências e penalizações por ocorrência/modalidade ao apurar, quando existem todas as fontes. Dados insuficientes ficam explicitamente por apurar. | Coberto |
| 27 | Fontes, estatísticas, validações e resultados imutáveis; finalização/validação/liquidação concorrentes não duplicam efeitos. | Coberto |
| 28 | Semana/mês/ano coincidem no fim do campeonato: uma declaração final por concorrente, três snapshots e seis rankings; aceitação concorrente. | Coberto |
| 29 | Empate no primeiro bloqueia 1.º e 2.º; último é independente segundo os seus scores. Não há anulação automática. Testes de modalidades e destaque. | Substituído pelo bloqueio |
| 30 | Não há devolução por empate. Posições, reservas e revendas preservadas; testes financeiros/concorrentes de empate. | Substituído pelo bloqueio |

## Lacunas completadas no PR #40

- Histórico público de criação de ofertas e execuções, incluindo canceladas/preenchidas,
  com paginação estável mesmo com timestamps iguais e sem publicar titulares/custos privados.
- Resultado e data de liquidação em leitura; data de validação e destaque do lugar que
  cada mercado remunera, incluindo empates e ausência real de 2.º lugar.
- Filtro explícito por lugar, atualização das classificações após ações e testes reais
  de navegador com os componentes e CSS do produto em desktop/telemóvel.
- Estatísticas imutáveis comuns por ocorrência e modalidade, disponibilizadas pela API
  e interface. Fecho e validação usam a mesma persistência idempotente.

## Estatísticas e limites temporais

`occurrence_classifications` contém uma linha por ocorrência/modalidade, com os
IDs das fontes, valores, ranks e proveniência por concorrente. A recolha administrativa
materializa os rankings completos; se faltar uma referência anterior não se materializa
um ranking fictício. A validação só materializa quando as fontes estão completas.
Uma linha existente nunca é corrigida; fontes divergentes são rejeitadas.

As estatísticas são congeladas, mas isso não equivale a validação administrativa
ou pagamento. Os dois passos mantêm-se separados. O leitor de estatísticas não
reconstrói nem grava dados ao consultar uma ocorrência sem resultados finais.

O histórico de ofertas descreve criação, odds e **estado/quantidade disponíveis atuais**.
Não inventa a quantidade original de uma oferta cancelada. As transações executadas
mostram a stake e responsabilidade realmente registadas. O cursor ordena timestamp
e ID do evento; cada página é de leitura e não altera carteiras/ledger.

## Instalação e validação

Migração 17: `202611170003_occurrence_results.sql`, dependente de 01–16.
É uma evolução do esquema versionado, sem importação ou compatibilidade de legado.
As migrações 15–16 já integradas mantêm-se no histórico de instalação; as suas
ferramentas deixam de ser um fluxo da gestão ou um requisito de aceitação da #11.
A migração 17 retira aos clientes os endpoints de criação individual e de
reconciliação/associação; validação e liquidação exigem o contexto recorrente explícito.

Executar CI de unitários/apresentação, build, três percursos SQL e sessões concorrentes.
O novo percurso completo gera seis definições e 18 mercados pelo calendário real,
apura fechos coincidentes com omissão, congela seis rankings, valida todos os lugares,
liquida os não empatados e preserva os empatados. A navegação é testada separadamente
em navegador com dados determinísticos e o CSS real, sem ligar ao Supabase.

Migrações no Supabase remoto e limpeza de dados remotos continuam por executar.
O ranking dos apostadores por P&L de um mercado não foi escolhido como parte deste
MVP; a classificação tratada aqui é a dos concorrentes. Correções históricas e
suporte financeiro a empate/zero continuam fora do âmbito autorizado.
