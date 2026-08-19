#!/usr/bin/env bash
# =============================================================================
# Bootstrap do ambiente Claude Code — LEVEL UP / Illumi / Infinity.ai
#
# Instala o Claude Code pelo instalador nativo da Anthropic e replica o
# ambiente padrão usado no host de dev do LEVEL FLOW:
#   - binário claude (native installer, ~/.local/bin/claude)
#   - dependências de runtime dos MCPs (node/npx, uv/uvx, git)
#   - MCPs (escopo user): playwright, context7, magic, sequential-thinking,
#     tavily, morphllm, serena  (pencil só se o binário local existir)
#   - skills globais (~/.claude/skills): context7-mcp, docker-expert,
#     frontend-design, java-architect, senior-qa, springboot-security
#   - regra global (~/.claude/rules/context7.md)
#   - settings (~/.claude/settings.json): modelo, tema, plugins habilitados
#   - plugin codex@openai-codex (marketplace openai/codex-plugin-cc)
#   - plugin langchain-skills@langchain-skills (marketplace
#     langchain-ai/langchain-skills) — 22 skills oficiais de LangChain,
#     LangGraph e Deep Agents, usadas no runtime Python de agentes
#
# Uso:
#   ./install.sh [--project-dir <dir>] [--model <modelo>] [--force-mcp] [--update] [--no-start]
#
# Segredos: exporte CONTEXT7_API_KEY e TAVILY_API_KEY, ou crie um arquivo
# secrets.env ao lado deste script (ver secrets.env.example). Sem a chave,
# o MCP correspondente é pulado com aviso (dá para rodar de novo depois).
#
# No final, persiste ~/.local/bin no ~/.bashrc (shells futuras) e, se houver
# TTY interativo, já inicia o claude no --project-dir (pule com --no-start).
# Idempotente: pode rodar mais de uma vez; só sobrescreve MCPs com --force-mcp.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/payload"

PROJECT_DIR="${PROJECT_DIR:-$HOME}"        # alvo do morphllm (fast-apply)
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-fable-5[1m]}"
FORCE_MCP=0
UPDATE_CLAUDE=0
NO_START=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --model)       CLAUDE_MODEL="$2"; shift 2 ;;
    --force-mcp)   FORCE_MCP=1; shift ;;
    --update)      UPDATE_CLAUDE=1; shift ;;
    --no-start)    NO_START=1; shift ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -25; exit 0 ;;
    *) echo "argumento desconhecido: $1 (use --help)"; exit 1 ;;
  esac
