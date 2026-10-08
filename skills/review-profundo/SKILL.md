---
name: review-profundo
description: >-
  Executa um code review profundo e verificado de um Pull Request, no método
  "ground truth primeiro" — sem rodar nada localmente: lê o resultado do CI,
  confere no código cada símbolo/métrica/label que o diff referencia, traz o
  contexto do GitHub (issue, PRs relacionados abertos e mergeados, reviews e
  respostas anteriores, histórico de commits e merges da main, caminho real até
  a produção) e avalia o impacto nos dados (tabelas, filas e populações que a
  mudança toca, resíduo legado, rollback), medindo com segurança quando o número
  muda a decisão. Termina em uma de duas saídas formais no PR: review
  "comentado" listando SOMENTE os bloqueantes (🔴🟠), ou aprovação com as
  justificativas — e deixa o PR em watch no gh-inbox para o retorno do autor.
  Use sempre que o usuário pedir um "review profundo", "review completo",
  "revisa esse PR a fundo", quiser revisar um PR crítico antes de aprovar, pedir
  para verificar se um review recebido está correto, ou pedir para conferir as
  respostas a um review e aprovar.
---

# Review profundo (método ground-truth)

Um review profundo se diferencia de um review comum por uma inversão: **a
verificação vem antes da opinião**. Nada de "parece certo" — cada afirmação do
review nasce de algo lido no código real, no histórico do GitHub ou medido nos
dados. O produto é um corpo único, estruturado, que o autor consegue absorver
item a item.

**Não execute nada localmente.** Nada de teste, linter, build ou validador do
projeto na máquina. O CI já roda isso: o review lê o resultado dele (Fase 2). O
tempo vai para o que o CI não vê — o contexto do GitHub e o impacto nos dados.
Ler e buscar código, ler o histórico do git e abrir a estrutura de um artefato
do diff (YAML/JSON) é leitura, não execução, e continua valendo.

**Comente somente pontos bloqueantes.** O review lista apenas o que precisa ser
resolvido antes do merge (🔴🟠). Nada de achados cosméticos, idiomatismos
opcionais, elogios de protocolo ou qualquer texto que não mude a decisão de
mergear. A verificação de fundo continua completa; o que muda é o que chega ao
autor: menos, e só o que importa.

**Duas saídas, nunca comentário solto** (Fase 6): com bloqueante, review formal
do tipo *comment* listando os bloqueantes; sem bloqueante, aprovação com as
justificativas. O rascunho é SEMPRE apresentado ao usuário antes de postar, e
todo review postado termina com o PR em **watch** para o retorno do autor.

## Fase 1 — Contexto do PR e do GitHub

1. **O PR**: `gh pr view <n> --json title,body,files,commits,baseRefName,headRefOid,reviews,comments`
   e `gh pr diff <n>`. Leia os reviews e as respostas que já existem: não
   repita o que já foi levantado, e confira se o que o autor diz ter corrigido
   está mesmo no head.
2. **O código no head**: `git fetch` na hora (ref local defasada leva a review
   errado) e leia os arquivos tocados **no estado do head**, não só o diff — o
   entorno do hunk é onde moram os bugs de integração. Use
   `git worktree add <dir-temporário>/<repo>-<n> pr-<n>`; **nunca** faça
   checkout no working tree do usuário (pode ter trabalho não commitado). Sem
   clone, `gh api` nos contents.
3. **O entorno no GitHub**:
   - issue(s) que o PR fecha ou cita: critério de aceite, e o que a issue
     registra sobre o estado do mundo quando foi aberta;
   - PRs citados no corpo, no código e nos comentários: estado real (aberto,
     mergeado, quando) — "aberto em paralelo" escrito há uma semana pode já
     estar na main;
   - PRs **abertos** que tocam os mesmos arquivos (`gh pr list --search "<path>"`):
     conflito ou dependência cruzada é achado de coordenação;
   - `git log origin/main -- <arquivos>` desde que o PR foi aberto: o que
     mudou embaixo dele;
   - RFC/ADR/runbook/README do módulo que a mudança precisa respeitar.
