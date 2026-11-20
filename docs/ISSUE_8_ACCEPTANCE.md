# #8 — experiência, testes adversariais e operação

| Critério | Evidência e limite |
| --- | --- |
| Dashboard, carteira, mercado, posições, histórico e resultados | Interface em `src/ui/App.tsx`; componentes de declarações, ocorrências, histórico e resultados. Fluxos de autenticação reais ainda exigem ensaio integrado |
| RLS e autorização | `tests/db/smoke.sql`, `markets.sql`, `issue_11_acceptance.sql`; permissões e isolamento repetidos depois de restauro em `recovery_checks.sql` |
| Votação simultânea | `competition_concurrency.py`: voto único e decisão por eleitorado congelado |
| Recargas repetidas e concorrentes | `operations_concurrency.py`: quatro RPCs efetivamente bloqueadas em simultâneo; uma emissão semanal, espectador apenas, repetição sem novo ledger, reconciliação |
| Double spend, double sale e settlement | `markets_concurrency.py` e suites posteriores: sessões PostgreSQL reais, titularidade e conservação, corte pelo relógio do servidor |
| Duas modalidades, empate/zero | `issue_11_acceptance_concurrency.py`: geração real de seis definições, fechos coincidentes, validação/liquidação concorrente e empate bloqueado sem pagamentos |
| Experiência responsiva | `tests/browser/occurrences.spec.ts`: Chromium a 1280/390 px, navegação histórica, modalidades, lugares, indisponibilidade e regresso ao período atual; não é OAuth E2E |
| Fluxos financeiros no navegador | `financial.spec.ts`: aplicação completa + PostgREST/PostgreSQL reais no CI, BACK/LAY, cancelamento, revenda parcial, compra, validação/liquidação, P&L, resposta perdida, isolamento e empate bloqueado; duas modalidades e 1280/390 px. [Âmbito e limites](FINANCIAL_BROWSER_TESTS.md). Auth é identidade controlada; OAuth continua pendente |
| OAuth e ciclo de sessão | [Ensaios reais e limites](OAUTH_VALIDATION.md): preflight com Google/GitHub/Supabase reais; ensaio assistido para login completo/persistência/saída. Regressão local separada de limpeza de dados e respostas tardias. A certificação completa exige autenticação humana nas contas de teste |
| Backup/restauro e recuperação | `recovery.py`: base populada, comparação de todos os dados public/auth e esquema, ACL/RLS, reconciliação e aceitação funcional na cópia. Não certifica Auth/Storage reais |
| Quotas e responsabilidade | [Procedimento de operação](OPERATIONS_RECOVERY.md); configuração remota e responsáveis por confirmar |
| Reversões | Não implementadas nem simuladas como suportadas; procedimento exige preservar auditoria e decisão específica, sem contornar empate/zero |

As suites históricas verificam a evolução das migrações. Não representam um
requisito de compatibilidade de produto. O fluxo atual exige bets recorrentes,
modalidade explícita e resultados congelados. Nenhuma migração remota é executada.

A #8 permanece aberta pelos limites indicados; a #5 permanece bloqueada pelo
modelo financeiro de empate/zero. Evoluções opcionais da #9 não bloqueiam estes
trabalhos de operação.
