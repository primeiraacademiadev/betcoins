# #11 — bets recorrentes e calendário 2026

## Entrega

Migração 12: `202611160003_recurring_bets.sql`, dependente de 01–11.
**Apenas versionada; não foi executada no Supabase remoto.** A publicação do
frontend não instala SQL. Antes da instalação autorizada: backup, revisão e teste
numa cópia com o mesmo esquema; aplicar as migrações pela ordem, nunca a baseline
por cima de uma instalação existente nem fixtures numa base real.

## Definições, ocorrências e mercados

- Uma definição por campeonato × periodicidade (anual/mensal/semanal) × modalidade.
- As duas modalidades mantêm-se explícitas: valor do snapshot final (%) e delta
  face ao **fecho anterior** (pp), sem capitalização nem substituição por start.
- Um calendário partilhado por campeonato/periodicidade; as duas modalidades e
  os três lugares usam o mesmo período e as mesmas fontes de fecho.
- Ativar uma definição gera antecipadamente os mercados de 1.º, 2.º e último
  dos períodos ainda negociáveis até ao fim do campeonato. Repetir/reconciliar
  não duplica definições, ocorrências, mercados nem outcomes.
- São necessários pelo menos dois concorrentes. Sem participantes suficientes
  ou referência anterior única, a ocorrência é indicada como bloqueada; não se
  inventa uma referência ou score. Uma admissão posterior volta a reconciliar.
- O calendário inclui períodos passados, mas a geração não cria apostas
  retroativas. Essas ocorrências são consultáveis sem mercados/resultados fictícios.
- Os mercados futuros podem negociar desde a publicação até ao seu corte. A data
  de início descreve o período de apuramento; não impõe um fecho antecipado.

Não se associam mercados antigos automaticamente às novas definições. Um sprint
existente com o mesmo início mas fecho incompatível bloqueia a preparação inteira
para revisão, sem alterar o histórico. Sprints coincidentes e compatíveis podem
ser usados; a proveniência dos seus snapshots continua sujeita às regras E2.

## Calendário

O calendário versionado suporta **2026** e falha de forma explícita para outros
anos. Os limites são truncados aos instantes do campeonato.

- Semanal: fecho da última sessão de ações NYSE de cada semana ISO, usando
  `America/New_York`, feriados e encerramentos antecipados. O intervalo seguinte
  começa imediatamente após o fecho anterior, mantendo uma referência inequívoca.
- Mensal: mês civil de `Europe/Lisbon`, incluindo mudanças de hora; fim no último
  microssegundo anterior ao mês seguinte, limitado pelo fecho do campeonato.
- Anual: limites do campeonato, incluindo 31/12/2026 conforme o registo existente.

