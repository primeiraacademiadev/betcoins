# Operação de campeonato e sprints — migração 09

## Estado de entrega

O código e o CI podem ser integrados sem aplicar SQL ao Supabase remoto. O deploy GitHub Pages publica apenas o frontend. **Não existe aplicação automática da migração 09.** Até à instalação manual, a interface apresenta o novo apuramento como indisponível e permite consultar os rankings antigos, sem certificar a sua proveniência.

## Instalação futura, por operador autorizado

Pré-requisito: esquema com migrações 01–08. Para instalação nova: migrações individuais 01–09, ou baseline `20261115_full_install.sql` seguido de `202611150004_position_settlement_pnl.sql` (08) e `202611150005_competition_validation.sql` (09). Para instalação 01–02: executar primeiro o upgrade 03–08 existente e depois 09. Não reaplicar baseline sobre uma instalação existente.

1. Fazer backup/exportação e testar a sequência num ambiente descartável com o mesmo esquema.
2. Rever `supabase/migrations/202611150005_competition_validation.sql` e executar **uma vez**, apenas quando a instalação for autorizada. A migração usa uma transação; em erro não prosseguir com uma instalação parcial. Não executar os fixtures de teste em produção.
3. Confirmar as três tabelas `competition_captures`, `competition_capture_scores`, `competition_validations` e a RPC `get_competition_review`. Recarregar o schema cache do PostgREST se necessário e atualizar a página.
4. Verificar que um admitido sem declaração mostra “aguarda primeiro YTD”, que a declaração de 0 continua válida e que um sprint antigo é apenas consultável.

A migração troca exclusivamente os zeros predefinidos sem `updated_at` por NULL, preserva scores declarados e históricos existentes e acrescenta proteção contra UPDATE/DELETE de declarações/snapshots. Não modifica wallets, ledger, trades, posições ou settlement. Consumidores próprios de `get_competitors` devem aceitar `ytd: null`.

## Fluxo administrativo

Em **Campeonato**, escolher o sprint. “Capturar referência inicial” fica disponível após o início e “Capturar fecho” após o fim, exigindo a captura inicial. O relógio e as permissões são verificados novamente no servidor. O botão de atualização permite consultar a disponibilidade quando um limite é atingido.

As capturas consultam as declarações históricas até à data de referência. Uma captura tardia não aceita uma declaração posterior como se fosse antiga. O snapshot mostra as datas de referência, declaração e execução; os dados ausentes ficam sem classificação.

Rever os valores, a atualidade das declarações, os empates e os motivos de ausência. Escrever uma nota (10–2000 caracteres), confirmar a revisão e selecionar **Validar classificação final**. A validação guarda o resultado completo e o responsável e não pode ser alterada pela aplicação. A repetição não duplica nem substitui esse registo.

O **Fecho anual** usa o mesmo fluxo, apenas com snapshot final e classificação pelo YTD absoluto. O fecho bloqueia novas declarações desse campeonato. A classificação final é independente de qualquer operação de apostas.

## Recuperação e limites

- Falha de rede: atualizar primeiro. Capturas/validações são idempotentes; não editar tabelas para forçar repetição.
- Ausência de declaração: mostrar como não classificado. Não introduzir 0, aplicar −1 pp nem reconstruir com o YTD atual. A validação pode confirmar um conjunto com ausências explícitas, mas nunca um conjunto sem dados classificáveis.
- Captura vazia: o marcador permanece imutável, mesmo que existam novas admissões depois.
- Histórico legado: consulta apenas. Não copiar valores antigos para as novas tabelas com proveniência inventada. Um processo de reconciliação excecional requer trabalho/revisão separados.
- Correção após captura/validação: não há reabertura ou retificação retroativa nesta entrega. Preservar a auditoria e discutir um procedimento próprio.
- Mercados: validar o campeonato não chama `settle_market`. As modalidades de snapshot da #1 e o empate/zero permanecem sem implementação financeira.

## Verificação automatizada

`npm test` e `npm run build`; no CI, `tests/db/competition.sql` nos três percursos de instalação e `tests/db/competition_concurrency.py` com sessões reais concorrentes. O teste Python recusa hosts diferentes de localhost/127.0.0.1. Nenhum teste aponta para Supabase remoto.


## Exports SQL gerados

Os caminhos históricos da baseline e upgrade 03–08 são produzidos por `python scripts/build_sql_bundles.py all`, a partir das migrações canónicas e templates. Os testes verificam que os bytes SQL são os mesmos dos exports congelados. Os exports deixam de ser cópias versionadas. O gerador não executa SQL; a instalação remota continua a exigir autorização separada. Ver [segurança e duplicação](SONAR_QUALITY.md).
