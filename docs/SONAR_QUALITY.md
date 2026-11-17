# Sonar: segurança da instalação e duplicação de SQL

## Causas corrigidas

O gate global de main reportava 29,0% de duplicação e dois alertas no install de
`validate.yml`: resolução sem lock e execução de scripts de lifecycle. A análise
do PR anterior estava verde porque avaliava alterações diferentes do conjunto
de código novo da análise global (desde a versão anterior).

`validate.yml` e `deploy.yml` passam a usar o mesmo comando já testado na CI:
`npm ci --ignore-scripts --no-audit --no-fund`. O lock versionado fixa a árvore;
nenhum passo usa `npx` para obter executáveis no momento da execução. Playwright
continua a ser invocado pelo executável instalado, com versão fixada no lock.

## Uma fonte para os exports SQL

Os ficheiros de instalação completa e upgrade repetiam integralmente 13 blocos
de migração. Esses corpos deixam de ser cópias versionadas. Em vez disso:

- `supabase/migrations/` conserva as fontes originais, sem modificações.
- `supabase/templates/` guarda apenas os cabeçalhos, guards e referências aos blocos.
- `supabase/bundles.json` fixa ordem, caminhos e SHA-256 das fontes/exports revistos.
- `scripts/build_sql_bundles.py` gera os exports, sem rede ou ligação a bases de dados.

Na raiz do repositório:

```text
python scripts/build_sql_bundles.py all
```

São criados os mesmos caminhos usados anteriormente:
`supabase/baselines/20261115_full_install.sql` e
`supabase/deploy/20261115_manual_upgrade_03_to_08.sql`.
Os dois resultados são **idênticos em UTF-8/LF aos exports anteriores**, verificados
contra hashes independentes nos testes. O upgrade continua com preflight,
postflight e uma única transação. As fontes e a semântica SQL não são refatoradas.
O gerador rejeita alteração dos corpos congelados, mudança de ordem, fontes
fora das migrações e caminhos que saiam do repositório.

Os exports são ficheiros gerados e ignorados pelo Git. A CI gera-os antes de
executar os percursos de instalação; não é guardada uma segunda implementação
de cada função. Para produzir um export diferente, criar uma nova versão e
rever os seus hashes; não corrigir um export congelado à mão.

## Âmbito da deteção de cópias

As migrações históricas contêm versões sucessivas intencionais das mesmas funções.
Não se altera uma migração histórica para fazer desaparecer uma comparação textual.
`.sonarcloud.properties` enumera esses ficheiros explicitamente **apenas em
`sonar.cpd.exclusions`**, a configuração suportada pela análise automática.
Não usa `sonar.exclusions`, não retira ficheiros à análise de segurança/reliabilidade,
não muda regras nem limiares do gate e não muda a versão para reiniciar o período.
Código da aplicação, gerador e testes continuam sujeitos a deteção de cópias.
Novas migrações não entram automaticamente nessa lista: exigem revisão explícita.

Referência oficial: [configuração adicional da análise automática](https://docs.sonarsource.com/sonarqube-cloud/analyzing-source-code/automatic-analysis#additional-analysis-configuration).

## Evidência

`tests/test_quality_pipeline.py` verifica exports congelados e determinísticos,
transação/guards, rejeição de fontes/ordem/caminhos adulterados, coerência do lock,
instalações seguras nos quatro passos dos workflows e âmbito restrito da exceção CPD.
A CI completa repete os três percursos PostgreSQL com os exports gerados, além de
98 testes de apresentação/regras, build, dois testes de navegador e concorrência
de mercados, fechos, estatísticas e liquidação.

As duas modalidades e o bloqueio de empate/zero não mudam. Nenhuma migração é
executada no Supabase remoto por esta correção. Gerar ficheiros não instala SQL.
