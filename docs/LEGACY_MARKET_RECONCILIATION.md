# #11 — reconciliação de mercados legados

Migração 15: `202611170001_legacy_market_reconciliation.sql`, dependente de 01–14.
**Apenas versionada. Nenhum SQL executado no Supabase remoto.** Publicar o frontend
não instala migrações. Testes SQL e sessões concorrentes usam apenas PostgreSQL
descartável em localhost, nos três percursos de instalação existentes.

## Decisão e âmbito

A migração 14 preservou outcomes antigos criados antes da primeira declaração.
Esta entrega permite rever o universo de mercados **ainda abertos, sem qualquer
histórico de negociação e sem apuramento congelado**, preservando toda a evidência.
Um administrador seleciona explicitamente o campeonato, o período e a modalidade.
O título, o YTD atual e o primeiro valor posterior ao fecho não determinam o contrato.

O período tem de coincidir exatamente com o tipo e o instante de fecho existentes.
Não se muda a pergunta, o corte, o título ou a categoria. Se a modalidade já está
definida, preservam-se essa modalidade, o campeonato, o sprint e o predecessor.
Uma modalidade ausente só é preenchida por decisão explícita num contrato intacto.
O delta mantém a regra de entrada do período em curso e de fecho anterior nos
seguintes; a ausência de referência continua a bloquear o apuramento.

## Rever e aplicar

Na Gestão, «Reconciliação de mercados legados» permite pré-visualizar cada mercado:

- Participantes com baseline auditado efetivo até ao instante da revisão e ao corte.
- Outcomes a retirar por ausência de entrada efetiva e outcomes a acrescentar.
- Motivo de bloqueio: histórico fechado, fontes congeladas, contratos existentes,
  período incompatível, mudança de modalidade, referência ambígua, bet suspensa
  ou menos de duas declarações iniciais.

`preview_legacy_market` não altera dados. `reconcile_legacy_market` exige a impressão
da pré-visualização e uma nota de 10–2000 caracteres. Reavalia tudo depois de obter
os mesmos locks de admissão, captura e negociação, incluindo o relógio real.
Uma nova entrada, alteração do mercado ou passagem do corte invalida a revisão.
Pedidos repetidos da mesma revisão devolvem o mesmo registo, sem reaplicar alterações.

Os outcomes elegíveis mantêm ID e label. Só num contrato intacto se retiram outcomes
prematuros, com cópia integral antes/depois no registo imutável
`market_reconciliations`. Não se apagam ofertas, trades, posições, listings ou fontes.
A migração não executa reconciliação automática nem altera linhas preexistentes.

## Contratos já negociados e histórico

**Qualquer oferta**, mesmo cancelada/preenchida, trade ou posição bloqueia a
transformação. Snapshots finais, classificações, resoluções e recolhas finais
associadas ao período também a bloqueiam. Não se reabre um mercado fechado,
não se remove um outcome contratado e não se infere um resultado histórico.

A negociação de um mercado sem modalidade explícita ou com outcomes sem entrada
efetiva sob a política 14 fica bloqueada no servidor: novas ofertas, aceitações,
listagens e compras secundárias passam pelo mesmo controlo. Cancelamentos continuam
disponíveis; validação e liquidação mantêm os seus critérios próprios. Não se
desfaz uma revenda nem se introduzem pagamentos, devoluções, void ou tesouraria.

Uma entrada real posterior pode resolver um outcome prematuro num mercado ainda
negociável, mantendo o contrato e a prova temporal. Sem essa entrada, mercados com
exposição ficam preservados e sinalizados para decisão própria; esta entrega não
autoriza conversão, exclusão de participantes contratados ou desbloqueio financeiro.
Mercados explícitos antigos com política anterior conservam essa política quando
há contratos; não se aplica retroativamente o baseline de entrada.

Mercados individuais permanecem individuais. Não se associam automaticamente
a definições/ocorrências recorrentes, não se fundem mercados nem se escolhe entre
contratos duplicados. Isso exigiria uma decisão sobre identidade e exposição.

## Evidência e limites

A guarda de migração compara exatamente mercados, outcomes, snapshots, scores,
baselines, membros finais, classificações, resoluções e todos os dados financeiros.
SQL verifica ambas as modalidades, seleção explícita, diferenças de participantes,
imutabilidade, nota, permissões, revisão desatualizada, ofertas canceladas,
quarentena e preservação de fontes congeladas.

Sessões reais concorrem em revisões duplicadas, primeira oferta, entrada inicial
e passagem do corte. Validam liquidação regular idempotente com vencedores
diferentes por modalidade, empate relevante bloqueado e conservação de moedas.

**A #11 permanece aberta** para contratos com exposição que requeiram uma decisão
financeira própria e eventual associação/fusão de legado. Empate/zero continua
bloqueado. Esta entrega não ativa a proposta antiga de anular e devolver colaterais.


## Seguimento: migração 16

A [associação revista às bets recorrentes](LEGACY_BET_ASSOCIATION.md) permite organizar mercados compatíveis com revisão e auditoria, alterando apenas a ligação. Atualiza o limite anterior sobre associação: colisões e fusões continuam bloqueadas. Migração apenas versionada, sem instalação remota.
