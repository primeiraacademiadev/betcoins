# 🪙 BetCoins — Campeonato de Investidores & Mercado de Previsões

**Um campeonato de carteiras, duas formas de ganhar.** Os concorrentes disputam a maior valorização percentual da carteira; os espectadores usam **BetCoins**, uma moeda 100% fictícia, para negociar previsões sobre a classificação.

> 🎲 É um jogo entre amigos, sem dinheiro real, sem conversão ou resgate de BetCoins e sem prémios monetários previstos nesta versão. Os desempenhos das carteiras são declarados pelos próprios concorrentes, não verificados por integração com corretoras.

## Campeonato 2026

- **Fim do campeonato anual:** 31 de dezembro de 2026. A classificação final considera a valorização YTD (%) da carteira nessa data, sujeita a validação posterior.
- **Concorrentes:** candidatam-se e são admitidos por votação dos concorrentes existentes; vence a maioria. O universo de eleitores, os prazos e os empates serão fixados nas regras.
- **Scores:** cada concorrente atualiza o seu YTD; guardamos histórico e data de cada atualização. O ranking anual é pela maior valorização percentual.
- **Sprints semanais e mensais:** classificações por performance do período, calculada a partir dos valores YTD de referência. Os snapshots nos limites dos períodos terão regras específicas.

## BetCoins e mercados

- Todos os participantes com acesso elegível começam com **1 000 BetCoins**.
- Os **espectadores recebem mais 1 000 BetCoins por semana**, creditados uma única vez por semana.
- Mercados para prever **1.º, 2.º e último lugar**, tanto no campeonato anual como, quando aplicável, nos sprints.
- **Mercado P2P:** as pessoas publicam ofertas com odds e valores; outras aceitam. A plataforma não banca apostas e não cria dinheiro nas liquidações.
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

**Estado: MVP implementado em branch de desenvolvimento, ainda não publicado nem ligado ao Supabase.** Veja a [PR #10](https://github.com/primeiraacademiadev/betcoins/pull/10). O [backlog](BACKLOG.md) mostra as entregas propostas, as decisões em aberto e os critérios de aceitação. Comentários e sugestões são bem-vindos através das [issues](https://github.com/primeiraacademiadev/betcoins/issues).

**Princípio:** é para brincar; as regras devem ser claras, o dinheiro é fictício e ninguém deve conseguir criar BetCoins ou alterar uma aposta através das ferramentas do browser.
