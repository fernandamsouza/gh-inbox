---
name: inbox
description: >
  Mostra a fila triada de PRs do GitHub que precisam de você (review pedido,
  re-review, seu PR com changes-requested, CI vermelho) e dispara o review do
  item escolhido. Use quando a pessoa pedir "/inbox", "o que tem pra revisar", "minha
  fila de review", "o que tá esperando eu", "chegou coisa nova no github", ou quando
  pedir para ver ou trocar a skill do botão Revisar. Não use para
  revisar um PR específico que a pessoa já apontou — nesse caso vá direto na skill de
  review.
---

# /inbox — fila de review triada

Frontend do triador `~/.claude/bin/gh-inbox`. O triador é shell puro (custo zero);
esta skill só lê a fila e despacha o que a pessoa escolher. **Nada de review dispara
sem ela escolher.**

## 0. Qual skill de review usar

A skill de review vem do `~/.claude/gh-inbox/skills.conf`, por bucket (`PRIMEIRA=`,
`RE_REVIEW=`, …, e `default=` para o resto). A variável `GH_INBOX_REVIEW_SKILL`, se
existir, vale para todos os buckets. Abaixo, **`<skill>`** é esse valor:

```bash
grep -E '^(PRIMEIRA|RE_REVIEW|default)=' ~/.claude/gh-inbox/skills.conf
```

Sem `skills.conf`, use `review-profundo` (o default que o instalador grava). Valor
vazio num bucket = não ofereça review nele. Se a skill configurada não existir nesta
instalação do Claude Code, diga isso em uma linha e pergunte qual usar — não troque
por outra por conta própria.

