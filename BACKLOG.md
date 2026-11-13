# BetCoins — Backlog de produto e entrega

Atualizado: 12-11-2026 · Estado: proposta de trabalho, não funcionalidades implementadas.

## Objetivo de entrega

Ter um jogo utilizável para o Campeonato 2026 (31-12-2026), com um ranking de investidores, sprints, participação aprovada por votação e um mercado P2P de posições negociáveis em BetCoins. Priorizar um ciclo completo e seguro antes de funcionalidades cosméticas.

**Prioridades:** P0 = indispensável para jogar; P1 = melhoria desejada para 2026; P2 = expansão posterior. **Estados:** a fazer / em curso / concluído, geridos nas issues.

## Épicos e entregáveis

### E0 — Regras e decisões (P0)
- Definir elegibilidade e papéis (conta com acesso, espectador, concorrente, administrador técnico).
- Admissão de concorrentes: quem vota, maioria sobre universo ou votos expressos, abstém-se, duração, empates, desistência.
- Regras de medição YTD, scores congelados, atualização tardia, desempate e aprovação da classificação final.
- Calendário e timezone dos sprints e do campeonato: semana, mês, snapshots e liquidação.
- Regras de mercados: outcomes mutuamente exclusivos, concorrentes elegíveis, retirada/desistência, fecho técnico no instante de referência.
- Regras monetárias: emissões iniciais, recarga semanal exclusiva de espectadores, precisão, reservas, taxas = 0, arredondamentos.
- Regras de avaliação/rentabilidade dos espectadores, especialmente posições sem preço e créditos periódicos.

### E1 — Fundação e acesso (P0)
- React + TypeScript + Vite; build/test/deploy GitHub Pages em `/betcoins/`.
- Supabase Auth: social login Google/GitHub; perfil e nickname.
- PostgreSQL, migrations versionadas, RLS deny-by-default, grants mínimos, gestão de segredos e ambientes.
- Bootstrap do campeonato 2026 e administrador técnico inicial.

### E2 — Campeonato e votação (P0)
- Candidatura e votação por concorrentes, contagem e decisão rastreáveis.
- Perfil de concorrente com atualização do YTD (%) e histórico.
- Ranking anual de investidores.
- Sprints semanais e mensais: janelas, snapshots de referência, ranking por retorno composto do período; ausência/correção de score.
- Validação e fecho oficial da classificação anual em 31/12/2026.

### E3 — BetCoins e carteira (P0)
- Carteira única por jogador; 1 000 BetCoins na adesão, só uma vez.
- Recarga semanal de 1 000 BetCoins apenas para espectadores elegíveis, idempotente e com recuperação de semanas perdidas.
- Ledger imutável, disponibilidades/reservas, reconciliação e sem saldos negativos.
- Histórico de créditos, ordens, negociações, transferências e liquidações.

### E4 — Mercados primários (P0)
- Mercados de 1.º, 2.º e último no anual e nos sprints; outcomes claros.
- Ofertas `back` e `lay` com odd, stake, responsabilidade, expiração e cancelamento do remanescente.
- Livro de ofertas, correspondência total/parcial, execução concorrente segura; proibir self-trading.
- Reservar integralmente ambas as responsabilidades na correspondência; definir política para ofertas ainda abertas.
- Liquidar após confirmação do resultado oficial; anulações e devoluções sem duplicação de pontos.

### E5 — Mercado secundário / saída 3-B (P0)
- Representar posições como direitos/obrigações transferíveis com colateral associado.
- V1: revenda integral de posição por preço em BetCoins, validade por mercado e cancelamento. Futuro: revenda parcial.
- Compra atómica transfere titularidade, risco e colateral; preserva contraparte original, ledger e histórico.
- Não há saída garantida nem preço de plataforma; distinguir posição posta à venda de posição vendida.
- Não permitir revenda após fecho, posições já comprometidas ou venda dupla; testar concorrência.

### E6 — Rankings dos espectadores (P0)
- V1: património contabilístico = saldo livre + colateral reservado. Futuro: valorização marcada a mercado, com estado de avaliação (cotado/sem liquidez).
- V1: valorização relativa contabilística = (património contabilístico − créditos recebidos) / créditos recebidos. Futuro: cálculo ponderado no tempo/fluxos e avaliação com preços de mercado.
- Classificação histórica e indicadores: créditos recebidos, P&L realizado, posições abertas, exposição e património.
- Não tratar apostas pendentes como lucro realizado.

### E7 — Experiência, operações e qualidade (P1)
- Dashboard da época e dos sprints, onboarding, páginas dos mercados, posições e histórico.
- Avisos de risco fictício, ausência de dinheiro real; acessibilidade móvel.
- Gestão de resultados, correção auditada, reabertura e reversão de liquidações com procedimento documentado.
- Testes E2E: acesso indevido, votação simultânea, duplicação de recargas, double spend, dupla venda, corrida entre venda e liquidação.
- Observabilidade, exportação/backups, plano de recuperação e limites free tier.

### E8 — Evolução (P2)
- Alertas, desafios personalizados, temporadas futuras, gráfico de preços e profundidade do livro de ofertas.
- Novos tipos de mercados e analytics; integração opcional com fontes de preços.

## Sequência de implementação sugerida

1. **M0 — Regras aprovadas e autenticação:** E0 + E1.
2. **M1 — Competição funcional:** candidaturas, votos, score YTD e ranking anual (E2).
3. **M2 — Economia interna:** wallet, ledger e créditos semanais (E3).
4. **M3 — Mercado completo:** ordens P2P, execução e liquidação (E4).
5. **M4 — Saída antecipada:** revenda/compra de posições (E5).
6. **M5 — Campeonato operacional:** sprints, dois rankings de espectadores e testes finais (E2/E6/E7).

Um marco só está completo com testes de autorização, invariantes económicas, documentação atualizada e operações repetíveis sem duplicação.

## Invariantes inegociáveis

- Nenhum cliente escreve diretamente saldos, ledger, resultados, votos alheios ou propriedade de posições.
- Emissões de BetCoins são exclusivamente operações autorizadas da plataforma; transferências e liquidações conservam o total em circulação.
- Reservas + saldo não podem tornar-se negativos; todas as movimentações são transacionais e idempotentes.
- Uma ordem não pode ser executada ou cancelada acima do seu remanescente; uma posição não pode ser vendida duas vezes.
- Fechos, decisões de votação e liquidações são auditáveis; relógio e autorização são validados no servidor.
- O GitHub Pages não contém chaves privilegiadas; RLS é obrigatória.

## Decisões ainda por validar com o grupo

1. Espectadores: qualquer utilizador autenticado pode apostar, incluindo concorrentes? O crédito semanal de 1 000 é apenas para quem **não** concorre, como definido.
2. Votação: maioria absoluta de todos os concorrentes elegíveis (proposta) ou maioria dos votos emitidos?
3. Data de atualização do YTD para apurar semanas/meses e tratamento de ausências.
4. Mercados anuais e sprints: elegibilidade, desempates, retiradas e aposta em si próprio.
5. Preço para venda secundária: mercado livre, sem garantia de execução; regras de divisão de posição e colateral.
6. Fórmula final de valorização relativa e marcação a mercado sem cotações.

A discussão destas regras é bem-vinda antes de codificar as respetivas operações.
