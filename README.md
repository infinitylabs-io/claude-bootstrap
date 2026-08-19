# claude-bootstrap — ambiente Claude Code padrão em qualquer infra

Sobe uma máquina nova (VPS, container, servidor) com o ambiente Claude Code
completo em um comando: binário via **instalador nativo da Anthropic**, MCPs,
skills globais, regras e plugins (codex + skills oficiais LangChain) — tudo
idempotente e reproduzível.

## Uso

```bash
# 1. clonar na máquina alvo
git clone https://github.com/infinitylabs-io/claude-bootstrap.git
cd claude-bootstrap

# 2. preencher os segredos (opcional — sem eles, context7/tavily são pulados)
cp secrets.env.example secrets.env   # editar com as chaves context7/tavily

# 3. rodar (root ou não; com root ele instala node/git via apt se faltar)
./install.sh --project-dir /caminho/do/projeto
```

No final o script persiste o PATH no `~/.bashrc` e, se o terminal for
interativo, **já inicia o claude** no diretório do projeto (o login acontece
na primeira execução; ou exporte `ANTHROPIC_API_KEY`). Em provisionamento
headless use `--no-start`. `codex login` à parte, se for usar o plugin codex.

> Alternativa sem clone: `scp -r` da pasta inteira a partir de uma máquina já
> configurada — aí o `secrets.env` preenchido viaja junto (ele é gitignored,
> nunca sobe pro repo).

## Flags

| Flag | Efeito |
|---|---|
| `--project-dir <dir>` | Diretório que o MCP morphllm (fast-apply) vai editar. Default: `$HOME`. |
| `--model <id>` | Modelo default do settings.json. Default: `claude-fable-5[1m]`. |
| `--force-mcp` | Reescreve MCPs já configurados (ex.: trocar o project-dir do morphllm). |
| `--update` | Reroda o instalador nativo mesmo com claude já presente. |
| `--no-start` | Não inicia o claude no final (útil em provisionamento automatizado). |

## O que é instalado

- **Claude Code** — `curl -fsSL https://claude.ai/install.sh | bash` (instalador
  nativo da Anthropic, binário em `~/.local/bin/claude`).
- **MCPs (escopo user)** — playwright, context7*, magic (21st.dev),
  sequential-thinking, tavily*, morphllm (fast-apply), serena (LSP simbólico);
  pencil só se o app Pencil já existir na máquina. (*exigem chave em `secrets.env`.)
- **Skills globais** (`~/.claude/skills`) — context7-mcp, docker-expert,
  frontend-design, java-architect, senior-qa, springboot-security
  (conteúdo em `payload/skills/`).
- **Regra global** — `~/.claude/rules/context7.md` (sempre buscar docs de
  lib/framework via context7 em vez de responder de memória).
- **Settings** (`~/.claude/settings.json`) — modelo, tema dark, tui fullscreen,
  plugins habilitados. Merge não-destrutivo: preserva o que já existir.
- **Plugins** — dois, ambos escopo user:
  - `codex@openai-codex` (marketplace `openai/codex-plugin-cc`).
  - `langchain-skills@langchain-skills` (marketplace
    `langchain-ai/langchain-skills`, MIT) — as **22 skills oficiais** da
    LangChain para LangChain/LangGraph/Deep Agents, alvo `>=1.0,<2.0` (API
    `create_agent`, sem `AgentExecutor`/`LLMChain` legado). Custam ~2,1k tokens
    sempre-carregados; o corpo de cada skill só entra quando dispara.
    Atualizar: `claude plugin marketplace update langchain-skills`.

## Pré-requisitos que o script resolve sozinho (se rodar como root em Debian/Ubuntu)

Node.js ≥18 (NodeSource 22.x), git, uv/uvx (astral.sh). Sem root/apt, ele
aborta com instrução do que instalar manualmente. `curl` é o único
pré-requisito absoluto.

## Manter o payload em dia

Quando a máquina de referência ganhar/perder skills ou regras globais:

```bash
./refresh-payload.sh   # recopia ~/.claude/skills e ~/.claude/rules para payload/
git commit -am "payload: atualiza skills/regras" && git push
```

Skills que vêm de **plugin** (as 22 da LangChain) não passam pelo `payload/` —
elas moram em `~/.claude/plugins/` e são reinstaladas do marketplace pelo
`install.sh`. Para adicionar outro plugin, use a função `install_plugin` no
`install.sh` e acrescente a entrada em `enabledPlugins`/`extraKnownMarketplaces`
no bloco de settings.

## O que NÃO é coberto (de propósito)

Autenticação (login é manual), `CLAUDE.md` de projetos (vivem em cada repo),
instalação do app Pencil, e `settings.local.json` por projeto.

Idempotente: rodar de novo não duplica nada; MCPs existentes só mudam com
`--force-mcp`.