done

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[aviso]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[erro]\033[0m %s\n' "$*"; exit 1; }

# --- segredos ----------------------------------------------------------------
if [[ -f "$SCRIPT_DIR/secrets.env" ]]; then
  # shellcheck disable=SC1091
  set -a; . "$SCRIPT_DIR/secrets.env"; set +a
  log "secrets.env carregado"
fi
CONTEXT7_API_KEY="${CONTEXT7_API_KEY:-}"
TAVILY_API_KEY="${TAVILY_API_KEY:-}"

[[ -d "$PAYLOAD_DIR" ]] || die "payload/ não encontrado ao lado do script — copie a pasta claude-bootstrap inteira, não só o install.sh"

# --- dependências de runtime ---------------------------------------------------
ensure_node() {
  if command -v node >/dev/null 2>&1; then
    local major; major="$(node -e 'console.log(process.versions.node.split(".")[0])')"
    if (( major >= 18 )); then log "node $(node --version) OK"; return; fi
    warn "node $(node --version) é antigo (<18); tentando atualizar"
  fi
  if command -v apt-get >/dev/null 2>&1 && [[ "$(id -u)" == "0" ]]; then
    log "instalando Node.js 22 (NodeSource)"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  else
    die "node >=18 não encontrado e não consigo instalar automaticamente (sem apt/root). Instale Node.js e rode de novo."
  fi
}

ensure_uv() {
  if command -v uvx >/dev/null 2>&1; then log "uv OK ($(uv --version 2>/dev/null || echo instalado))"; return; fi
  log "instalando uv (astral.sh)"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  command -v uvx >/dev/null 2>&1 || die "uv instalado mas uvx não está no PATH"
}

ensure_git() {
  command -v git >/dev/null 2>&1 && { log "git OK"; return; }
  if command -v apt-get >/dev/null 2>&1 && [[ "$(id -u)" == "0" ]]; then
    apt-get install -y git
  else
    die "git não encontrado — necessário para serena e plugins"
  fi
}

command -v curl >/dev/null 2>&1 || die "curl é pré-requisito deste script"
ensure_git
ensure_node
ensure_uv

# --- Claude Code (instalador nativo da Anthropic) ------------------------------
export PATH="$HOME/.local/bin:$PATH"
if command -v claude >/dev/null 2>&1 && [[ "$UPDATE_CLAUDE" == "0" ]]; then
  log "claude já instalado: $(claude --version)"
else
  log "instalando Claude Code (instalador nativo)"
  curl -fsSL https://claude.ai/install.sh | bash
  command -v claude >/dev/null 2>&1 || die "instalação do claude falhou (confira ~/.local/bin no PATH)"
  log "claude instalado: $(claude --version)"
fi

# garante ~/.local/bin no PATH das próximas sessões de shell (sem precisar
# "reiniciar" nada agora: dentro deste script o PATH já foi exportado acima)
RC_FILE="$HOME/.bashrc"
if ! grep -qs '\.local/bin' "$RC_FILE" 2>/dev/null; then
  printf '\n# claude-bootstrap: binário do Claude Code\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC_FILE"
  log "PATH (~/.local/bin) persistido em $RC_FILE"
else
  log "PATH já persistido em $RC_FILE"
fi

# --- skills e regras globais ----------------------------------------------------
log "instalando skills globais em ~/.claude/skills"
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/rules"
for skill in "$PAYLOAD_DIR/skills"/*/; do
  name="$(basename "$skill")"
  rm -rf "$HOME/.claude/skills/$name"
  cp -r "$skill" "$HOME/.claude/skills/$name"
  log "  skill: $name"
done
cp "$PAYLOAD_DIR/rules/"*.md "$HOME/.claude/rules/"
log "regras globais copiadas (context7.md)"

# --- settings.json (merge preservando o que já existir) -------------------------
log "aplicando ~/.claude/settings.json (merge)"
CLAUDE_MODEL="$CLAUDE_MODEL" python3 - <<'PYEOF'
import json, os, pathlib
path = pathlib.Path.home() / ".claude" / "settings.json"
current = {}
if path.exists():
    try: current = json.loads(path.read_text())
    except Exception: pass
desired = {
    "model": os.environ["CLAUDE_MODEL"],
    "theme": "dark",
    "tui": "fullscreen",
    "enabledPlugins": {
        "codex@openai-codex": True,
        "langchain-skills@langchain-skills": True,
    },
    "extraKnownMarketplaces": {
        "openai-codex": {"source": {"source": "github", "repo": "openai/codex-plugin-cc"}},
        "langchain-skills": {
            "source": {"source": "github", "repo": "langchain-ai/langchain-skills"}
        },
    },
}
# merge raso: o desejado vence, mas dicts de 1º nível são combinados
for k, v in desired.items():
    if isinstance(v, dict) and isinstance(current.get(k), dict):
        current[k] = {**current[k], **v}
    else:
        current[k] = v
current.setdefault("permissions", {}).setdefault("allow", [])
if "mcp__pencil" not in current["permissions"]["allow"]:
    current["permissions"]["allow"].append("mcp__pencil")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(current, indent=2, ensure_ascii=False) + "\n")
print(f"  settings.json gravado (modelo: {os.environ['CLAUDE_MODEL']})")
PYEOF

# --- MCPs (escopo user) ----------------------------------------------------------
add_mcp() { # add_mcp <nome> <json>
  local name="$1" json="$2"
  if claude mcp get "$name" >/dev/null 2>&1; then
    if [[ "$FORCE_MCP" == "1" ]]; then
      claude mcp remove "$name" -s user >/dev/null 2>&1 || true
    else
      log "  mcp $name já configurado (use --force-mcp para reescrever)"
      return
    fi
  fi
  claude mcp add-json "$name" "$json" -s user >/dev/null
  log "  mcp $name configurado"
}

log "configurando MCPs (escopo user)"
add_mcp playwright '{"type":"stdio","command":"npx","args":["-y","@playwright/mcp@latest"]}'
add_mcp sequential-thinking '{"type":"stdio","command":"npx","args":["-y","@modelcontextprotocol/server-sequential-thinking"]}'
add_mcp magic '{"type":"stdio","command":"npx","args":["@21st-dev/magic"]}'
add_mcp serena '{"type":"stdio","command":"uvx","args":["--from","git+https://github.com/oraios/serena","serena","start-mcp-server","--context","ide-assistant"]}'
add_mcp morphllm "$(python3 -c "import json,sys;print(json.dumps({'type':'stdio','command':'npx','args':['@morph-llm/morph-fast-apply',sys.argv[1]]}))" "$PROJECT_DIR")"

if [[ -n "$CONTEXT7_API_KEY" ]]; then
  add_mcp context7 "$(python3 -c "import json,sys;print(json.dumps({'type':'stdio','command':'npx','args':['-y','@upstash/context7-mcp@latest','--api-key',sys.argv[1]]}))" "$CONTEXT7_API_KEY")"
else
  warn "CONTEXT7_API_KEY ausente — MCP context7 pulado (exporte a chave e rode de novo)"
fi

if [[ -n "$TAVILY_API_KEY" ]]; then
  add_mcp tavily "$(python3 -c "import json,sys;print(json.dumps({'type':'stdio','command':'npx','args':['-y','mcp-remote','https://mcp.tavily.com/mcp/?tavilyApiKey=\${TAVILY_API_KEY}'],'env':{'TAVILY_API_KEY':sys.argv[1]}}))" "$TAVILY_API_KEY")"
else
  warn "TAVILY_API_KEY ausente — MCP tavily pulado (exporte a chave e rode de novo)"
fi

PENCIL_BIN="$HOME/.pencil/mcp/visual_studio_code/out/mcp-server-linux-x64"
if [[ -x "$PENCIL_BIN" ]]; then
  add_mcp pencil "$(python3 -c "import json,sys;print(json.dumps({'command':sys.argv[1],'args':['--app','visual_studio_code','--agent','claudeCodeCLI']}))" "$PENCIL_BIN")"
else
  warn "Pencil não instalado nesta máquina — MCP pencil pulado (instale o app Pencil se precisar de .pen)"
fi

# --- plugins ------------------------------------------------------------------------
# install_plugin <plugin@marketplace> <repo-github-do-marketplace> <rótulo>
install_plugin() {
  local plugin="$1" repo="$2" label="$3"
  log "instalando plugin $plugin"
  claude plugin marketplace add "$repo" --scope user >/dev/null 2>&1 || true
  # -y é exigido quando stdout não é TTY (provisionamento headless)
  if claude plugin install "$plugin" --scope user -y >/dev/null 2>&1; then
    log "  $label instalado"
  else
    warn "instalação de $label falhou — rode manualmente: claude plugin install $plugin"
  fi
}

install_plugin codex@openai-codex openai/codex-plugin-cc "plugin codex"
install_plugin langchain-skills@langchain-skills langchain-ai/langchain-skills \
  "skills oficiais LangChain (22)"

# --- resumo -------------------------------------------------------------------------
echo
log "Bootstrap concluído. Estado dos MCPs:"
claude mcp list || true
echo
log "Lembretes:"
echo "  - morphllm apontado para: $PROJECT_DIR (reconfigure com --project-dir --force-mcp em outro projeto)."
echo "  - O plugin codex requer o Codex CLI autenticado ('codex login') para funcionar."
echo "  - As 22 skills LangChain custam ~2.1k tokens sempre-carregados; atualize com 'claude plugin marketplace update langchain-skills'."
echo "  - Shells novas já acham 'claude' no PATH ($RC_FILE); na shell atual use: export PATH=\"\$HOME/.local/bin:\$PATH\""
echo

# início automático: só em terminal interativo (TTY); em provisionamento
# headless (cloud-init, CI, ssh sem -t) apenas informa o próximo passo
if [[ "$NO_START" == "1" ]]; then
  log "Pronto. Inicie com: claude  (login na primeira execução)"
elif [[ -t 0 && -t 1 ]]; then
  log "Iniciando o Claude Code (login na primeira execução)…"
  cd "$PROJECT_DIR"
  exec "$HOME/.local/bin/claude"
else
  warn "Sem TTY interativo — não dá para iniciar o claude daqui. Rode: claude"
fi
