# Duas modalidades de aposta — regra #1

## Entrega

A migração 11 (`202611160002_snapshot_market_modes.sql`) está apenas versionada.
Requer 01–10 e **não foi aplicada ao Supabase remoto**. A publicação do frontend
não instala SQL. Os novos controlos precisam da instalação manual autorizada.

Cada novo mercado declara uma modalidade independente da periodicidade e do lugar
(1.º, 2.º, último):

| Modalidade | Valor de classificação | Unidade |
| --- | --- | --- |
| `snapshot_value` | YTD do snapshot de **fecho atual** | % |
| `snapshot_delta_previous` | YTD do fecho atual − YTD do **fecho do período anterior** | pp |

Exemplo: anterior 12,00%, atual 16,50% → valor 16,50%; diferença +4,50 pp.
A passa de 12 para 16,5; B de −5 para 2: A lidera pelo valor final, B pela diferença
(7 pp contra 4,5 pp). Não há capitalização. O snapshot inicial do próprio sprint
não substitui o fecho anterior, mesmo que exista e contenha outro valor.

## Referência anterior e calendário

Na criação da modalidade delta, o servidor identifica o predecessor registado
com o fecho mais recente que não ultrapasse o início do período atual:

- Semanal/mensal: sprint da **mesma periodicidade e campeonato**.
- Anual: campeonato anterior, cujo fecho não ultrapasse o início do atual.
- Nenhum candidato ou candidatos empatados no fecho: criação bloqueada, sem
  escolher arbitrariamente um deles. O calendário deve ser revisto pela gestão.

O mercado guarda os IDs e a data de fecho dessa referência. A interface apresenta
a referência antes da criação e a data fixada ao consultar o mercado. O critério,
período atual, lugar e referências não podem ser alterados depois da criação.
Registar outro período mais tarde não troca silenciosamente a referência de um
mercado existente. Não é gerado calendário nem inferida recorrência (#11).

O período anterior pode ainda aguardar captura quando o mercado é criado. O seu
snapshot de fecho auditável tem de existir antes da validação. Sem predecessor
registado (por exemplo, primeiro sprint), não se inventa baseline zero nem se
recorre a um snapshot de início. Esta entrega não cria temporadas históricas.

## Captura, revisão e validação

Usar as capturas auditadas E2 da migração 09. O fluxo E2 de captura de um sprint
continua a exigir o marcador inicial antes do fecho; os valores desse início
não são usados nestas duas modalidades. Cada fonte deve ter o instante de fecho
exato guardado no mercado. Datas divergentes bloqueiam o apuramento.

O painel de cada mercado mostra valores finais, valores anteriores quando
pertinentes, datas, unidade, classificação e ausências. A gestão revê os dados,
escreve uma nota e confirma **Validar classificação do mercado**. A validação
específica do mercado guarda linhas completas, IDs dos snapshots, modalidade,
responsável, nota e data, de forma imutável. A classificação de campeonato E2
(incluindo o delta start/end legado) permanece distinta.

Para valor absoluto basta o fecho atual. Para delta é obrigatório um valor
anterior e atual para cada concorrente. Zero declarado é válido; ausência é
ausência. Novos admitidos sem referência anterior não recebem 0 nem um score
atual retroativo. A validação bloqueia se faltar algum dado ou se os outcomes
não coincidirem com o universo atual congelado. Elegibilidade dinâmica continua
dependente de #11.

Depois da validação, atualizações correntes de YTD não alteram o resultado. A
consulta pública mostra o mesmo conjunto congelado usado pela liquidação.

## Liquidação, empates e compatibilidade

A liquidação regular usa apenas a classificação do mercado validada e o outcome
derivado desse critério. O mesmo endpoint financeiro preserva colaterais, P&L,
revendas anteriores, titular atual, auditoria e repetição idempotente. A resolução
liga-se à validação específica por `classification_id`; resoluções legadas
continuam ligadas à validação E2. Exatamente uma das referências deve existir.

Empates relevantes continuam **bloqueados**. Ranking partilhado 1,1,3 não cria
um segundo lugar. A validação pode congelar a classificação empatada, mas isso
não autoriza a liquidação. Não há tesouraria nova, void, devolução de colateral
ou seleção arbitrária de um empatado. A regra financeira do zero fica pendente.

Mercados anteriores à migração mantêm `mode = NULL`, critério e resultados
anteriores. A migração não reinterpreta apostas existentes nem associa mercados
antigos a períodos presumidos. O endpoint de criação anterior é preservado para
compatibilidade; a interface atual envia explicitamente a modalidade.

## Instalação e testes

Antes de instalação futura: backup e revisão; aplicar 09, 10 e 11 na ordem correta
sobre o esquema existente. Nunca reaplicar baseline nem executar fixtures numa
base real. A migração é transacional; nenhum comando aponta para Supabase remoto.

- Testes de apresentação: modalidade, unidade, datas, exemplo 12 → 16,5,
  ausências versus zero e distinção dos critérios legados.
- SQL nos três percursos de instalação: duas modalidades × três periodicidades
  × três lugares, vencedores divergentes, ausências, fonte incorreta, predecessor
  ambíguo, imutabilidade, permissões, auditoria e regressão dos mercados anteriores.
- PostgreSQL concorrente: validação e liquidação repetidas, pagamentos ao atual
  titular após revenda, preservação do P&L anterior, conservação de moeda e
  mercados empatados com colateral reservado sem pagamentos/devoluções.
