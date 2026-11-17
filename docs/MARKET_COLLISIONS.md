# #11 — colisões entre mercados legados e gerados

Migração 17: `202611170003_market_collisions.sql`, dependente de 01–16.
**Apenas versionada; nenhum SQL executado no Supabase remoto.** O frontend não
instala migrações. A instalação acrescenta uma referência nullable e estruturas
de revisão, sem resolver colisões nem alterar dados preexistentes.

## Tratamento permitido

Quando uma associação encontra uma posição ocupada no calendário, «Rever colisão
com o gerado» compara os dois contratos e mostra o que será mantido. Um administrador
pode fazer o **legado compatível ocupar a posição de um gerado intacto**, com nota
de 10–2000 caracteres e a impressão da pré-visualização.

O legado mantém ID, título, pergunta, modalidade, corte, referências, outcomes,
ofertas, trades, revendas, posições, custos, reservas e pagamentos. Só recebe a
ligação à definição e à ocorrência. Pode já ter exposição, desde que o contrato
seja exatamente compatível e os participantes coincidam com a participação efetiva.

O gerado mantém o seu ID, todos os outcomes, título, regras e datas. Perde apenas
a ligação à posição do calendário e recebe `replaced_by_market_id`, que aponta
para o legado mantido. Fica **substituído e sem negociação/apuramento próprios**,
sem passar a `void`, sem ser apagado e sem devolver moedas. O estado contratual
anterior é conservado; a indicação de substituição é metadado distinto.

## Condições e bloqueios

- Ambos ainda abertos e antes do corte, com período operacional sem fontes finais.
- Mesmo campeonato, sprint, periodicidade, categoria, modalidade, referência anterior,
  política de entrada e início; universo de concorrentes coincidente.
- O ocupante tem ligação de geração e não tem associação revista/substituição anterior.
- O gerado nunca teve qualquer oferta, mesmo cancelada/preenchida, trade ou posição,
  classificação ou resolução. Não se esvaziam contratos para os tornar elegíveis.
- As condições normais da associação 16 continuam a aplicar-se ao legado, incluindo
  baseline efetivo e correspondência exata ao calendário.

Qualquer histórico económico no gerado bloqueia esta operação. Os dois mercados
permanecem com as suas identidades e exposições, sem fusão, escolha de vencedor,
transferência de posições ou reembolso. Períodos fechados e fontes congeladas não
são substituídos. Não se encadeiam substituições nem se transfere uma associação
revista para outro contrato.

## Transação e auditoria

`preview_market_collision` é de leitura. `resolve_market_collision` obtém os locks
de admissão, captura e negociação e os locks das duas linhas, revendo o relógio,
contratos, participantes, fontes, suspensão e assinaturas económicas antes de aplicar.
Uma nova oferta, correspondência, entrada ou passagem do corte invalida a revisão.

A posição é libertada pelo gerado e ocupada pelo legado na mesma transação.
`market_collision_resolutions` guarda autor, data, nota, plano e os dois estados
antes/depois. Os dados financeiros privados entram apenas como assinaturas opacas.
Repetir a mesma revisão devolve o mesmo registo, sem novos efeitos.

Um trigger só admite essas transições exatas e auditadas. O arquivo e os seus
outcomes tornam-se imutáveis. O leitor partilhado de compatibilidade com exceção
de posição ocupada é privado; a associação normal continua a bloquear colisões.

## Depois da resolução

- Geração e retoma reencontram o ID do legado no calendário, sem novo duplicado.
- Entradas efetivas chegam ao legado pelas regras existentes. O gerado arquivado
  não recebe outcomes novos, recolhas, classificações ou liquidações.
- Todas as operações de negociação e apuramento bloqueiam o arquivo no servidor.
  Funções anteriores ficam privadas; a referência não é apenas um bloqueio da UI.
- «Gerados substituídos» conserva o nome de cada arquivo e permite consultar o
  contrato mantido. O arquivo sai das listas de negociação e liquidação.
- Se a bet estiver suspensa, o legado passa a respeitar essa suspensão, conforme
  indicado na revisão. Cancelamentos do legado continuam disponíveis.

O fecho do legado usa a recolha comum e os snapshots imutáveis existentes. Valor
no fecho e delta continuam separados, podendo produzir vencedores distintos.
**Empate/zero continua bloqueado**, com posições e reservas intactas.

## Evidência e limites

Guarda de migração nos três percursos compara contratos, outcomes, fontes, histórico,
financeiro, calendário e auditorias; exclui apenas a nova referência nullable.
SQL verifica preservação integral de uma revenda e dos seus custos/lucros, as duas
modalidades, ofertas canceladas, geração/entrada após substituição, imutabilidade
do arquivo, bloqueios de negociação/validação/liquidação, permissões e idempotência.

Sessões PostgreSQL reais concorrem em revisões duplicadas, dois legados para o
mesmo gerado, primeira oferta, matching, entrada, geração e corte. O fluxo completo
usa recolha final e liquidação idempotente após substituição, com vencedores por
modalidade distintos e empate relevante com posições abertas preservadas.

A #11 permanece aberta para colisões com histórico económico no gerado e outras
incompatibilidades que exigiriam uma decisão própria sobre contratos. Não se ativa
fusão financeira, reversão, nulidade ou tesouraria nesta entrega.