4. **Escopo real** em uma frase: arquivos, +/−, mudança de comportamento, e
   onde o esforço foi concentrado.

## Fase 2 — Ground truth do código

Registre cada item com ✓/✗.

1. **CI no head atual**: `gh pr checks <n>`. Job vermelho ou cancelado: abra
   (`gh run view`, steps do job) e separe falha de código de infra — gate
   cancelado com zero steps é fila/runner, não código, mas ainda bloqueia o
   merge. Confira se o job que importa para o diff **rodou** (path filter que
   não casou = validador que nunca viu a mudança). Barra verde não é
   cobertura: leia o teste e rastreie se ele exercita o ramo crítico com os
   argumentos reais ("existe teste para X" ≠ "X foi executado"); se não
   exercita, é **falsa segurança**.
2. **Todo símbolo referenciado existe?** Cada métrica, label, função, campo,
   env var, rota ou arquivo que o diff menciona: confira com `file:line`. Um
   review que aponta `file:line` errado perde autoridade inteira — confira
   duas vezes.
3. **Cross-PR/cross-repo**: se o diff depende de algo de outro PR ou repo,
   verifique o estado real e o comportamento no intervalo (métrica inexistente
   → expressão vazia → alerta inerte pode ser design válido, mas precisa ser
   verificado, não assumido). Paridade exata entre os dois lados (lista de
   valores em duas linguagens, label emitido × label lido no alerta).
4. **Consistência com os vizinhos**: convenções do arquivo/módulo (labels,
   prefixos de métrica, padrão de teste, nomenclatura).
5. **Links e URLs**: dashboards, runbooks e docs referenciados existem? Um
   `runbook_url` 404 é achado de coordenação de release.
6. **Caminho até a produção**: como a mudança é deployada de fato — workflow e
   path filter, GitOps com auto-sync, comando manual (o target existe?).
   "Merge não deploya" precisa ser verdade hoje, não quando o PR foi escrito.
   Ordem de deploy entre componentes (api × consumer, exporter × regra) e o que
   acontece no intervalo.

## Fase 3 — Impacto nos dados

Para todo PR que mexe em escrita, leitura, dedup, normalização, formato de
evento, métrica ou alerta, responda — com número quando ele mudar a decisão:

- **O que a mudança toca**: tabelas/colunas, event store, tópicos/filas,
  índices, séries de métrica; por qual caminho de código e para qual recorte
  dos dados.
- **Que população é afetada, e quanto**: linhas/eventos por dia, com corte pela
  dimensão que importa no domínio e amostra concreta. Confira a ordem de
  grandeza contra a população suposta antes de interpretar.
- **Lado produtor dos casos degenerados**: campo vazio, coringa, legado — quem
  grava, se há fallback, com que frequência sai assim. Regra coerente sobre dado
  degenerado ainda corrompe o resultado.
- **Resíduo**: dado já escrito que a mudança não corrige (event store
  append-only, valor congelado, linha fundida). Existe? Conserta sozinho ou fica
  preso? "Não se espera população" é afirmação a contar, não a aceitar.
- **Rollback**: voltando a flag ou o deploy, o que acontece com o que já foi
  escrito? A recuperação depende de algo (reprocessamento, backfill) que outra
  mudança pode desligar?
- **Observabilidade**: série que some, dobra ou muda de semântica; alerta que
  fica inerte ou passa a disparar.

Como medir, sem exceção:

- **Defina o que está medindo e mostre a query antes de rodar.** Medição não é
  diagnóstico.
- **Alvo**: réplica analítica ou data warehouse primeiro (serve para censo, não
  para o estado do instante); métricas e logs pela stack de observabilidade.
  Banco de produção só com throttle: serial, 1 conexão, timeout curto, nunca
  leque de workers. Antes de conectar, confira para onde a conexão aponta —
  nunca assuma.
- **Custo**: query paga passa por dry-run; apresente o custo e espere o OK
  explícito do usuário antes de rodar, mesmo que sejam centavos.
