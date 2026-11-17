# #11 — associação revista de mercados legados às bets recorrentes

Migração 16: `202611170002_legacy_bet_association.sql`, dependente de 01–15.
**Apenas versionada; nenhum SQL executado no Supabase remoto.** O frontend não
instala SQL. A migração cria as estruturas e funções, sem associar ou alterar
automaticamente qualquer mercado existente.

## Preparar, rever e associar

Na Gestão, preparar uma definição suspensa antes de gerar mercados. A nova ação
`prepare_bet_for_association` cria apenas a definição e o calendário; não gera
mercados nem suspende uma definição que entretanto tenha sido ativada. Repetir
a preparação de uma definição suspensa preserva o mesmo ID.

Em «Associar mercados legados às bets», escolher o mercado, a bet e a ocorrência.
`preview_market_bet_association` mostra compatibilidade, colisão, efeito da
suspensão e distinção entre associação operacional e arquivo histórico. Rever
e aplicar com nota de 10–2000 caracteres e a impressão da pré-visualização.

`associate_legacy_market` obtém os locks de admissão, captura e negociação, relê
o contrato, o calendário, os participantes, a suspensão, as fontes e o histórico
económico, verificando o relógio após a espera. Qualquer alteração relevante
invalida a revisão. Só altera `definition_id` e `occurrence_id` do mercado.

O registo imutável `market_bet_associations` guarda autor, data, nota, destino,
plano e mercado antes/depois. Assinaturas opacas do histórico económico permitem
detetar uma oferta, correspondência ou revenda entretanto realizada, sem publicar
esses dados privados na auditoria. Pedidos repetidos da mesma revisão devolvem
o mesmo registo; a ligação não pode ser removida ou transferida.

## Contrato compatível

- Modalidade já explícita: `snapshot_value` ou `snapshot_delta_previous`.
- Mesmo campeonato, periodicidade, sprint, instante de fecho e categoria.
- Datas da ocorrência coerentes com o campeonato/sprint que lhe dá origem.
- Mesma referência anterior no delta; quando usa a política de entrada, mesmo
  início do período. O baseline não é reaproveitado para mudar o contrato.
- Num mercado ainda negociável, política de entrada 14 já adotada e universo
  de outcomes exatamente igual às participações efetivas (mínimo dois).
  Ausências devem ser reconciliadas pelo fluxo 15 quando esse fluxo o permite.
- Destino operacional aberto e sem fontes finais já congeladas.

Uma ligação compatível pode conservar ofertas, trades, revendas e posições já
existentes: não modifica outcomes, odds, colaterais, custos, carteiras, ledger,
scores, snapshots, classificações ou pagamentos. Isso distingue esta operação
da reconciliação 15, que pode corrigir o universo apenas em contratos intactos.

## Efeitos operacionais e geração

A pré-visualização avisa que associar a uma **bet suspensa suspende a negociação**.
Ofertas podem continuar a ser canceladas; posições e reservas mantêm-se. Ao
retomar, a geração reencontra o mesmo ID na posição definição × ocorrência × lugar,
sem criar um substituto. Entradas efetivas são sincronizadas pelas regras 14.

O mercado passa a aparecer no filtro da bet e da ocorrência. No corte, segue
a recolha final comum dessa ocorrência, com baselines congelados, declarações
coincidentes e penalização local pelas regras 13–14. Modalidades continuam a
produzir classificações distintas e podem ter vencedores diferentes. A associação
não captura, valida nem liquida por si só.

## Colisões e histórico

Se o destino já tem um mercado para o mesmo lugar, mesmo vazio, a associação
fica bloqueada. Não se apaga o gerado, não se escolhe um sobrevivente, não se
funde exposição nem se transforma uma colisão num mercado anulado. O mercado
legado conserva o ID e continua individual. Revisões concorrentes para a mesma
posição e a corrida com geração respeitam a unicidade existente.

Um mercado passado só pode ser organizado como arquivo quando já está liquidado
ou tem snapshot final no instante exato de fecho. Mantém a política histórica,
as fontes e os resultados. Um mercado passado aberto sem snapshot fica bloqueado:
não se criam obrigações/penalizações retroativas nem classificações com YTD atual.
Mesmo um arquivo ainda por apurar conserva esse estado; associação não certifica
a completude dos seus dados.

## Testes e limites

A guarda de instalação compara todos os dados contratuais, financeiros e de
competição, além do calendário e auditoria anterior, nos três percursos SQL.
Testes cobrem preparação sem geração/suspensão, seleções incompatíveis,
universos/referências ausentes, metadados exatos, preservação financeira,
arquivo sem novas recolhas, permissões e imutabilidade.

Sessões PostgreSQL reais concorrem em revisão duplicada, dois candidatos para
uma posição, matching, primeiro score, geração e passagem do corte. O fluxo
completo verifica recolha final dos mercados associados, as duas modalidades,
liquidação idempotente e empate bloqueado com posições/reservas preservadas.

**Empate/zero continua bloqueado**: sem void, devoluções, fusões ou tesouraria.
A #11 permanece aberta para colisões que exijam escolha/fusão de contratos e
legados incompatíveis/com exposição cuja transformação requeira decisão própria.