**Trocar a skill quando a pessoa pedir** ("usa a meu-review no Revisar", "qual skill o
botão usa?", "tira o review do bucket MEU_PR"): não edite o arquivo, use o comando, que
valida o nome antes de gravar:

```bash
~/.claude/bin/gh-inbox skill                         # mostra a atual e as instaladas
~/.claude/bin/gh-inbox skill <nome>                  # PRIMEIRA, RE_REVIEW e default
~/.claude/bin/gh-inbox skill <BUCKET> <nome|off>     # só um bucket
```

Repasse a saída em uma ou duas linhas, incluindo o aviso de watch se ele aparecer.
Trocar a skill é pedido explícito da pessoa — nunca troque por iniciativa própria.

## 1. Atualizar e mostrar a fila

```bash
~/.claude/bin/gh-inbox scan && ~/.claude/bin/gh-inbox list
```

**Se a tool `mcp__visualize__show_widget` estiver disponível**, mostre a fila como
widget clicável, não como tabela de texto — texto morto obriga a pessoa a digitar o
número de volta. O widget deve ter:

- cada `repo#num` como `<a href>` pro PR no GitHub
- um botão por linha chamando `sendPrompt()`:
  - bucket `PRIMEIRA`/`RE_REVIEW` → `"Roda a <skill> no <repo>#<num>"` (o `repo` do item já vem
    com a org)
  - bucket `MEU_PR` → `"Lê os comentários que recebi no meu PR <...> e me propõe o ajuste"`
  - bucket `CI_VERMELHO` → `"Diagnostica o CI vermelho do <...>"`
  - bucket `PRONTO` → **sem botão de ação**, só o link pro PR: mergear é da pessoa
- chips de filtro por bucket e um select de ordenação, **resolvidos em JS** (não em
  `sendPrompt`): `prioridade` (default), `menor primeiro`, `maior primeiro`
- `menor primeiro` importa: o tamanho do diff é o que escala o custo do review, e
  quem usa isto costuma querer começar pelo mais barato

**Se essa tool não estiver disponível** (ela não é padrão do Claude Code — é uma MCP
específica), caia para uma tabela markdown com as mesmas colunas (bucket, `repo#num`
como link, detalhe, título) na ordem do `list`, e diga em uma linha que a pessoa
escolhe respondendo com o número ou o `repo#num`.

Ordem default = a que o `list` devolve (ranqueada: trava-merge primeiro, trivial por
último). Não reordene fora do widget/tabela. Não resuma a fila em prosa.

Se a fila estiver vazia, diga isso em uma linha e pare — sem widget.

## 2. Esperar a escolha

A pessoa escolhe por número, por repo ("os do repo X"), ou por bucket ("só os meus PRs").
Se não houver escolha, **pare aqui**. Não presuma "então roda todos".

Antes de disparar mais de um item, avise quantos são e confirme — cada item roda a
`<skill>` inteira (a `review-profundo`, por exemplo, lê o CI, o GitHub e os dados de
cada PR e pode pedir OK para medir no banco).

## 3. Despachar

Os buckets vêm no `queue.json` (`~/.claude/gh-inbox/queue.json`).

### `PRIMEIRA` — review pedido, você ainda não revisou
Invoque a **`<skill>`** do bucket no PR (`repo` + `num` do item).

### `RE_REVIEW` — você já revisou e vieram commits novos
Invoque a **`<skill>`** do bucket, mas alimentada **só com o delta**:

```bash
~/.claude/bin/gh-inbox diff <repo> <num>
```

Isso imprime o compare do SHA do último review até o head — não o PR inteiro.
Diga o que já tinha sido apontado antes (`prev_state` no item) e concentre o
review no que mudou depois. O campo `rerequested` diz se houve pedido formal ou se
foram só commits novos.

Item com `watched: true` veio do watch que a skill de review registrou depois de
postar (a `review-profundo` faz isso sempre; outra skill precisa chamar
`gh-inbox watch` no fim). O campo `motivo` diz o que o autor fez depois do review (`prev_at`):
`commits`, `resposta` (comentário, review ou edição do corpo, **sem** commit — o
diff vem vazio, então leia as respostas dele desde `prev_at`) ou
`commits+resposta`. Depois do re-review postado, registre o watch de novo
(`~/.claude/bin/gh-inbox watch <repo> <num> <COMMENTED|APPROVED>`), se a skill não
tiver feito isso.

### `PRONTO` — seu PR aprovado, CI verde, sem thread aberta
Não é review nem diagnóstico. É o sinal de que **a pessoa** pode mergear. Diga qual PR,
quem aprovou, e pare aí. **Nunca mergeie** — nem sugira que você vai mergear.

```bash
gh pr view <num> --repo <repo> --json reviews,mergeable,mergeStateStatus
```

### `MEU_PR` — seu PR com changes-requested / thread esperando você
Não é review. Leia o que pediram e proponha o ajuste:

```bash
gh pr view <num> --repo <repo> --comments
gh api repos/<repo>/pulls/<num>/comments --jq '.[] | {path, line, user: .user.login, body}'
```

Traga os pontos levantados e a proposta de correção. **Não commite sem mostrar o diff
e ter o OK.**

### `CI_VERMELHO` — checks falhando no seu PR
Não é review. Ache o check que falhou e diagnostique:

```bash
gh pr checks <num> --repo <repo>
gh run view <run-id> --repo <repo> --log-failed
```

## 4. Ao terminar o review: widget de confirmação

A `<skill>` termina com um parecer em texto. **Não pare aí e não pergunte em
prosa se pode postar.** Se `mcp__visualize__show_widget` estiver disponível, renderize
um widget com:

- identificação do PR (repo#num, autor, tamanho) e a contagem de bloqueantes
- **um cartão por achado**: severidade, `arquivo:linha`, a afirmação em uma linha, e o
  cenário de falha concreto em uma linha
- um `<a href>` no `arquivo:linha` apontando para a linha no GitHub
  (`https://github.com/<repo>/pull/<num>/files#diff-...` ou o blob com `#L<n>`)
- botões, todos via `sendPrompt()`:
  - **postar no PR** → `"Posta os achados do review no <repo>#<num>"`
  - **postar só os bloqueantes** → quando houver não-bloqueantes na lista
  - **descartar** → `"Descarta o review do <repo>#<num>, não posta"`
  - por achado, um **remover** que exclui aquele item antes de postar
- se o review não encontrou nada bloqueante, o widget diz isso em uma linha e o único
  botão é **aprovar** — que **não** aprova nada: manda
  `"Não achei bloqueante no <repo>#<num>; me mostre o resumo pra eu decidir o approve"`.
  Aprovar é sempre da pessoa.

Sem essa tool, liste os achados numerados (severidade, `arquivo:linha`, afirmação,
cenário de falha) e pergunte em uma linha o que postar — mas **só posta com resposta
explícita**, nunca por padrão.

O clique no botão **é** o OK. Sem clique, nada vai pro PR. Nunca poste porque o
review "ficou bom" nem porque o review foi pedido — pedir review não é autorizar
comentário.

Depois de postar, confirme em uma linha com o link dos comentários criados.

## Regras que não se relaxam

- **Nunca aprovar, nunca mergear.** Entregue o parecer; approve/merge é da pessoa.
- **Nunca postar comentário no PR sem o OK explícito.** A `<skill>`
  roda, o resultado vira o widget de confirmação da seção 4, e só vai pro PR quando houver o clique. Pedir o review não é autorizar comentário.
- **Não commitar sem explicar o diff antes** (vale para `MEU_PR`).
- Idioma: comentário de PR segue o padrão do repo.

## Marcar como visto

Depois de tratar os itens, para limpar o que já foi visto:

```bash
~/.claude/bin/gh-inbox mark
```

Isso evita que os mesmos itens voltem como novos. Não rode `mark` por iniciativa
própria.
