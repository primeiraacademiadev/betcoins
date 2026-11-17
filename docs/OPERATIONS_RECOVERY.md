# Operação e recuperação — #8

## Âmbito e estado

O ensaio automatizado usa exclusivamente PostgreSQL descartável em localhost. Não
exporta dados reais, não instala migrações no Supabase e não configura serviços ou
alertas remotos. A publicação do frontend não instala o esquema. A sequência de
instalação atual termina na migração 17; versões anteriores destas notas descrevem
entregas históricas, não um modo alternativo de funcionamento.

Continuam em vigor as duas modalidades explícitas, referências congeladas e
empate/zero bloqueado. Não existe compatibilidade legada a garantir. Dados de teste
incompatíveis podem ser removidos numa preparação autorizada; nunca se recriam
resultados históricos a partir de scores atuais.

## Ensaio verificável no CI

Depois de todas as migrações e dos testes concorrentes, `tests/db/recovery.py`:

1. Recusa hosts remotos, destinos arbitrários, serviços libpq e opções de ligação
   alternativas. Só aceita a origem local `betcoins` e cria `betcoins_recovery`.
   Se o destino existir, termina sem o substituir; não contém DROP DATABASE.
   Exige clientes pg_dump/pg_restore da mesma versão principal do servidor. O CI
   usa Ubuntu 24.04 com PostgreSQL 16, evitando exports de um cliente mais recente
   que introduzam parâmetros desconhecidos no servidor 16.
2. Exporta a base populada com `pg_dump` e restaura numa base nova com
   `pg_restore --exit-on-error --single-transaction`. Mantém grants, funções,
   políticas RLS, constraints, triggers e dados. Os papéis já existem no cluster CI.
3. Compara o esquema completo e a contagem/digest de todas as tabelas public/auth,
   incluindo ledger, titulares/custos, reservas, transações, declarações e resultados.
   A comparação normaliza apenas a chave aleatória de restrição do psql e o valor
   interno `pg_attver`, regenerado no restauro. Mantém as definições de colunas,
   permissões, políticas, funções e todos os dados na comparação; ver a
   [documentação PostgreSQL de attoptions](https://www.postgresql.org/docs/16/catalog-pg-attribute.html).
4. Reconcilia cada carteira com o ledger, conserva a moeda emitida e rejeita saldos
   negativos. Confirma isolamento de carteiras e recusa de escrita financeira.
5. Repete a aceitação do modelo recorrente na cópia, dentro de transações revertidas;
   confirma que a origem e a cópia mantêm os mesmos dados depois dos testes.

O arquivo temporário não é publicado como artefacto. O ensaio mede integridade e
funcionalidade da base PostgreSQL de teste. O stub Auth do CI não certifica OAuth,
sessões, Storage, segredos, DNS nem uma recuperação completa do serviço Supabase.

## Preparação pelo operador

Antes de começar a época, identificar um responsável e substituto, o projeto correto,
o plano contratado, o commit publicado e as migrações efetivamente instaladas.
Não deduzir o estado remoto a partir de um CI verde. Guardar este inventário num
local restrito, sem tokens nem passwords no repositório.

Definir e validar com o grupo uma perda máxima de dados e um prazo de recuperação.
Como ponto de partida operacional: exportação diária e antes de qualquer instalação
ou fecho financeiro; perda máxima pretendida de 24 horas e recuperação pretendida
em 4 horas. São objetivos propostos, não garantias demonstradas pelo CI.

Confirmar as opções disponíveis no [guia oficial de backups do Supabase](https://supabase.com/docs/guides/platform/backups).
O guia recomenda exportações próprias e cópias externas para o plano gratuito.
Uma exportação CSV isolada não preserva funções, permissões e relações. Uma cópia
da base também não substitui a cópia dos ficheiros de Storage nem o inventário das
configurações de autenticação e dos segredos necessários ao serviço.

Guardar cópias cifradas fora do projeto de origem, com acesso restrito ao operador
e substituto; verificar checksum, data, projeto e versão do esquema. Testar uma
cópia em ambiente isolado antes de a considerar recuperável. Definir retenção e
remoção das cópias com o grupo; dados pessoais não devem ser publicados no CI.
Este procedimento não foi executado remotamente nesta entrega.

## Incidente e reabertura

1. Registar o início, sintomas, último estado consistente e operações de resultado
   incerto. Não repetir créditos, compras ou liquidações até consultar o estado.
   Se a integridade estiver em causa, o operador deve suspender escritas pelo
   controlo de acesso do serviço. Retirar botões do frontend não bloqueia RPCs.
2. Preservar a base afetada e a auditoria. Escolher uma cópia identificada e
   restaurá-la primeiro num destino isolado. Nunca restaurar sobre a única cópia.
3. Comparar esquema/permissões, utilizadores e totais por tabela. Reconciliar
   todas as carteiras, moeda emitida, reservas, titularidade das posições e
   resultados congelados. Testar duas contas e confirmar que uma não lê a
   carteira da outra nem pode escrever diretamente no ledger.
4. Rever operações posteriores ao backup antes da reabertura. Restaurar uma base
   anterior pode perder negócios já confirmados. Não reemitir créditos nem
   reconstruir negociações por estimativa. Comunicar o intervalo afetado e
   resolver as diferenças com evidência e autorização do grupo.
5. Confirmar configuração OAuth, redirecionamentos, frontend e esquema compatíveis.
   Reabrir apenas depois de todas as verificações passarem; registar os tempos,
   diferenças e responsável. Um CI verde não autoriza esta operação remota.

Uma classificação ou liquidação errada não é automaticamente um incidente de
backup. Não há função de reversão/reabertura financeira no MVP. Preservar os
registos, impedir novas operações afetadas e preparar uma correção separada com
regras aprovadas. Não editar saldos, apagar ledger ou usar void para contornar
empate/zero. A recuperação não oferece uma reversão seletiva de negócios.

## Quotas e observação

O operador deve consultar o [painel de consumo e limites do plano](https://supabase.com/docs/guides/platform/manage-your-usage)
antes da abertura, diariamente durante utilização e antes de grandes fechos.
Registar utilização da base, tráfego de saída, armazenamento, utilizadores ativos,
erros da API, latência e falhas de autenticação; confirmar os limites no painel,
sem assumir valores fixos de um plano gratuito.

Adotar avisos operacionais a 80% e intervenção a 95% do limite aplicável. Confirmar
notificações do fornecedor e o destinatário responsável. Estes limiares são uma
política proposta de operação; não foram configurados alertas nem monitorização
automática nesta entrega. Se não houver alertas no plano, manter a verificação
manual e registar a data. Reduzir leituras repetidas, exportar antes de mudanças e
avaliar capacidade com o grupo; não eliminar auditoria para libertar espaço.

## Limites de aceitação

A #8 fica parcialmente concluída: o CI cobre o restauro da base e os casos críticos
de autorização/concorrência. Continuam por demonstrar um ensaio Supabase completo,
responsáveis e notificações de quota efetivamente configurados, OAuth no navegador
e o procedimento de correção/reversão aprovado. Não fechar a issue com base apenas
no ensaio PostgreSQL. Os testes de navegador existentes verificam componentes
reais e navegação responsiva com dados controlados, sem ligação Supabase.
