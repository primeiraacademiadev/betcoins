# #8 — experiência, testes adversariais e operação

Atualizado em 20/11/2026, após os PRs #42–#44 e a validação manual do operador.

| Critério | Evidência e limite |
| --- | --- |
| Dashboard, carteira, mercado, posições, histórico e resultados | Interface em `src/ui/App.tsx`; componentes de declarações, ocorrências, histórico e resultados. Fluxos financeiros no navegador cobertos no PR #43; autenticação real confirmada pelo operador após o PR #44 |
| RLS e autorização | `tests/db/smoke.sql`, `markets.sql`, `issue_11_acceptance.sql`; permissões e isolamento repetidos depois de restauro em `recovery_checks.sql` |
| Votação simultânea | `competition_concurrency.py`: voto único e decisão por eleitorado congelado |
| Recargas repetidas e concorrentes | `operations_concurrency.py`: quatro RPCs efetivamente bloqueadas em simultâneo; uma emissão semanal, espectador apenas, repetição sem novo ledger, reconciliação |
| Double spend, double sale e settlement | `markets_concurrency.py` e suites posteriores: sessões PostgreSQL reais, titularidade e conservação, corte pelo relógio do servidor |
| Duas modalidades, empate/zero | `issue_11_acceptance_concurrency.py`: geração real de seis definições, fechos coincidentes, validação/liquidação concorrente e empate bloqueado sem pagamentos |
| Experiência responsiva | `tests/browser/occurrences.spec.ts`: Chromium a 1280/390 px, navegação histórica, modalidades, lugares, indisponibilidade e regresso ao período atual; não é OAuth E2E |
| Fluxos financeiros no navegador | `financial.spec.ts`: aplicação completa + PostgREST/PostgreSQL reais no CI, BACK/LAY, cancelamento, revenda parcial, compra, validação/liquidação, P&L, resposta perdida, isolamento e empate bloqueado; duas modalidades e 1280/390 px. [Âmbito e limites](FINANCIAL_BROWSER_TESTS.md). Auth desta suite é identidade controlada; validação OAuth humana registada separadamente |
| OAuth e ciclo de sessão | [Ensaios reais e limites](OAUTH_VALIDATION.md): operador confirmou entrada/regresso, persistência após recarregar e saída seguida de recarregamento com GitHub e Google em 20/11/2026. Preflight real e regressões locais de limpeza de dados/respostas tardias são evidências distintas. Cancelamento no consentimento do fornecedor não é requisito adicional |
| Backup/restauro e recuperação | `recovery.py`: base populada, comparação de todos os dados public/auth e esquema, ACL/RLS, reconciliação e aceitação funcional na cópia. Não certifica Auth/Storage reais |
| Quotas e responsabilidade | [Confirmações pendentes](OPERATIONS_RECOVERY.md#confirmações-pendentes): plano/consumo, acompanhamento e canal de aviso; verificação manual é alternativa quando não há alertas disponíveis |
| Reversões | Fora do MVP por decisão do operador em 20/11/2026; não bloqueiam a #8. Não implementadas nem simuladas como suportadas. Preservar auditoria; não editar saldos/ledger nem contornar empate/zero |

## O que falta confirmar

Somente o mínimo operacional de backups e quotas: existência/data e localização
restrita de uma cópia recuperável da base, frequência das cópias, responsável pelo
acompanhamento, plano/consumo atuais e canal de aviso ou rotina de consulta manual.
Não foi confirmado no serviço remoto nesta revisão. O teste de restauro no CI
e as instruções de recuperação já existem; não provam que há uma cópia remota recente.

Um restauro integral do Supabase remoto, recuperação de Storage sem utilização
demonstrada, substituto obrigatório, objetivos fixos de recuperação e novos alertas
automáticos não são condições adicionais para aceitar o MVP da #8.

As suites históricas verificam a evolução das migrações. Não representam um
requisito de compatibilidade de produto. O fluxo atual exige bets recorrentes,
modalidade explícita e resultados congelados. Nenhuma migração remota é executada.

A #8 permanece aberta pelas confirmações operacionais indicadas; a #5 permanece bloqueada pelo
modelo financeiro de empate/zero. Evoluções opcionais da #9 não bloqueiam estes
trabalhos de operação.