- **Credenciais** só lidas em runtime de um arquivo local; nunca literais em
  comando, script ou arquivo.
- Sem acesso ou sem OK para medir: a query vira pedido no review — o autor conta
  e registra o número no PR.

## Fase 4 — Caçar os achados

Para cada suspeita, monte o trio completo antes de escrever: **evidência**
(`file:line`, histórico do GitHub ou número medido) → **cenário de falha
concreto** (entradas/estado → resultado errado, narrado; sem cenário narrável,
corte) → **sugestão acionável** (de preferência com código ou query pronta).

**Filtro de bloqueio:** só entra o que for 🔴 (anula o propósito do PR) ou 🟠
(correção/precisão a resolver antes do merge). Cosmético, idiomático, opcional
ou "seria bom mas não trava o merge" é descartado. Na dúvida, o que não for
defensável como "precisa resolver antes de mergear" cai fora.

Ângulos que reviews comuns esquecem:

- **Estado futuro**: a mudança sobrevive ao end-state do épico/migração em
  curso? Cite o plano que define esse futuro.
- **Código certo, texto errado**: descrição, comentário ou *help* de métrica
  prometendo o que a implementação não cobre é achado — separe "o código está
  certo; o texto atribui o mecanismo errado".
- **Corpo desatualizado**: PR que recebeu merge da main depois de escrito tem
  premissas a reconferir — números, mecanismo de deploy, "PR em paralelo" que
  já mergeou, justificativa que outro PR já entregou.
- **Fix de review desfeito por merge**: para cada commit de correção de review,
  confira que o conteúdo sobreviveu no head (`git diff <commit-do-fix> HEAD --
  <arquivo>`); merge da main pode devolver o hunk à versão antiga sem conflito.
- **Decisões deliberadas desprotegidas**: comportamento sutil e intencional
  merece registro em comentário para ninguém "simplificar" depois.
- **Aritmética de detecção**: janelas somam (`rate[15m]` + `for: 15m` ≈ 30 min),
  cardinalidade multiplica, timeouts compõem. Faça a conta e compare com o
  texto.
- **Casos de borda de linguagem/ferramenta**: vector matching com empty, tipos
  estritos, staleness, colisão de labels de scrape.
- **Assimetrias**: guarda ou teste para a dimensão X sem o espelho para Y é gap.
- **Silent failure de configuração**: chave ausente caindo em default sem log é
  indistinguível de desligamento deliberado.
- **Recorte de escopo**: parte que resolve outro problema que o do título,
  sobretudo se é a fonte do maior risco, merece a sugestão de entrar sem ela.

## Fase 5 — Escrever o corpo

As duas saídas usam o mesmo cabeçalho:

```markdown
## Visão geral
[Escopo real: N arquivos, +X/−Y, o que muda, onde o esforço foi concentrado.]

**Verificação:** [CI no head <sha> (jobs relevantes); o que foi conferido no
código e no GitHub; números medidos nos dados, com a fonte ou a query.]

**Veredito:** [uma frase honesta: maduro/cirúrgico/tem bloqueante.]
```

**Com bloqueante**, em seguida os achados:

```markdown
## 🔴 N. [Título — só se anular o propósito central]
## 🟠 N. [Correção/precisão a resolver antes do merge]
[Evidência → cenário de falha narrado → sugestão com código/query. Numeração
sequencial. Só bloqueantes — nada de 🟡/🟢.]
```

**Sem bloqueante**, em seguida as justificativas da aprovação:

```markdown
## Por que aprovo
- [Cada ponto de risco que a mudança tinha e a evidência de que está coberto:
  `file:line`, PR/issue, número medido. Curto, um item por risco.]
- [O que fica para depois do deploy, se houver: validação a fazer, recontagem.]
```

Não invente achado para preencher nem infle as justificativas: na aprovação,
cada item é um risco real que foi verificado, não elogio.

Regras de tom:

