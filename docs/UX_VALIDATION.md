# BetCoins · Catálogo e validação contextual (#13)

## Contrato de apresentação
Cada erro acionável tem código estável (`UXErrorCode`), título, explicação e ação corretiva. Quando é um campo, associa `field`. O código de origem PostgreSQL/PostgREST nunca é mostrado ao jogador. Os toasts globais tratam erros de operação; erros dos campos são anunciados junto ao respetivo input (`aria-invalid`, `role="alert"`).

A classificação parte do `code` estruturado quando disponível (por exemplo 42501 para permissão, 23505 para conflito, 23514 para restrição), podendo interpretar mensagens antigas da RPC apenas internamente. Desconhecidos usam `UNKNOWN`; não exibimos consultas SQL, nomes de tabelas ou segredos. Em falhas de rede, `NETWORK_UNCERTAIN` informa que o resultado é desconhecido e recomenda verificar o estado antes de repetir.

## Inventário de operações
| Área | Ações | Validação anterior à RPC | Erro/ação contextual |
| --- | --- | --- | --- |
| Campeonato | Atualizar YTD | Número finito ≥ −100 | `INVALID_YTD`, corrigir valor |
| Admissões | Candidatura e votos | Perfil/nickname; aprovação pendente | `APPLICATION_DECIDED`, atualizar lista; `NOT_AUTHORIZED` |
| Mercados | Publicar BACK/LAY | Odd > 1, ≤ 1000, duas casas; stake inteira > 0; outcome; saldo/reserva; estado do mercado | `ODD_TOO_LOW`, `ODD_PRECISION`, `STAKE_INVALID`, `BALANCE_INSUFFICIENT`, `MARKET_CLOSED` |
| Mercados | Aceitar total/parcial | Quantidade inteira dentro da oferta; capital disponível; mercado aberto; confirmados cenários económicos | `OFFER_UNAVAILABLE`, atualizar livro; `BALANCE_INSUFFICIENT` |
| Carteira | Revender lotes | Lote mínimo, preço positivo e centesimal | `INVALID_LOT`, `INVALID_PRICE`, `POSITION_UNAVAILABLE` |
| Carteira | Comprar revenda | Sessão e anúncio disponível; confirmação de preço/payoff | `POSITION_UNAVAILABLE` ou `BALANCE_INSUFFICIENT` |
| Conta | Alterar nickname | 2–40 caracteres | `INVALID_NICKNAME` |
| Gestão | Criar sprint | Nome, datas válidas e início anterior ao fim | `INVALID_DATE` |
| Gestão | Criar mercado | Título, fecho futuro, pelo menos dois concorrentes | `INVALID_SELECTION`, `INVALID_DATE` |
| Gestão | Snapshots, grants, liquidação | Estado e prazo do servidor | `MARKET_CLOSED`, `NOT_AUTHORIZED`, `DUPLICATE_ACTION` |

## Aceitação P2P: duas perspetivas
A **stake é sempre do lado BACK**. Se a odd for 1,20 e a stake BACK for 10 ฿, a responsabilidade LAY é 2 ฿; pagamento total para o vencedor é 12 ฿.

- Autor oferece BACK, aceitante assume LAY: reserva 2 ฿, ganha 10 ฿ líquidos se o resultado **não** ocorrer e perde 2 ฿ se ocorrer.
- Autor oferece LAY, aceitante assume BACK: reserva 10 ฿, ganha 2 ฿ líquidos se o resultado ocorrer e perde 10 ฿ se não ocorrer.
- Se aceitar 5 ฿ de stake numa oferta BACK a 1,20, assume LAY com reserva 1 ฿, lucro possível 5 ฿ e pagamento total 6 ฿.

Os cenários visíveis e a confirmação são recalculados pela quantidade escolhida, não pela stake máxima do livro. O saldo pós-reserva é uma **estimativa** antes da confirmação da RPC, nunca uma promessa de execução.

## Validação manual recomendada
Verificar em desktop e telemóvel: odd 1,00 com texto junto ao input e botão inativo; odd 1,20 e stake 10; aceitação parcial BACK/LAY; saldo insuficiente; oferta preenchida entre leitura e aceitação; rede interrompida depois de enviar uma operação; candidatura decidida; nickname inválido; sprint com fim anterior ao início; leitura do toast sem scroll e navegação por teclado.

Os testes unitários em `uxErrors.test.ts` e `domain.test.ts` cobrem o catálogo, privacidade, valores de odds/stakes, e a economia da aceitação. Os testes automáticos de Chromium em `tests/browser/occurrences.spec.ts` cobrem navegação histórica e apresentação responsiva a 1280/390 px com componentes reais e dados controlados. OAuth e operações financeiras completas no navegador ainda exigem validação integrada; ver a [matriz #8](ISSUE_8_ACCEPTANCE.md).
