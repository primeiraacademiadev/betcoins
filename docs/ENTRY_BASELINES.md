# #11 — YTD inicial e entradas a meio do período

## Entrega

Migração 14: `202611160005_entry_baselines.sql`, dependente de 01–13.
**Apenas versionada; não foi executada no Supabase remoto.** O frontend não instala
SQL. Antes de instalação autorizada: backup, revisão e teste numa cópia. Não
reaplicar baseline nem executar fixtures numa base real.

O PR #36 acrescentou declarações finais e penalizações locais. Esta entrega
acrescenta participação efetiva a partir do primeiro YTD, sem alterar as duas
modalidades ou ativar empate/zero.

## Admissão e participação efetiva

| Estado | Consequência |
| --- | --- |
| Admitido — aguarda YTD inicial | Sem baseline e sem nova participação operacional nos mercados |
| Primeiro YTD declarado | Inicia participação efetiva, com valor e instante auditados |
| Atualizações correntes seguintes | Atualizam o YTD corrente, preservando o primeiro valor |

O primeiro YTD é guardado em `entry_baselines`, por concorrente e campeonato:
valor, admissão, instante efetivo, ID da declaração auditada e data de registo.
Não pode ser alterado ou apagado pela aplicação. Zero declarado é válido;
ausência nunca é transformada em zero.

O formulário inicial usa `declare_initial_ytd`. O endpoint corrente continua
seguro: se for usado para o primeiro registo, o trigger do histórico também guarda
o baseline. Repetir o mesmo pedido inicial devolve o registo existente; tentar
substituí-lo por outro valor é recusado. Uma atualização corrente posterior não
modifica a referência inicial.

A admissão mantém os direitos e eleitorados de votação existentes; esta entrega
separa o início efetivo da participação nos mercados, sem reabrir votações.

## Entrada durante um período

Nos mercados com a nova política, o período guarda o seu início e a indicação de
que admite referências de entrada. Para `snapshot_delta_previous`:

- Se a participação começa no início ou durante o período, a referência desse
  concorrente é o seu **YTD inicial**, com a data efetiva visível.
- Nos períodos que começam depois da entrada, a referência volta a ser o
  **snapshot de fecho do período anterior**. O baseline inicial não é usado para
  substituir um snapshot anterior ausente.
- O fecho atual usa o valor efetivo, incluindo uma eventual penalização local;
  a referência anterior usa o original não penalizado, como na migração 13.

Exemplos: entrada com **12%**, fecho em **15%** → **+3 pp desde a entrada**.
No período seguinte, referência anterior **15%**, fecho **17%** → **+2 pp nesse
período**, não +5 pp desde o baseline original.

`snapshot_value` continua a usar o YTD efetivo no fecho, independentemente do
tempo decorrido desde a entrada, desde que a participação já fosse efetiva nesse
fecho. Não se cria uma terceira modalidade de aposta.

A comparação de deltas pode envolver janelas diferentes entre concorrentes. A
interface mostra o tipo e a data de referência por linha e identifica **janela
parcial** quando usa a entrada. A admissão não é confundida com a data do primeiro
YTD. Uma entrada exatamente no início usa a referência inicial; uma entrada depois
do corte não participa retroativamente.

## Mercados, calendário e fechos

A aprovação, por si só, deixa de criar outcomes novos. Ao registar o primeiro YTD,
a transação sincroniza as bets ativas e os mercados explícitos abrangidos pela
nova política cujo corte ainda não passou. São necessárias duas participações
com YTD inicial para gerar mercados novos. Pausas continuam a ser respeitadas;
retomar uma definição reconcilia as entradas entretanto ativadas.

Ofertas, odds, trades, posições, reservas e pagamentos existentes são preservados.
Só são acrescentados outcomes, uma vez. Mercados fechados, capturados ou validados
não são alterados. Uma entrada que fica à espera de um lock até depois do corte
é registada com a data real e só chega aos mercados ainda negociáveis.

Uma primeira ocorrência pode não ter um predecessor registado. O delta só pode
ser validado sem esse snapshot se **todos** os seus participantes tiverem uma
referência de entrada válida para esse período. Qualquer concorrente que já
participava antes do período continua a exigir o fecho anterior; não há fallback
permanente para o baseline nem para zero.

O fluxo de declarações finais congela também o ID do baseline que justificava a
elegibilidade. Quem ainda não tinha participação efetiva no corte não recebe
obrigação nem penalização retroativa por esse período. As regras de prazo,
declaração final, original/efetivo e penalização local da migração 13 mantêm-se.

## Histórico e compatibilidade

A migração recupera apenas o **primeiro registo auditado** após a admissão, dentro
dos limites do campeonato e que já existisse à data da instalação. Guarda o valor
e a data reais desse registo, identificando a origem como histórico auditado.
Não usa o YTD atual, snapshots de fecho ou declarações futuras para adivinhar uma
entrada. Sem prova auditada, a participação aguarda a primeira declaração.

Não se reescrevem snapshots, classificações validadas, fechos ou pagamentos. A
política nova fica explícita apenas nos mercados ainda negociáveis e sem
classificação/captura final; mercados históricos conservam as regras anteriores.
Outcomes antigos de admitidos sem baseline não são apagados: contratos desse
legado podem exigir reconciliação própria, continuando bloqueados se o universo
do mercado não coincidir com o apuramento. Não se fabrica elegibilidade histórica.

## Verificação e limites

- Guarda de migração compara histórico de scores, snapshots, classificações,
  resoluções, carteiras, ledger, posições, contratos e membros congelados.
- SQL nos três percursos verifica admissão sem zero, ativação no primeiro score,
  zero válido, primeiro valor versus atualizações, +3 pp na entrada e +2 pp no
  período seguinte, referência ausente, penalizações locais, fontes e permissões.
- Sessões reais concorrentes cobrem voto de admissão sem ativação prematura,
  primeira declaração em simultâneo com matching, pedidos duplicados, atualizações
  seguintes, entrada após o corte, elegibilidade dos fechos e liquidação regular.
- As duas modalidades podem produzir vencedores diferentes; empates entre
  referências de entrada continuam **bloqueados**, com posições/reservas intactas.

Empate/zero, void/reversão e reconciliação de contratos legados continuam fora
desta entrega. Não são ativados mecanismos de correção retroativa do baseline.


## Seguimento: migração 15

A [reconciliação revista de mercados legados](LEGACY_MARKET_RECONCILIATION.md) permite corrigir contratos ainda negociáveis sem histórico de negociação, com pré-visualização e auditoria. Contratos com exposição e resultados históricos são preservados. Migração apenas versionada; instalação remota pendente.
