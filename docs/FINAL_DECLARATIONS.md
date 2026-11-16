# #11 — declarações finais obrigatórias e penalizações

## Entrega e instalação

A migração 13 (`202611160004_final_declarations.sql`) está **apenas versionada** e
requer 01–12. Não foi executada no Supabase remoto. O frontend não instala SQL.
Antes de instalação futura autorizada: backup, revisão e teste numa cópia com o
mesmo esquema. Não reaplicar baseline nem executar fixtures numa base real.

O PR #35 acrescentou a recorrência. Esta entrega acrescenta a recolha de YTD de
fecho e a penalização local autorizada na #11. Não altera as duas modalidades nem
implementa empate/zero, void, devoluções ou tesouraria.

## O que cria uma obrigação

Uma ocorrência recorrente com mercados publicados passa a exigir declarações
quando atinge o corte. Calendário histórico sem mercados não cria obrigações
retroativas. Um snapshot final que já existia antes deste fluxo permanece intacto:
não é reaberto nem recalculado.

Os fechos semanal/mensal/anual coincidentes do mesmo campeonato partilham uma
ronda e **uma única declaração por concorrente**. Os períodos e participantes são
identificados pelos outcomes que estavam publicados no corte. Uma admissão após
esse instante não entra retroativamente no fecho.

Ao aceder, o concorrente vê os fechos por ordem cronológica. Enquanto houver um
fecho por resolver, `set_my_score` recusa atualizar o YTD corrente, incluindo por
RPC direta. A interface mostra a declaração de fecho e desativa os formulários
correntes. Um fecho posterior não pode ser declarado antes do mais antigo.

## Declaração, prazo e encerramento

- O YTD final é relativo ao instante de fecho indicado, não ao instante atual.
- Sem prazo administrativo fixado, a recolha continua aberta. Não existe prazo
  universal de 24 horas nem outro valor predefinido.
- A gestão pode fixar um prazo futuro com nota. Depois de anunciado, esse prazo
  fica imutável; não pode ser encurtado ou alterado silenciosamente.
- Se ainda não fixou prazo, a gestão pode **Encerrar recolha e apurar**, com nota
  e confirmação: o instante da ação passa a ser o prazo efetivo.
- Se prometeu um prazo futuro, o apuramento só é permitido depois desse instante.
- Declarações são aceites estritamente antes do prazo. O relógio é verificado
  depois da espera pelos locks; transações antigas não contornam o limite.

Uma declaração final é imutável. Repetir o mesmo pedido devolve o mesmo registo;
outro valor é recusado. Não altera `competitors.ytd` nem entra no histórico de
atualizações correntes. Depois de resolver todos os fechos, o concorrente pode
registar uma atualização corrente separada. Se perdeu o prazo sem declarar,
aguarda o apuramento administrativo para a obrigação ficar resolvida.

## Penalização local e proveniência

O apuramento cria os snapshots finais das ocorrências, sem executar liquidação:

| Situação | Snapshot efetivo |
| --- | --- |
| Declaração final recebida no prazo | YTD final declarado, sem penalização |
| Omissão, mas existe YTD conhecido no corte | Último valor original conhecido − **1 pp** |
| Nunca existiu YTD conhecido | Sem classificação; não inventar 0 ou penalização |

Exemplo: último YTD conhecido **12%**, sem declaração final → original **12%**,
penalização **−1 pp**, efetivo **11%**. O snapshot guarda origem, data, referência
temporal, valor original, penalização, valor efetivo e motivo. Esses campos ficam
visíveis nos rankings do mercado e na revisão do campeonato.

Uma omissão usa a última atualização corrente registada até ao corte ou uma
declaração final de período anterior que já fosse conhecida nesse corte. Uma
declaração feita mais tarde não é introduzida retroativamente como fonte conhecida.
O valor é escolhido pela referência temporal que descreve, não por uma atualização
futura nem pelo YTD corrente depois do corte.

Uma declaração final explícita pode ser recebida depois do corte, dentro da
recolha administrativa: é uma declaração histórica específica, com data real de
receção preservada. Não é uma atualização corrente retrodatada. O seu ID serve
todos os snapshots dos fechos coincidentes.

Não existe acumulação automática de penalizações: cada omissão produz −1 pp
apenas no seu snapshot. Se o valor original for −100%, o efetivo pode ser −101%
como score penalizado; isso não reescreve o YTD declarado nem introduz um piso
que não foi aprovado nas regras.

## Duas modalidades e período seguinte

`snapshot_value` ordena o YTD efetivo do fecho atual.
`snapshot_delta_previous` calcula:

`efetivo_atual − original_do_snapshot_de_fecho_anterior`

A referência anterior usa o valor original preservado, sem transportar a sua
penalização. Exemplo: anterior original 12%, efetivo penalizado 11%; atual declarado
14% → delta **2 pp**, não 3 pp. Uma nova omissão no atual aplica a sua própria
penalização de 1 pp, sem alterar o original anterior ou os resultados já fechados.
Sem referência anterior, o delta continua bloqueado; não se usa início do sprint,
baseline de entrada ou zero como substituto.

As classificações já validadas e pagamentos existentes não são reescritos. Após
o apuramento, a revisão/validação da classificação e a liquidação regular continuam
a ser ações separadas. Empates, incluindo os criados pela penalização, mantêm a
liquidação **bloqueada**, sem pagamentos ou devoluções improvisados.

## Compatibilidade e limites restantes

As capturas legadas de períodos não recorrentes conservam o fluxo anterior.
Nos recorrentes, a captura de fecho antiga encaminha para a recolha/apuramento,
impedindo contornar as declarações; depois de apurado, apenas devolve o snapshot
existente de forma idempotente. A captura inicial legada continua disponível.

Não há reabertura, correção retroativa, alteração da elegibilidade, baseline
especial para entradas a meio do período ou reconciliação de mercados antigos.
A #11 mantém esses pontos pendentes, além das decisões financeiras de empate/zero.

## Verificação

- Testes de interface: ordem dos fechos, prazo não fixado/expirado, YTD válido,
  original 12 → efetivo 11, ausência versus zero e indicação de penalização local.
- SQL nos três percursos: fechos coincidentes, bloqueio do YTD corrente e da
  captura antiga, imutabilidade/idempotência, respeito pelo prazo, fontes de
  omissão, dados ausentes e delta sem propagação da penalização anterior.
- Sessões PostgreSQL concorrentes: declaração repetida, declaração tardia contra
  apuramento, apuramento/validação/liquidação repetidos, conservação monetária e
  empate penalizado com posições/reservas intactas.