Fonte oficial, verificada em 16/11/2026: [NYSE — Holidays & Trading Hours](https://www.nyse.com/trade/hours-calendars).
O calendário preserva 251 sessões de 2026. Os testes verificam Good Friday,
Independence Day, Thanksgiving, Natal, fechos antecipados e diferenças DST.
As sessões são dados versionados e imutáveis pela aplicação; revisão do calendário
oficial exige uma alteração própria, não um ajuste silencioso de apostas existentes.

## Admissões e preservação de contratos

Após uma admissão, um trigger transacional reconcilia as definições ativas:
acrescenta o novo outcome aos mercados abertos e futuros cujo corte ainda não
passou. Não modifica ofertas, odds, trades, posições, carteiras ou pagamentos.
A interface avisa que o universo de concorrentes pode aumentar.

Mercados passados, liquidados ou com classificação congelada não recebem novos
outcomes. Não se reabre uma ocorrência nem se altera o resultado histórico.
A admissão mantém o estado “aguarda primeiro YTD” quando não há declaração;
não cria 0 nem referência anterior fictícia. Num delta sem score no fecho anterior,
o apuramento continua bloqueado pelas regras da migração 11.

Suspender uma definição bloqueia novas ofertas, aceitações e revendas dos seus
mercados. Não apaga posições nem impede cancelar ofertas não correspondidas ou
liquidar regularmente após validação. Retomar reconcilia os períodos restantes e
admissões pendentes, preservando os contratos existentes.

Geração, admissão, revisão de snapshots e negociação seguem a mesma ordem de
locks. O corte é verificado após a espera pelo lock. Não há sobreposição entre
geração idempotente e criação duplicada por duas sessões concorrentes.

## Navegação e classificações

A gestão permite ativar/suspender definições e reconciliar o calendário, sem
selecionar concorrentes manualmente. Em Mercados, escolher bet e ocorrência
mostra as datas, estado e os mercados correspondentes. Uma ocorrência sem
mercados não mostra resultados de outro período como fallback.

Enquanto um mercado está aberto, a classificação **provisória** usa as últimas
declarações, com a data visível. O delta só aparece se houver referência anterior
congelada para o concorrente. Depois do corte, esta vista deixa de usar scores
atuais: a consulta histórica usa exclusivamente os snapshots/validações existentes
e sinaliza dados ausentes. A classificação definitiva e a liquidação continuam no
fluxo de revisão e validação da migração 11; a geração não liquida automaticamente.

## Limites mantidos e critérios ainda abertos

Empate/zero permanece **bloqueado**, sem void, devoluções ou tesouraria nova.
As duas modalidades da #1 e a imutabilidade dos resultados são preservadas.

Esta entrega cobre a recorrência, geração, calendário, atualização de outcomes e
navegação. **A #11 permanece aberta:** as propostas antigas sobre declaração final
obrigatória, prazo administrativo, penalizações, baseline especial para entradas
a meio do período e nulidade por empate não são ativadas. Exigem reconciliação
com as regras canónicas mais recentes e a instrução atual de bloquear empate/zero.
Não se implementa reversão nem migração retroativa de mercados antigos.

## Evidência

- Testes unitários de estados, filtros por ocorrência, histórico indisponível e
  apresentação das modalidades/aviso de elegibilidade.
- SQL nos três percursos de instalação: calendário, DST, limites, seis definições,
  idempotência, referências delta, ausência de snapshots inventados, admissões,
  mercados históricos preservados, pausa/retoma, RLS e reconciliação de carteiras.
- Sessões reais concorrentes: duas gerações, votos decisivos e trigger de admissão
  por não administrador, duas admissões, negociação em simultâneo com reconciliação
  e suspensão, preservando contratos e conservação de BetCoins.

## Seguimento: migração 13

A [recolha de declarações finais e as penalizações locais](FINAL_DECLARATIONS.md) estão agora preparadas na migração 13. Este seguimento atualiza o limite histórico da entrega 12 acima; não ativa baseline especial de entrada, empate/zero ou reconciliação legada. Instalação remota continua pendente.

## Seguimento: migração 14

O [YTD inicial e a participação efetiva](ENTRY_BASELINES.md) estão agora preparados na migração 14. Atualiza o limite histórico sobre entradas acima: períodos em curso à entrada usam o primeiro YTD; os seguintes usam o fecho anterior. Históricos e contratos não são reescritos; a instalação remota e a reconciliação legada continuam separadas.


## Seguimento: migração 15

A [reconciliação revista de mercados legados](LEGACY_MARKET_RECONCILIATION.md) permite corrigir contratos ainda negociáveis sem histórico de negociação, com pré-visualização e auditoria. Contratos com exposição e resultados históricos são preservados. Migração apenas versionada; instalação remota pendente.


## Seguimento: migração 16

A [associação revista às bets recorrentes](LEGACY_BET_ASSOCIATION.md) permite organizar mercados compatíveis com revisão e auditoria, alterando apenas a ligação. Atualiza o limite anterior sobre associação: colisões e fusões continuam bloqueadas. Migração apenas versionada, sem instalação remota.


## Âmbito revisto e aceitação final — 17/11/2026

Não existem casos legados nem requisito de compatibilidade para trás. Reconciliações, associações e colisões deixam de bloquear a #11. O PR #40 foi refeito para [completar e testar os critérios do modelo atual](ISSUE_11_ACCEPTANCE.md): histórico de ofertas/trades, resultados por ocorrência e navegação. Migração 17 apenas versionada; empate/zero bloqueado; nenhuma instalação remota. Esta decisão substitui os limites anteriores relativos ao legado.
