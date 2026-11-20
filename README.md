# 🪙 BetCoins — Campeonato de Investidores & Mercado de Previsões

**Um campeonato de carteiras, duas formas de ganhar.** Os concorrentes disputam a maior valorização percentual da carteira; os espectadores usam **BetCoins**, uma moeda 100% fictícia, para negociar previsões sobre a classificação.

> 🎲 É um jogo entre amigos, sem dinheiro real, sem conversão ou resgate de BetCoins e sem prémios monetários previstos nesta versão. Os desempenhos das carteiras são declarados pelos próprios concorrentes, não verificados por integração com corretoras.

## Entrar ou criar conta

Na plataforma, **Continuar com Google** ou **Continuar com GitHub** permite entrar numa conta existente ou criar uma nova automaticamente. A candidatura ao campeonato é uma etapa posterior, separada da autenticação.

## Campeonato 2026

- **Fim do campeonato anual:** 31 de dezembro de 2026. A classificação final considera a valorização YTD (%) da carteira nessa data, sujeita a validação posterior.
- **Concorrentes:** candidatam-se e são admitidos por maioria absoluta do eleitorado elegível, congelado na abertura da votação. O empate entre resultados de um mercado é uma regra diferente da votação.
- **Scores:** cada concorrente atualiza o seu YTD; guardamos histórico e data de cada atualização. O ranking anual é pela maior valorização percentual.
- **Sprints semanais e mensais:** usam snapshots YTD congelados. Foram definidas **duas modalidades de mercado**: (1) valor absoluto do snapshot de fecho; (2) diferença em pontos percentuais entre o snapshot do período anterior e o do fecho atual. Ambas estão preparadas na migração 11, com critério explícito, snapshots de fecho identificados e validação própria por mercado; instalação remota pendente.

## BetCoins e mercados

- Todos os participantes com acesso elegível começam com **1 000 BetCoins**.
- Os **espectadores recebem mais 1 000 BetCoins por semana**, creditados uma única vez por semana.
- Mercados para prever **1.º, 2.º e último lugar**, tanto no campeonato anual como, quando aplicável, nos sprints.
- **Mercado P2P:** as pessoas publicam ofertas com odds e valores; outras aceitam. A plataforma não banca apostas e não cria dinheiro nas liquidações. **Empate como zero na roleta:** apostas em ambos os lados perdem; esta regra exige um modelo de tesouraria e ainda **não está implementada no settlement**, pelo que não se devem liquidar empates pela função binária atual.
- **Saída antecipada por revenda da posição (mercado secundário)**: o titular oferece a posição (ou parte dela) a outro participante. Só há saída quando alguém a compra; o risco, os direitos económicos e as reservas correspondentes são transferidos atomicamente.
- **Mercados em funcionamento durante o campeonato**, até ao instante de corte definido para cada mercado; não impomos fecho antecipado só porque o resultado parece previsível.
- Ordens podem ficar sem contraparte; não há preço nem liquidez garantidos. A exposição máxima deve estar sempre coberta por BetCoins reservados.

### Dois rankings de espectadores

1. **Maior património contabilístico em BetCoins (V1):** saldo disponível + colateral reservado. A marcação a mercado das posições exige liquidez e fica para uma evolução.
2. **Maior valorização relativa (V1):** (saldo disponível + reservado − créditos recebidos) / créditos recebidos. É uma rentabilidade contabilística simples, não uma valorização de mercado nem um retorno ponderado pelo tempo.

As duas classificações dos espectadores são independentes do ranking de valorização das carteiras.

## Como jogar (exemplo)

A Ana é candidata a ganhar o campeonato. Um jogador aceita uma exposição a odds 1,20 com stake de 10 BetCoins. Se acertar, recebe 12 (lucro líquido de 2); se falhar, perde 10. A contraparte fica do lado oposto, com responsabilidade de 2 BetCoins. Ambos os lados são reservados no momento da correspondência. Antes da liquidação, qualquer titular pode **colocar os seus direitos/obrigações à venda**; a transferência só se concretiza quando outro jogador aceita o preço. Exemplos ilustrativos.

## Produto e tecnologia previstos

Aplicação web pública em **GitHub Pages** (React, TypeScript, Vite), autenticação social (Supabase Auth) e dados em PostgreSQL (Supabase). Operações sensíveis em funções transacionais, RLS, ledger auditável e verificação de limites pelo relógio do servidor. Prevê-se utilização dos planos gratuitos, sujeita aos respetivos limites.

## Estado e participação

