# BetCoins — Setup das plataformas (fase final)

**Não executar ainda sem rever a PR de implementação.** Estas instruções foram preparadas para o setup conjunto após validação.

## Requisitos
- Repositório `primeiraacademiadev/betcoins` com o código aprovado em `main`.
- Conta Supabase com projeto PostgreSQL.
- OAuth Google e GitHub.
- GitHub Pages ativo (Deploy from GitHub Actions ou branch com `dist/`).
- Browser suportado com JavaScript; não existem tokens de acesso privilegiado no frontend.

## 1. PostgreSQL e funções

1. Criar projeto Supabase Free.
2. **Instalação nova e vazia:** escolher exatamente um dos seguintes caminhos:
   - Método recomendado para projetos geridos por Supabase CLI: aplicar por ordem os nove ficheiros de `supabase/migrations/`, conservando o histórico de migrações.
   - Método de instalação SQL manual: executar `supabase/baselines/20261115_full_install.sql` (01–07), depois `202611150004_position_settlement_pnl.sql` (08) e `202611150005_competition_validation.sql` (09). Registar a baseline; não reaplicar as migrações 01–07.
3. **Projeto existente:** nunca executar a baseline. Antes de qualquer alteração, consultar `supabase_migrations.schema_migrations` (ou o histórico oficial do projeto); comparar as versões efetivamente aplicadas com os nomes em `supabase/migrations/`, fazer backup e aplicar **apenas as versões em falta**, pela ordem original. Não deduzir o estado remoto a partir do CI ou de GitHub Pages. A migração 09 está preparada, mas **não foi aplicada ao Supabase remoto** nesta entrega; ver [operação E2](docs/COMPETITION_OPERATIONS.md).
4. **Atualizações futuras:** criar novas migrações aditivas; manter os sete ficheiros originais e a baseline de 2026-11-15 imutáveis. Uma nova baseline deverá ter data/versão própria e ser verificada num PostgreSQL descartável.
5. Criar uma conta de teste com social login.
6. No SQL Editor, **como administrador da BD**, atribuir o primeiro administrador e concorrente usando o UUID da conta de teste:

```sql
insert into public.admins(id) values ('UUID-DA-CONTA-AQUI');
insert into public.competitors(id) values ('UUID-DA-CONTA-AQUI');
```

O primeiro concorrente tem de ser criado por um operador; um utilizador não pode autoproclamar-se primeiro concorrente.

**Nota importante:** as migrações são uma implementação inicial. Validar num projeto de teste descartável antes de utilização partilhada; verificar RLS, privilégios, assinaturas das funções e testes concorrentes antes de produção.

## 2. Social login

No Supabase Authentication configurar os providers Google e GitHub com respetivos Client IDs / secrets armazenados **apenas** na configuração do provider. Configurar a URL pública da aplicação, por exemplo:

`https://primeiraacademiadev.github.io/betcoins/`

Adicionar o mesmo endereço às URL de redirecionamento permitidas do Supabase. Nos providers OAuth usar o endereço de callback fornecido pelo próprio Supabase (não o GitHub Pages diretamente).

## 3. Ambiente frontend

```sh
cp .env.example .env
npm install
npm run dev
npm test
npm run build
```

Variáveis:
- `VITE_SUPABASE_URL`: URL do projeto
- `VITE_SUPABASE_ANON_KEY`: chave pública / publishable/anon compatível com Supabase JS

**Nunca** inserir `service_role`, `secret`, passwords, Client Secret OAuth ou tokens de corretoras em variáveis `VITE_*` nem no GitHub Pages. O frontend contém sempre estas variáveis no JavaScript entregue ao browser.

## 4. GitHub Pages

A aplicação está configurada para `base: '/betcoins/'`. O workflow de CI verifica testes/build e não publica automaticamente. Antes de ativar o deploy público, criar um workflow separado para Pages com permissões mínimas `pages: write` e `id-token: write`, e variáveis públicas `VITE_*` em Repository Variables, nunca secrets privados.

O deployment só deve ser ativado após passar os testes com Supabase de teste.

## 5. Créditos semanais

A função `grant_weekly()` distribui 1 000 BetCoins aos espectadores elegíveis, incluindo semanas em atraso desde o registo dentro do campeonato, e rejeita execução por não administradores. O botão administrativo permite executar manualmente, sem duplicação na mesma semana.

**Agendamento automático ainda não configurado.** Na fase de setup decidir entre pg_cron controlado pelo operador e uma automação GitHub Actions protegida. Não colocar credenciais privilegiadas numa aplicação pública.

## 6. Procedimento de fecho

- Os concorrentes atualizam os YTD (declaração manual).
- Com a migração 09, o gestor captura as declarações históricas até aos limites inicial/final; sem ambos não existe delta classificável do sprint. Ausências ficam explicitamente sem classificação.
- O gestor revê datas, valores, empates e ausências e regista uma validação final imutável, com nota, autor e data. O anual usa o YTD de fecho. Ver [procedimento completo](docs/COMPETITION_OPERATIONS.md).
- Esta validação não seleciona outcomes nem liquida apostas. A associação de resultados validados aos mercados é trabalho da #5/#11. Não usar a liquidação binária existente para empates/zero ou para as modalidades ainda não suportadas da #1.
- Não há retificação automática de mercados liquidados na V1. Corrigir antes do settlement.

## 7. Checklist de aceitação pré-lançamento

- [ ] Login/logout Google e GitHub, redirecionamento e sessão.
- [ ] Um utilizador sem login não lê dados protegidos.
- [ ] Uma conta não altera score alheio, wallets, ledger, candidatos ou positions.
- [ ] Votação maioritária; eleitorado congelado; primeira admissão administrada.
- [ ] Criação de aposta rejeitada após `closes_at` (hora servidor).
- [ ] Recarga repetida da mesma semana não duplica BetCoins.
- [ ] Aceitação simultânea da mesma oferta não duplica correspondência.
- [ ] Vendedor não consegue vender uma posição duas vezes.
- [ ] Compra transfere colateral, direitos e preço sem criar ou destruir moedas.
- [ ] Liquidação conserva pontos e não paga duas vezes.
- [ ] Interfaces móveis e acessibilidade validadas.
- [ ] Backup e recuperação definidos, quotas Free compreendidas.

## Limitações conscientes da V1

- Mercado secundário: suporta **revenda integral e parcial por lotes indivisíveis** após aplicação da migração `202611150003_partial_resale.sql`.
- Book de ofertas: manual e P2P, sem motor automático de correspondência nem promessa de liquidez.
- Ranking de espectadores usa saldos contabilísticos (disponível + reservado); não é uma marcação a mercado independente. O retorno relativo simples é `(património - créditos recebidos) / créditos recebidos`. O resultado definitivo deve ser avaliado após as liquidações.
- Sprints: captura manual de snapshots nos limites; não existe recolha automática de scores.
- O mecanismo de correção/reversão de liquidações não está implementado.
- Só existe a gestão inicial de um campeonato; múltiplas temporadas são trabalho futuro.