- Direto e específico; zero cerimônia, zero "talvez considerar possivelmente".
- 🔴 é raro; não infle. Sem seção de pontos fortes.
- Nada de texto de enfeite: sem parafrasear o diff, sem observação que o autor
  tira sozinho olhando o código.
- Não mencione o que deixou de rodar localmente: a verificação é o CI, o código,
  o GitHub e os dados.
- Quando a forma atual está deliberadamente documentada e mesmo assim é
  bloqueante, diga que trocar exigiria alinhar a documentação.
- Escreva no idioma que o repositório já usa nos PRs e reviews.

## Fase 6 — Entregar

Apresente o rascunho completo ao usuário com um resumo de uma linha (quantos
achados por severidade) e qual das duas saídas ele vai virar. Anote o head
(`headRefOid`) sobre o qual o rascunho foi escrito: é contra ele que o post é
conferido.

**Reconfira imediatamente antes de postar** — o OK do usuário pode chegar minutos
depois do rascunho, e nesse intervalo o autor sobe commit, responde ou mergeia:

```bash
gh pr view <n> --repo <owner/repo> --json state,headRefOid,comments,reviews
```

- **Mergeado ou fechado:** não poste. Diga ao usuário e pergunte se ainda quer o
  registro (review "comentado" num PR fechado não muda nada e não tem watch).
- **Head diferente do revisado, ou resposta nova do autor:** não poste o rascunho.
  Ele pode pedir o que acabou de entrar. Leia o delta e as respostas, refaça o
  rascunho sobre o head novo e apresente de novo — o OK anterior valia para o texto
  antigo.
- **Igual ao revisado:** poste. Se o rascunho promete CI verde e algum job ainda
  roda, espere fechar antes (em segundo plano, sem polling na conversa).

Só depois do OK explícito e dessa reconferência, poste como **review formal** —
nunca como `gh pr comment` solto:

- **Há bloqueante** → `gh pr review <n> --comment --body-file <arquivo>`: marca o
  PR como revisado e lista os bloqueantes.
- **Nada bloqueante** → `gh pr review <n> --approve --body-file <arquivo>`, com as
  justificativas.

`--request-changes` só se o usuário pedir. Aprovar não é mergear: merge é
sempre do usuário.

**Watch — logo depois de postar, nas duas saídas, sempre:**

```bash
~/.claude/bin/gh-inbox watch <owner/repo> <num> <COMMENTED|APPROVED>
~/.claude/bin/gh-inbox watching    # confirma
```

O watch é do gh-inbox (shell, custo zero, sem LLM). A cada scan ele confere a
atividade do **autor** do PR depois do review — commit novo (de qualquer um),
comentário, review ou edição do corpo — e, quando há, o PR entra no `/inbox` como
RE_REVIEW com o motivo (`commits`, `resposta` ou `commits+resposta`), e o poller
de 60 s mostra um banner com o botão "Revisar". Atividade de outros revisores não
dispara. **Nada roda sozinho:** o re-review é escolha do usuário, pelo banner ou
pelo `/inbox`. PR mergeado ou fechado sai do watch sozinho; `gh-inbox unwatch
<owner/repo> <num>` tira na mão. Diga ao usuário que o watch ficou ativo.

**Re-review (o autor respondeu):** comece pelo que o watch registrou —
`gh-inbox list` mostra o motivo, `gh-inbox diff <owner/repo> <num>` dá o delta
desde o commit revisado, e as respostas do autor desde o review estão nos
comentários e reviews posteriores a ele. Reconfira cada resposta contra o head:
commit novo e o diff dele, diff líquido contra a main, CI no head novo, corpo
atualizado, e de onde veio o número que o autor diz ter medido (o método cobre o
que foi pedido?). Tudo fechado → aprovação listando o que foi conferido e o que
ainda falta (ex.: gate a re-rodar). Algo aberto → novo review *comment* só com o
que segue bloqueando. Depois de postar o re-review, rode o `gh-inbox watch` de
novo: isso rearma o watch a partir do review novo.

Ao final, remova worktrees e refs temporárias.