**Estado: MVP integrado na `main`, publicado em GitHub Pages e ligado ao Supabase; existem regras de produto por implementar.** O [backlog](BACKLOG.md), as [regras do Campeonato 2026](docs/CHAMPIONSHIP_RULES_2026.md) e as [issues](https://github.com/primeiraacademiadev/betcoins/issues) distinguem o que está aprovado, implementado e pendente. Comentários e sugestões são bem-vindos através das [issues](https://github.com/primeiraacademiadev/betcoins/issues).

O apuramento auditado e a validação final E2 estão preparados na **migração 09, ainda não aplicada ao Supabase remoto nesta entrega**. Até à instalação, a interface mantém consulta dos dados antigos e indica a indisponibilidade dos novos controlos. [Critérios e testes](docs/ISSUE_3_ACCEPTANCE.md) · [Instalação e operação](docs/COMPETITION_OPERATIONS.md).

**Princípio:** é para brincar; as regras devem ser claras, o dinheiro é fictício e ninguém deve conseguir criar BetCoins ou alterar uma aposta através das ferramentas do browser.

A liquidação P2P vinculada à classificação validada está preparada na **migração 10, apenas versionada**, dependente da 09. Bloqueia empates, dados incompletos e mercados sem período associado. A #5 continua aberta para as lacunas de produto/finanças. [Critérios, instalação e limites](docs/ISSUE_5_ACCEPTANCE.md).

As [duas modalidades da regra #1](docs/SNAPSHOT_MARKET_MODES.md) estão preparadas na **migração 11, apenas versionada**, dependente de 01–10. Empate/zero continua bloqueado; mercados anteriores mantêm os critérios legados.

As [bets recorrentes e o calendário 2026](docs/RECURRING_BETS.md) estão preparados na **migração 12, apenas versionada**, dependente de 01–11: geração idempotente, duas modalidades, atualização de concorrentes nos mercados negociáveis e navegação por ocorrências. Empate/zero continua bloqueado. A #11 permanece aberta para os critérios operacionais ainda não implementados.

As [declarações finais obrigatórias e penalizações locais](docs/FINAL_DECLARATIONS.md) estão preparadas na **migração 13, apenas versionada**, dependente de 01–12: fechos coincidentes partilham declaração, a gestão determina o prazo e omissões com YTD conhecido recebem −1 pp apenas no fecho atual. O valor original fica preservado para não acumular penalizações nas referências seguintes. Empate/zero mantém-se bloqueado.

O [YTD inicial e as entradas a meio do período](docs/ENTRY_BASELINES.md) estão preparados na **migração 14, apenas versionada**, dependente de 01–13. A participação começa no primeiro YTD; a referência inicial é imutável, os períodos seguintes voltam ao fecho anterior e os históricos/pagamentos existentes são preservados. Empate/zero continua bloqueado.

Reconciliação de legado: [pré-visualização, auditoria e preservação de contratos](docs/LEGACY_MARKET_RECONCILIATION.md), migração 15 apenas versionada, dependente de 01–14.

Associação de legado: [preparação suspensa, revisão de compatibilidade e ligação auditada às bets](docs/LEGACY_BET_ASSOCIATION.md), migração 16 apenas versionada, dependente de 01–15.

#11: [matriz de aceitação do modelo atual e evidência dos 30 critérios](docs/ISSUE_11_ACCEPTANCE.md). Migração 17 de estatísticas/histórico apenas versionada, sem Supabase remoto. Compatibilidade legada não exigida.

Qualidade: [instalação de dependências com lock, exports SQL gerados e âmbito do Sonar](docs/SONAR_QUALITY.md). Gerar exports não aplica migrações.

Operação #8: [matriz de aceitação](docs/ISSUE_8_ACCEPTANCE.md) e [backup, recuperação e quotas](docs/OPERATIONS_RECOVERY.md). O CI ensaia restauro numa base local descartável; falta confirmar uma cópia recente da base real, frequência/responsável e acompanhamento de quotas/avisos. Não é exigido restauro integral do Supabase remoto. Reversões financeiras ficam fora do MVP por decisão de 20/11/2026. Duas modalidades e empate/zero bloqueado mantidos; sem migrações remotas nesta revisão.

Testes #8: [fluxos financeiros no navegador](docs/FINANCIAL_BROWSER_TESTS.md), com a aplicação completa, PostgREST/PostgreSQL locais, duas modalidades e larguras desktop/telemóvel. Identidades de teste controladas; operações financeiras reais, sem migrações no Supabase remoto.

OAuth #8: [redirecionamentos reais, ensaio assistido e limpeza da sessão](docs/OAUTH_VALIDATION.md). O operador confirmou entrada/regresso, persistência após recarregar e saída seguida de recarregamento com GitHub e Google em 20/11/2026. Esta validação manual é distinta do preflight e das regressões com identidade controlada. Cancelamento no consentimento do fornecedor não é requisito adicional.
