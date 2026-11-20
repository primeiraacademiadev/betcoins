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

## Mínimo operacional do MVP

Esta revisão documental de 20/11/2026 não consulta o painel remoto, não exporta
dados reais nem configura alertas. Define o mínimo a confirmar, sem o dar por feito.

Para backups, identificar uma cópia recente da base (dados e esquema/permissões),
a sua data, localização fora do projeto de origem e frequência de atualização.
Guardar dados e credenciais em local restrito, fora do repositório. O restauro
automatizado no CI já verifica o procedimento técnico; não substitui essa cópia.
Uma pasta de configurações ou credenciais não demonstra um backup da base.

Para quotas, identificar quem acompanha o consumo, o plano e limites aplicáveis,
e o canal de aviso disponível. Quando o plano não oferecer alertas, basta uma
rotina de consulta manual com frequência e data da última verificação registadas.
Não é necessário desenvolver monitorização automática para fechar a #8.

## Recomendações de operação

As recomendações seguintes ajudam a operar o serviço. Substituto, objetivos de
24 horas/4 horas e limiares de 80%/95% não são requisitos adicionais do MVP.

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
backup. Reversões e reabertura financeira ficam fora do MVP por decisão do operador
em 20/11/2026 e não bloqueiam a #8. Não existe essa função. Preservar os
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

## Confirmações pendentes

| Ponto | Estado em 20/11/2026 | Confirmação mínima |
| --- | --- | --- |
| Cópia da base real | Não confirmada; o arquivo temporário do CI é de teste | Data da última cópia, projeto a que pertence e localização restrita fora da origem; confirmar que inclui dados e esquema/permissões |
| Frequência das cópias | Não confirmada | Registar quando são feitas e quem as acompanha |
| Plano e consumo | Não consultados nesta revisão | Confirmar plano/limites e leitura atual de base, tráfego e utilizadores ativos; Storage apenas se utilizado |
| Responsável e avisos | Não confirmados | Identificar responsável e canal dos avisos disponíveis; em alternativa, frequência da consulta manual e data da última leitura |

Não publicar ficheiros de backup, credenciais ou dados pessoais para demonstrar
estas confirmações; basta registar o estado e manter a evidência em local restrito.
Nesta revisão não foi demonstrado um backup recente nem a configuração de avisos.

## Aceitação da #8

Estão concluídos os testes críticos de autorização/concorrência, fluxos financeiros
no navegador com PostgREST/PostgreSQL reais no CI, experiência responsiva e ensaio
de restauro da base. O operador confirmou manualmente entrada, persistência e saída
com GitHub e Google em 20/11/2026; ver [evidência e limites](OAUTH_VALIDATION.md).

A #8 mantém-se aberta apenas pelas confirmações operacionais mínimas acima.
O ensaio de restauro não certifica uma recuperação integral do serviço Supabase;
essa limitação não cria uma obrigação de restaurar o ambiente remoto. Não é exigido
um ensaio de Storage sem utilização demonstrada, nem reversões ou cancelamento
no consentimento dos fornecedores. Duas modalidades e empate/zero bloqueado mantidos.
Nenhuma migração remota é executada por esta revisão documental.
