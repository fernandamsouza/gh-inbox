# gh-inbox

Para de abrir o GitHub para *descobrir* o que precisa de você.

Um poller local avisa em ≤60s quando pedem seu review, te marcam ou mexem no seu PR.
O banner é clicável e vai direto pro PR; o que você não viu na hora fica na Central de
Notificações. E a skill `/inbox` mostra a fila já classificada, com um botão que dispara
o review no PR que você escolher.

**A parte que roda 24/7 custa zero.** Triagem e notificação são shell puro — `gh`, `jq`
e `curl`. Nenhum token de LLM é gasto até você escolher um PR para revisar.

## Instalar

```bash
git clone <este-repo> && cd gh-inbox && ./install.sh
```

Precisa de **macOS**, [`gh`](https://cli.github.com) autenticado e `jq`. O instalador
falha cedo, com a mensagem do que fazer, se faltar qualquer um — ou se o seu token não
conseguir ler `/notifications`.

É **idempotente**: rodar de novo preserva o estado e não faz o backlog voltar a
notificar.

**A org não tem default.** Se a sua conta aparece em exatamente uma org, o instalador
detecta e segue; se aparece em várias, ele lista e pede `--org`. Cravar um default faria
a ferramenta parecer quebrada para quem não é daquela org — as buscas voltariam vazias,
sem erro.

```bash
./install.sh --org minhaorg     # triagem restrita a outra org do GitHub
./install.sh --no-notifier      # banner sem clique; não instala dependência nenhuma
./install.sh --no-icon          # não personaliza o ícone do banner
```

### O que o instalador faz

1. confere macOS, `gh` autenticado, `jq`, e acesso a `/notifications`
2. instala o `terminal-notifier` via brew, copia o `.app` para `~/Applications` e
   registra no Launch Services (esse passo é obrigatório — veja *Problemas conhecidos*)
3. monta uma cópia do app com nome e ícone próprios (`gh-inbox`)
4. instala os scripts em `~/.claude/bin` e a skill `/inbox`
5. gera o LaunchAgent com o seu `$HOME` e carrega (poll de 60s)
6. **semeia o baseline**: o que já existe hoje entra como visto, então você só é
   avisada do que for novo a partir da instalação
7. dispara uma notificação de teste

### O único passo manual

O passo 7 existe de propósito: ele faz o **prompt de permissão do macOS aparecer na
hora**, com você ainda no terminal. Clique em **Permitir** e acabou.

O macOS exige consentimento do usuário para qualquer app postar notificação, e isso não
é pré-concedível — não há como o instalador resolver.

Se você não vir prompt nenhum, o macOS já tem um "não" gravado. **Vá em Ajustes do
Sistema > Notificações > gh-inbox e ligue.** Não perca tempo com
`tccutil reset UserNotification …`: apesar de ser o que a mensagem de erro do
terminal-notifier sugere, ele falha com *"Failed to reset"* nesta configuração.

Sem a permissão nada quebra: o poller cai no `osascript`, que avisa mas não abre o PR
no clique.

Opcional, e vale: nos mesmos Ajustes, troque o estilo de **Banners** para **Alertas**.
Banner some sozinho em segundos; alerta fica na tela até você dispensar. Nos dois casos
o histórico é preenchido.

## Usar

| | |
|---|---|
| banner | clique abre o PR no GitHub |
| Central de Notificações | histórico, uma entrada por PR, cada uma clicável |
| `/inbox` no Claude Code | fila clicável; escolhe e dispara o review |
| `gh-inbox list` | a fila no terminal |
| `gh-inbox scan` | recoleta e reclassifica |
| `gh-inbox digest` | só o que é novo desde a última vez (exit 1 se nada) |
| `gh-inbox diff <repo> <n>` | no re-review: só o delta desde o seu último review |
| `gh-inbox mark` / `seed` | marca como visto / baseline inicial |

Os binários ficam em `~/.claude/bin/`. O histórico pelo terminal:

```bash
~/Applications/gh-inbox.app/Contents/MacOS/terminal-notifier -list ALL
```

## O que ele classifica

| Bucket | O que é |
|---|---|
| `PRONTO` | seu PR aprovado, CI verde, sem thread aberta — dá pra mergear |
| `MEU_PR` | seu PR com changes-requested ou thread esperando você |
| `CI_VERMELHO` | checks falhando num PR seu |
| `RE_REVIEW` | você já revisou e vieram commits novos — revisa **só o delta** |
| `PRIMEIRA` | pediram seu review e você ainda não revisou |

A ordem da tabela é a prioridade na fila: o que destrava merge primeiro, trivial por
último. Drafts são filtrados.

## Configuração

Nada obrigatório. A identidade vem do `gh` — descoberta com `gh api user`, cacheada, e
revalidada a cada 10 minutos (se você rodar `gh auth switch`, ele percebe e troca).
**Não** usa `git config`: e-mail de commit não é login do GitHub.

| Variável | Default |
|---|---|
| `GH_INBOX_ORG` | **obrigatória** — detectada na instalação, gravada no plist |
| `GH_INBOX_USER` | descoberto do `gh` |
| `GH_INBOX_DIR` | `~/.claude/gh-inbox` |
| `GH_INBOX_LOG` | `~/Library/Logs/gh-inbox-poll.log` |
| `GH_INBOX_SCAN_EVERY` | `10` (ticks entre scans de estado) |
| `GH_INBOX_NOTIFIER` | `gh-inbox` (nome do app do banner) |

## Ícone e nome do banner

Por padrão o banner aparece como **gh-inbox**, com o ícone de `assets/icon.svg`
. Para usar o seu:

```bash
./make-icon.sh caminho/do/logo.png          # PNG, SVG ou .icns
./make-icon.sh logo.png OutroNome           # muda também o nome exibido
```

A 3.0.0 do terminal-notifier **removeu a flag `-appIcon`** — o ícone sempre vem do
bundle que envia. Então a única via é um bundle próprio: o `make-icon.sh` copia o app,
gera o `.icns` com `sips`/`iconutil`, ajusta `CFBundleIconFile`, `CFBundleName` e
`CFBundleIdentifier`, e re-assina ad-hoc. Só ferramentas nativas — **não precisa de
Xcode**, apesar de o `make icon` do upstream depender (aquele target compila o app;
aqui a gente reaproveita o já compilado).

O bundle id é **`io.github.fernandamsouza.gh-inbox`** — namespace próprio, não o do
terminal-notifier. O app é uma cópia derivada dele, mas identidade de bundle é do autor
original, não nossa. Quem fizer fork sobrescreve com `GH_INBOX_BUNDLE_BASE`.

Trocar o `CFBundleIdentifier` cria um app novo aos olhos do macOS, então a permissão é
pedida outra vez — e a entrada antiga fica órfã na lista de Notificações. Inofensiva,
só polui.

## Por que não é polling caro

`GET /notifications` com `If-Modified-Since`. Quando nada mudou o GitHub responde
**304, que não consome rate limit** — e o `x-poll-interval` que ele devolve é 60s,
exatamente a cadência do LaunchAgent. Medido: 3 polls consecutivos, rate limit
inalterado.

O scan de estado (3 queries GraphQL) roda a cada 10 ticks, porque **CI vermelho não
gera notificação no GitHub** — só aparece consultando estado.

## Evento não é estado

Uma notificação é um **evento**: "alguém pediu seu review às 19:19". A fila é
**estado**: "quem está pendente agora". Divergem muito — em uso real, **a maior parte
das notificações de review já não corresponde a nada pendente** quando você vai olhar,
porque pedido a time é reassignado, pedido é removido, PR é fechado.

Sem tratamento o banner te manda para PRs que já não são seus. Então antes de notificar
um `review_requested` o poller confere o PR: aberto, não-draft, e você ainda em
`requested_reviewers` (ou algum time ainda pedido — associação de time não é resolvível
barato, e aí ele erra para o lado de notificar). Num ciclo real isso descartou a
**maioria** dos eventos que chegaram.

Os descartados também entram no `notif-seen.json`. Sem isso voltariam a ser "novos" a
cada tick, para sempre.

## Histórico, e a pegadinha do `-group`

Cada evento vira um banner e uma entrada na Central de Notificações. Isso depende de um
detalhe contraintuitivo: a flag `-group` **remove as notificações antigas do mesmo
grupo** — parece agrupamento visual, é substituição. Um grupo fixo deixa uma entrada só
e destrói o histórico.

O projeto usa **grupo único por PR** (`ghinbox-<org>-<repo>-<num>`): o histórico
acumula, e um evento repetido no mesmo PR substitui apenas a própria entrada.

## O que aconteceu no seu PR

Uma notificação com reason `author` significa apenas "atividade no seu PR": approve,
changes-requested, comentário e push produzem o **mesmo** payload, porque o
`subject.title` é o título do PR, não o estado do review.

Então, para eventos `author`, o poller busca o último review de outra pessoa e rotula:
*aprovado*, *mudanças pedidas*, *comentário no review*, *review dispensado*. Custo: 1
chamada REST por evento `author`.

O bucket `PRONTO` cobre o outro lado: aprovado e verde não aparecia em lugar nenhum, e
é justamente o momento de agir.

## Sem dependência externa

O banner vem de um notificador próprio: **~120 linhas de Swift** sobre o
`UserNotifications` da Apple, em `notifier/notifier.swift`. Nada de terceiro.

O `notifier/build.sh` compila com o `swiftc` do Command Line Tools e monta o app
bundle com `sips`, `iconutil`, `PlistBuddy` e `codesign` — tudo nativo do macOS. O
binário sai **universal (arm64 + x86_64)**, então o mesmo build serve Apple Silicon e
Intel.

```bash
./notifier/build.sh                     # ícone de assets/icon.svg, nome gh-inbox
./notifier/build.sh caminho/logo.png    # PNG, SVG ou .icns
./notifier/build.sh logo.png OutroNome  # muda também o nome exibido
```

Flags que ele aceita: `-title`, `-subtitle`, `-message`, `-open URL`, `-group ID`,
`-list [ID|ALL]`, `-remove ID|ALL`. Sem argumentos ele roda como *handler* — é assim
que o macOS o reabre quando alguém clica na notificação, e é onde a URL é aberta.

O `terminal-notifier` continua sendo aceito como **fallback**: se ele existir e o
notificador próprio não, o poller usa ele. As flags que usamos são iguais nos dois.

Sobre "nativo": **não existe** opção que dispense a permissão. O `osascript` funciona
sem pedir uma própria — e por isso a Apple não lhe dá handler de clique. Qualquer app
que poste notificação precisa de consentimento do usuário, o nosso incluído.

## Problemas conhecidos

**Não vi prompt de permissão nenhum.** Ajustes do Sistema > Notificações > gh-inbox.
O `tccutil reset` que a mensagem de erro sugere **falha** nesta configuração.

**`terminal-notifier` retorna "Notifications are not allowed" e nada explica.** Não
chame o `$(brew --prefix)/bin/terminal-notifier` — é um *shim* em shell que mascara o
erro real. O executável de dentro do `.app` dá a mensagem acionável. O poller já usa o
caminho certo.

**Instalei via brew e ele nunca pede permissão, só retorna `exit 3`.** O Launch Services
**não indexa `/opt/homebrew/Cellar`**, e o macOS não deixa app desconhecido pedir
autorização de notificação. Por isso o instalador copia o `.app` para `~/Applications` e
roda `lsregister`.

**Botão de ação no banner não serve.** O `-action` do terminal-notifier existe, mas: os
botões ficam escondidos atrás de um hover no macOS, exigem um processo vivo esperando o
clique, e o retorno medido foi `@ACTIONCLICKED` — **sem dizer qual botão**. Para ação no
banner o que funciona é `-open` (abre URL) ou `-execute` (roda comando), os dois no
clique do corpo, e portanto competindo pelo mesmo clique. Este projeto usa `-open`.

**A primeira chamada de um bundle id novo bloqueia** até o prompt ser respondido —
medido em 2 minutos. No instalador isso é desejável (a pessoa está ali). No poller não:
ele roda com teto de 5s e cai no `osascript`, senão seguraria o lock e emperraria o
ciclo.

**Não notifica com o Mac dormindo.** `StartInterval` do launchd não acorda a máquina; o
poll acontece quando ela volta.

## Limitações conhecidas

- **macOS only** — depende de launchd e osascript.
- **`/inbox` exige o Claude Code.** Sem ele, poller e banner funcionam; a fila fica no
  `gh-inbox list`.
- **Uma org por instalação** (`GH_INBOX_ORG`, fixado no plist).
- **Pedido a time erra para o lado de notificar** — associação de time não é resolvível
  barato, então ainda chega algum banner de PR que não é seu.
- **Testado em Apple Silicon apenas.** O código trata Intel (`/usr/local`) e ausência de
  brew, mas esses caminhos nunca foram exercitados.
- **Sem testes automatizados.**

## Remover

```bash
./uninstall.sh            # preserva o estado
./uninstall.sh --purge    # apaga estado e logs também
```

Não desinstala o `terminal-notifier` — pode ser usado por outra coisa. Para tirar:
`brew uninstall terminal-notifier`.

## Licença

MIT — veja [LICENSE](LICENSE).

O `terminal-notifier`, única dependência, também é MIT. O app derivado que o
`make-icon.sh` monta é uma cópia local do binário dele com ícone e bundle id próprios;
nada é redistribuído.
