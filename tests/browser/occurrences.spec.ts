import {test,expect} from '@playwright/test';
for(const viewport of [{width:1280,height:900},{width:390,height:844}]){
 test(`historical navigation, mode and ranking at ${viewport.width}px`,async({page})=>{
  await page.setViewportSize(viewport);
  await page.addInitScript(()=>{Date.now=()=>Date.parse('2026-11-17T12:00:00Z')});
  await page.route('https://fonts.googleapis.com/**',route=>route.abort());
  await page.goto('tests/browser/index.html');
  await page.getByLabel('Ocorrência').selectOption('past');
  await expect(page.getByTestId('selection')).toHaveText('past');
  await expect(page.getByText('Períodos passados são apenas consultáveis.',{exact:false})).toBeVisible();
  await page.getByLabel('Resultado',{exact:true}).selectOption('second');
  await expect(page.locator('.target-row')).toContainText('Concorrente B');
  await page.getByLabel('Bet',{exact:true}).selectOption('d');
  await page.getByLabel('Ocorrência').selectOption('past');
  await expect(page.getByText('Variação desde o fecho do período anterior (pp)',{exact:true}).first()).toBeVisible();
  await expect(page.locator('.target-row')).toContainText('Concorrente C');
  await expect(page.getByText('Transação executada',{exact:false})).toBeVisible();
  await expect(page.getByText('Liquidado em',{exact:false})).toBeVisible();
  await expect(page.getByRole('button',{name:/Comprar|Aceitar|Liquidar resultado/})).toHaveCount(0);
  await page.getByLabel('Ocorrência').selectOption('empty');
  await expect(page.getByText('Dados históricos indisponíveis / por apurar')).toBeVisible();
  await expect(page.locator('.rank-row')).toHaveCount(0);
  await page.getByRole('button',{name:'Ir para o período corrente'}).click();
  await expect(page.getByTestId('selection')).toHaveText('current');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 });
}
