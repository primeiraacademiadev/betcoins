# BetCoins — Regras canónicas do Campeonato 2026

> Versão de decisão: 15-11-2026. Documento de produto da [issue #1](https://github.com/primeiraacademiadev/betcoins/issues/1).
> Distinguir **regra aprovada**, **comportamento atualmente implementado** e **decisão ainda por validar**. Isto não constitui, por si só, suporte técnico para liquidação de empates ou novos mercados.

## 1. Acesso, papéis e elegibilidade

- O login social Google/GitHub serve para **entrar ou criar conta**. Não equivale a entrar no campeonato. Qualquer utilizador autenticado começa com acesso à plataforma e identidade pública/nickname.
- Papéis: espectador, concorrente admitido e administrador técnico. Um concorrente pede admissão; o eleitorado é congelado na abertura da candidatura. Apenas concorrentes elegíveis votam; o candidato não vota em si.
- **Implementado:** aprovação por **maioria absoluta do eleitorado elegível** (> 50%); rejeição quando os votos negativos tornam matematicamente impossível atingir essa maioria; as abstenções não reduzem o denominador.
- Créditos iniciais por carteira: 1 000 ฿, uma só vez. Dotações semanais: 1 000 ฿ apenas para espetadores elegíveis, por semana UTC, idempotentes e recuperáveis, nunca anteriores ao registo.
- **A validar com os jogadores:** se concorrentes também podem apostar (não recebem dotação semanal) e se são permitidas apostas no próprio concorrente.

## 2. Calendário, declarações e snapshots

- Campeonato anual de 2026: fecho de referência **31-12-2026**; a data técnica de fecho e o instante da captura devem ser controlados pelo servidor.
- Sprints semanais e mensais; classificações e mercados dependem de snapshots YTD identificados e congelados.
- Os concorrentes podem atualizar os valores YTD durante o período. Os snapshots efetivamente recolhidos ficam imutáveis.
- **Duas modalidades de aposta distintas, aprovadas:**
  1. **Valor do snapshot:** previsão do **valor YTD absoluto no snapshot de fecho** do período atual.
  2. **Diferença entre snapshots:** previsão de **ΔYTD = YTD do snapshot de fecho atual − YTD do snapshot do período anterior** (em **pontos percentuais**, sem capitalização).
- A diferença não deve ser confundida com a rentabilidade composta entre valores YTD nem com a stake/odd da aposta.
- A modalidade escolhida é atributo do mercado, visível ao utilizador; o motor não deve adivinhar a modalidade.
- **Exemplo:** snapshot anterior 12,00% e snapshot do fecho atual 16,50%. No mercado «valor do snapshot», a referência é **16,50%**; no mercado «diferença entre snapshots», a referência é **+4,50 p.p.** Estes são resultados diferentes, não duas maneiras de apresentar o mesmo mercado.
- **Implementação preparada na migração 11:** mercados com modalidade explícita `snapshot_value` ou `snapshot_delta_previous`, fontes de fecho identificadas e classificação validada própria. O delta start/end do próprio sprint permanece apenas nos mercados/classificações legados. A migração 11 não foi aplicada ao Supabase remoto; ver [modalidades e operação](SNAPSHOT_MARKET_MODES.md).
- **A validar com o grupo:** horário semanal de referência e fuso horário, ausência de atualização e regras não abrangidas pelo fluxo de fecho; a migração 13 prepara a omissão final com último valor conhecido e penalização local de **1 p.p.** (instalação remota pendente); inscrições a meio do período, correções/tardios, retiradas.

## 3. Outcomes, mercados P2P e empate

- Mercados têm outcomes explícitos, mutuamente exclusivos na resolução regular, e fecham na hora do servidor.
- Uma oferta BACK representa posição a favor de um outcome; LAY é o lado contrário. Uma odd decimal 1,20 e stake BACK 10 ฿ implicam responsabilidade LAY 2 ฿; colateral total 12 ฿; sem taxas no MVP.
- A aceitação P2P pode ser parcial dentro dos limites da oferta. A revenda de posições preserva colateral, risco, custo de aquisição e contabilidade; só há saída quando existe comprador.
- **Regra de empate revista pelo operador em 20/11/2026:** devolução integral do colateral aos titulares atuais: stake BACK e responsabilidade LAY. Substitui a anterior regra de perdas de ambos os lados. Não está implementada; empate/zero continua bloqueado.
- **Exemplo confirmado:** stake 10 ฿, odd 1,20: BACK recebe 10, LAY recebe 2 e tesouraria recebe 0. Se BACK tiver sido vendido por 7, o comprador recebe os 10 de colateral e realiza +3; o vendedor mantém −3. Revendas não são desfeitas.
- **Lacuna técnica bloqueante:** o settlement P2P atual é binário BACK/LAY: escolhe um `winner_outcome_id` e atribui a soma dos colaterais a um dos lados; a totalidade de BetCoins em circulação é conservada. Não existe ainda resolução por empate com devolução integral. A decisão revista não exige tesouraria. **Não utilizar `settle_market` para fingir que esta regra já está suportada.**
- **Próxima revisão:** âmbito do empate relevante no mercado inteiro e implementação futura da devolução ao titular atual, com P&L pelo custo de aquisição. Sem emissão, queima ou tesouraria. Ver [tratamento financeiro](TIE_ZERO_PROPOSAL.md). Só implementar após autorização e testes; sem migrações remotas nesta revisão.
- **Distinguir de anulação:** `void` por falha técnica, retirada/desistência ou resultado não validável é um mecanismo diferente de **empate desportivo/competitivo**. A decisão revista devolve colateral por empate sem desfazer revendas. Políticas para falhas técnicas/retiradas não são decididas por essa regra.

## 4. Liquidação, transparência e rankings

- O resultado oficial é validado pela gestão após fechar o mercado; liquidação transacional, idempotente e auditável, nunca antes do fecho.
- Para a liquidação regular, o P&L do último titular é **pagamento final − custo de aquisição**; o P&L de revendas anteriores permanece realizado e separado.
- Património contabilístico dos espetadores = disponível + reservado. Não é uma avaliação *mark-to-market* nem se deve chamar lucro a créditos atribuídos.
- Ranking relativo contabilístico existente: (património contabilístico − créditos recebidos) / créditos recebidos; uma métrica de retorno económico robusta com fluxos externos e preços de referência fica para evolução posterior.
- Os valores YTD são **declarados pelos concorrentes**, não verificados automaticamente por corretora; a UI deve indicar esta limitação.

## 5. Matriz de decisões e implementação

| Tema | Regra/decisão | Estado de implementação |
| --- | --- | --- |
| Login versus candidatura | Jornadas separadas | Implementado |
| Votação por maioria absoluta | Eleitorado congelado | Implementado |
| Duas modalidades: snapshot absoluto e Δ do anterior | Aprovadas como regra de produto | Implementadas no código/migração 11, com validação e liquidação regular; instalação remota pendente. Geração recorrente continua na #11 |
| ΔYTD aritmético do sprint | Diferença de snapshots em p.p. | Implementado para start/end do mesmo sprint |
| Empate — decisão revista | Devolver stake BACK e responsabilidade LAY ao titular atual, sem desfazer revendas | **Por implementar**: bloqueado; tesouraria recebe zero |
| Revenda parcial por lotes | Proporções e cêntimos exatos | Implementado |
| Créditos iniciais e semanais | 1 000 ฿, com elegibilidade | Implementado |
| Captura automática, ausência, penalização, timezone | Validar regras | Pendente |
| Retiradas, void, reversão auditada | Definir procedimento | Pendente |
| Preço de referência / mark-to-market | Não inventar liquidez | Não implementado; assumido como limitação |

## 6. Critérios para próximos tickets

1. Tipos explícitos `snapshot_value` e `snapshot_delta_previous` preparados na migração 11, com fontes por período e testes 12,00% → 16,50%. Instalação remota e geração recorrente são etapas separadas.
2. Preparar, após revisão/autorização, devolução integral de colateral por **empate/zero** ao titular atual. Não criar tesouraria nem desfazer revendas; manter bloqueado até implementar/testar.
3. Validar com os jogadores as regras ainda pendentes e atualizar a UI/termos do campeonato quando forem acordadas.

**Este documento fecha o trabalho de inventariar e fixar as regras conhecidas da E0, mas não representa aprovação das decisões identificadas como pendentes nem implementação das lacunas técnicas.**

## 7. Estado técnico E2 — sem alterar as decisões E0

A migração 09 acrescenta apuramento auditado e validação administrativa persistida para anual/sprints: origem temporal das declarações, ausências explícitas sem classificação, empates partilhados e resultados imutáveis. Não foi aplicada ao Supabase remoto nesta entrega. Ver [matriz de aceitação da #3](ISSUE_3_ACCEPTANCE.md) e [operação](COMPETITION_OPERATIONS.md).

Capturar a última declaração auditada até ao limite não aprova penalizações nem declarações tardias. O delta da classificação E2 do sprint continua a usar start/end. A migração 11 acrescenta classificações próprias por modalidade aos novos mercados e liquidação regular auditada; o empate/zero continua sem suporte financeiro e bloqueado. Validar uma classificação não executa automaticamente a liquidação.

## 8. Declarações finais e omissões — migração 13

A autorização de implementar as declarações finais e penalizações da #11 acrescenta recolha administrativa após o corte, uma declaração por fechos coincidentes e bloqueio das atualizações correntes enquanto houver obrigações pendentes. O prazo é escolhido pela gestão. Uma omissão com YTD conhecido aplica −1 pp apenas ao score efetivo do fecho, mantendo o original e a origem. O delta do período seguinte usa o original anterior, sem propagar penalizações. Ver [fluxo, instalação e limites](FINAL_DECLARATIONS.md). As duas modalidades, históricos imutáveis e bloqueio de empate/zero são preservados. Migração apenas versionada; Supabase remoto não migrado.

## 9. Participação efetiva e entrada a meio do período — migração 14

A autorização para implementar o baseline inicial da #11 separa admissão e participação efetiva, que começa na primeira declaração YTD auditada por campeonato. Esse valor é imutável. Nos períodos em curso à entrada, o delta usa o YTD inicial e mostra a janela parcial; nos seguintes, usa o original do fecho anterior. O valor absoluto mantém o critério de fecho. Não há zeros por omissão, retroatividade, propagação de penalizações ou implementação de empate/zero. Ver [regras, testes e limites](ENTRY_BASELINES.md). Migração apenas versionada; Supabase remoto não migrado.


## Âmbito atualizado da #11 — 17/11/2026

Não existe obrigação de compatibilidade ou reconciliação de legado; dados exclusivamente de teste não conformes podem ser removidos numa operação identificada. A aceitação incide no modelo recorrente atual e nas duas modalidades, com [matriz e testes](ISSUE_11_ACCEPTANCE.md). Os resultados finais por ocorrência são persistidos pela migração 17; histórico e rankings não usam YTD corrente como substituto de fontes ausentes. Empate/zero permanece bloqueado, sem anulação/devolução automática. Supabase remoto não migrado.

## 10. Estado e proposta da #5 — 20/11/2026

As modalidades, geração recorrente, declarações/penalizações e entrada efetiva
descritas nas secções históricas anteriores foram entregues; a #11 está encerrada.
Não existe requisito de compatibilidade legada. A [matriz atual da #5](ISSUE_5_ACCEPTANCE.md)
substitui listas antigas de pendências dessas entregas.

A regra revista pelo operador devolve integralmente o colateral ao titular atual:
stake BACK e responsabilidade LAY; tesouraria recebe zero. Revendas não são desfeitas.
O [tratamento financeiro BACK/LAY](TIE_ZERO_PROPOSAL.md) substitui a proposta rejeitada
de perdas e tesouraria. O âmbito de mercado inteiro continua como proposta a rever.
O motor continua **bloqueado**, sem implementar devoluções por esta revisão.

Reversões e reabertura financeira ficam fora do MVP por decisão do operador.
A #8 foi encerrada; backups e quotas ficaram adiados, sem os dar como confirmados.
Duas modalidades e empate/zero bloqueado mantidos. Esta revisão não executa
migrações no Supabase remoto nem confirma o estado de instalação remota.
