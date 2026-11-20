# OAuth e ciclo de sessão — #8

## O que cada ensaio demonstra

| Ensaio | Serviço/identidade | Evidência e limite |
| --- | --- | --- |
| `test:oauth:preflight` | Aplicação publicada, Supabase Auth e Google/GitHub reais | Quatro cenários: dois fornecedores a 1280/390 px. Confirma pedido de autorização, retorno `/betcoins/`, código, state e callback correto do Supabase. Não introduz credenciais, não completa login e não certifica sessão |
| `test:oauth:assisted` | Mesmos serviços reais; conta de teste autenticada pelo operador | Confirma regresso, remoção dos parâmetros de autenticação da URL, sessão após reload, identidade associada, saída, limpeza de dados e reload sem sessão. Precisa de intervenção humana e não corre automaticamente no CI |
| `session.spec.ts` | App + PostgREST/PostgreSQL reais, identidade Auth controlada | Quatro regressões locais, duas modalidades e duas larguras. Uma resposta financeira da sessão anterior é entregue depois da saída; não pode repor dados privados. Não é apresentado como OAuth real |

Nenhum ensaio executa migrações no Supabase remoto, altera providers, cria Client
Secrets, alarga scopes ou substitui Google/GitHub por um servidor falso. O preflight
usa um contexto vazio, sem sessão guardada e sem interceção de rede. Contacta os
serviços públicos reais e termina no fornecedor, antes de autenticar a conta.

O fluxo usa os callbacks existentes descritos nos guias oficiais de
[Google](https://supabase.com/docs/guides/auth/social-sign-in/auth-google) e
[GitHub](https://supabase.com/docs/guides/auth/social-sign-in/auth-github).

## Ensaio assistido completo

Preparar uma conta de teste para cada fornecedor. A entrada pode criar um
utilizador/perfil e o crédito inicial normal na aplicação; não usar contas alheias
nem contas reais de jogadores para gerar dados descartáveis. Não executar operações
de mercado neste ensaio. Não fornecer passwords, MFA ou cookies ao código ou ao chat.

Num ambiente local autorizado com dependências e Chromium instalados, definir
`OAUTH_ASSISTED=1` no ambiente e executar `npm run test:oauth:assisted`. O teste abre
o fornecedor; o operador introduz credenciais/MFA e revê eventual consentimento no
próprio navegador. O teste continua quando regressa ao BetCoins e termina a sessão
de teste depois das verificações. Recusa execução no CI e execução sem opção explícita.

Não são importados cookies, tokens ou storageState, nem são gravados novos estados
de sessão. Traces, vídeos e screenshots automáticos estão desligados neste ensaio.
Os diretórios de diagnóstico estão ignorados pelo Git; se uma falha gerar contexto
com informação da conta de teste, mantê-lo local e não o anexar a issues ou PRs.

O ecrã de consentimento pode não ser apresentado pelo fornecedor. Cancelamento
nesse ecrã não é um requisito adicional da #8, nem exige revogar permissões para
o fazer aparecer. CAPTCHA, introdução de credenciais, eventual MFA,
aprovação de novas permissões e criação de contas ficam a cargo do operador.
Não contornar bloqueios dos fornecedores para automatizar a entrada.

## Correção do ciclo de sessão

A inspeção do fluxo de saída encontrou dados mantidos no estado da interface:
limpar apenas saldo e perfil deixava posições, ledger e estado administrativo na
memória do ecrã. A interface passa a ter uma instância de estado por identidade;
sair ou mudar de utilizador destrói todo o estado privado e os rascunhos. Respostas
pendentes da identidade anterior não podem restaurá-lo. Eventos Auth mais recentes
têm precedência sobre a consulta inicial de sessão.

Não modifica permissões, carteiras, modalidades ou liquidação. Não exige migração.
As regressões locais usam respostas financeiras reais e verificam a saída com
posições existentes, uma resposta atrasada e reload posterior.

## Estado da validação real

Os PRs #43 e #44 estão integrados em `main` e publicados. Em 20/11/2026, o operador
confirmou, para GitHub e Google, entrada/regresso à aplicação, persistência da
sessão após recarregar e ausência de sessão depois de sair e recarregar.
Estes fluxos ficam validados manualmente pelo operador; não se afirma que o comando
de ensaio assistido foi executado, nem que o preflight certifica login completo.

A #8 mantém apenas as confirmações operacionais mínimas de backups e quotas
descritas na [matriz de aceitação](ISSUE_8_ACCEPTANCE.md). Reversões ficam fora do
MVP. Não exige restauro integral do serviço remoto nem cancelamento no fornecedor.
