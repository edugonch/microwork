#!/usr/bin/env bash
# install.sh — Instala/actualiza microbreak en ~/.local/bin (macOS)
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- colores ---
GRN='\033[1;32m' YLW='\033[1;33m' CYN='\033[1;36m' RED='\033[1;31m' RST='\033[0m'
ok()   { echo -e "${GRN}[✓]${RST} $*"; }
info() { echo -e "${CYN}[•]${RST} $*"; }
warn() { echo -e "${YLW}[!]${RST} $*"; }
die()  { echo -e "${RED}[✗]${RST} $*" >&2; exit 1; }

echo ""
echo -e "${GRN}MicroBreak T2D — Instalador macOS${RST}"
echo "=================================="
echo ""

# --------------------------------------------------------------------------
# 1. Prerequisitos
# --------------------------------------------------------------------------
if ! command -v zsh >/dev/null 2>&1; then
  die "Zsh no encontrado. Este script requiere Zsh."
fi

PYTHON_OK=0
if command -v python3 >/dev/null 2>&1; then
  PY_VER=$(python3 --version 2>&1)
  ok "Python encontrado: $PY_VER"
  PYTHON_OK=1
else
  warn "Python 3 no encontrado — la integración IA no estará disponible."
  warn "Para habilitarla: brew install python"
fi

# --------------------------------------------------------------------------
# 2. Instalar archivos
# --------------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"

# Instalar con ambos nombres para compatibilidad con aliases existentes
cp "$SCRIPT_DIR/microbreak.sh" "$INSTALL_DIR/microbreak.sh"
chmod +x "$INSTALL_DIR/microbreak.sh"
ln -sf "$INSTALL_DIR/microbreak.sh" "$INSTALL_DIR/microbreak"
ok "microbreak instalado en $INSTALL_DIR/microbreak.sh"
ok "symlink creado:  $INSTALL_DIR/microbreak → microbreak.sh"

if [[ "$PYTHON_OK" -eq 1 ]]; then
  cp "$SCRIPT_DIR/workout_ai.py" "$INSTALL_DIR/workout_ai.py"
  chmod +x "$INSTALL_DIR/workout_ai.py"
  ok "workout_ai.py instalado en $INSTALL_DIR/workout_ai.py"

  # Apuntar AI_PYTHON_SCRIPT al directorio de instalación
  # (workout_ai.py ya usa SCRIPT_DIR = dirname(__file__), así que config.json
  #  quedará en ~/.local/bin/config.json, que está en .gitignore del repo)
fi

# --------------------------------------------------------------------------
# 3. PATH
# --------------------------------------------------------------------------
SHELL_RC="$HOME/.zshrc"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  warn "$INSTALL_DIR no está en tu PATH."
  echo ""
  printf "  ¿Agregar automáticamente a %s? [s/N] " "$SHELL_RC"
  read -r answer
  if [[ "$answer" =~ ^[sS]$ ]]; then
    printf '\n# MicroBreak\n%s\n' "$PATH_LINE" >> "$SHELL_RC"
    ok "PATH actualizado en $SHELL_RC"
    warn "Ejecuta:  source $SHELL_RC   (o abre una terminal nueva)"
  else
    info "Agrega manualmente a $SHELL_RC:"
    echo "    $PATH_LINE"
  fi
else
  ok "$INSTALL_DIR ya está en PATH"
fi

# --------------------------------------------------------------------------
# 3b. Preservar / migrar aliases existentes
# --------------------------------------------------------------------------
SHELL_RC="$HOME/.zshrc"

# Detectar aliases que apuntaban a microbreak.sh o microbreak
EXISTING_ALIASES=$(grep -E "alias [a-zA-Z_-]+=.*(microbreak)" "$SHELL_RC" 2>/dev/null || true)

if [[ -n "$EXISTING_ALIASES" ]]; then
  echo ""
  info "Aliases de microbreak encontrados en $SHELL_RC:"
  echo "$EXISTING_ALIASES" | while IFS= read -r line; do
    echo "    $line"
  done
  ok "Siguen funcionando — microbreak.sh sigue en $INSTALL_DIR/microbreak.sh"
fi

# --------------------------------------------------------------------------
# 4. Configurar LLM (solo si Python disponible)
# --------------------------------------------------------------------------
if [[ "$PYTHON_OK" -eq 0 ]]; then
  echo ""
  ok "Instalación completa (sin IA — Python no disponible)"
  echo -e "\n  Para correr:  ${CYN}microbreak${RST}\n"
  exit 0
fi

CONFIG_FILE="$INSTALL_DIR/config.json"

# Crear config base si no existe
if [[ ! -f "$CONFIG_FILE" ]]; then
  python3 - "$CONFIG_FILE" <<'PYEOF'
import json, sys
from pathlib import Path
cfg = {
    "llm_provider": "anthropic",
    "api_keys": {},
    "providers": {
        "anthropic": {"model": "claude-sonnet-4-5"},
        "openai":    {"model": "gpt-4o-mini"},
        "together":  {"model": "meta-llama/Llama-3.3-70B-Instruct-Turbo",
                      "url": "https://api.together.xyz"},
        "ollama":    {"url": "http://localhost:11434", "model": "llama3.2"}
    }
}
Path(sys.argv[1]).write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
PYEOF
  info "config.json creado en $INSTALL_DIR"
fi

echo ""
echo "Providers de IA disponibles:"
echo "  anthropic  — Claude  (console.anthropic.com)"
echo "  openai     — GPT-4o  (platform.openai.com)"
echo "  together   — Llama/Mixtral open-source (api.together.xyz)"
echo "  ollama     — Local, sin costo ni internet"
echo "  skip       — Sin IA por ahora"
echo ""
printf "¿Qué provider quieres usar? [anthropic]: "
read -r provider
provider="${provider:-anthropic}"

if [[ "$provider" == "skip" ]]; then
  ok "Omitiendo configuración de IA. Puedes configurarla editando:"
  echo "    $CONFIG_FILE"
else
  # Actualizar provider en config
  python3 - "$CONFIG_FILE" "$provider" <<'PYEOF'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
cfg = json.loads(p.read_text())
cfg["llm_provider"] = sys.argv[2]
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
PYEOF
  ok "Provider configurado: $provider"

  # Pedir API key (excepto Ollama que es local)
  if [[ "$provider" != "ollama" ]]; then
    case "$provider" in
      anthropic) KEY_LABEL="ANTHROPIC_API_KEY" ;;
      openai)    KEY_LABEL="OPENAI_API_KEY" ;;
      together)  KEY_LABEL="TOGETHER_API_KEY" ;;
      *)         KEY_LABEL="${provider^^}_API_KEY" ;;
    esac

    # Verificar si ya hay una key guardada
    EXISTING_KEY=$(python3 - "$CONFIG_FILE" "$provider" <<'PYEOF'
import json, sys
from pathlib import Path
cfg = json.loads(Path(sys.argv[1]).read_text())
key = cfg.get("api_keys", {}).get(sys.argv[2], "")
print("exists" if key else "")
PYEOF
)

    if [[ "$EXISTING_KEY" == "exists" ]]; then
      ok "API key para '$provider' ya guardada en config.json"
      printf "  ¿Reemplazarla? [s/N] "
      read -r replace
      [[ "$replace" =~ ^[sS]$ ]] || { echo ""; ok "Manteniendo key existente."; provider="skip_key"; }
    fi

    if [[ "$provider" != "skip_key" ]]; then
      echo ""
      printf "  Ingresa tu %s (oculto): " "$KEY_LABEL"
      read -rs api_key
      echo ""
      if [[ -n "$api_key" ]]; then
        # Pasar key via variable de entorno para no exponerla en la línea de comando
        WORKOUT_NEW_KEY="$api_key" python3 - "$CONFIG_FILE" "$provider" <<'PYEOF'
import json, os, sys
from pathlib import Path
p = Path(sys.argv[1])
cfg = json.loads(p.read_text())
cfg.setdefault("api_keys", {})[sys.argv[2]] = os.environ["WORKOUT_NEW_KEY"]
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
PYEOF
        ok "API key guardada en $CONFIG_FILE"
      else
        info "Sin key — microbreak te la pedirá la primera vez que lo corras."
      fi
    fi
  else
    info "Ollama es local, no requiere API key."
    info "Asegúrate de tener Ollama corriendo: https://ollama.com"
  fi
fi

# --------------------------------------------------------------------------
# 5. Resumen
# --------------------------------------------------------------------------
echo ""
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
ok "¡Instalación completa!"
echo ""
echo -e "  Correr:          ${CYN}microbreak${RST}"
echo -e "  Modo test:       ${CYN}microbreak --test${RST}"
echo -e "  Sin IA:          ${CYN}microbreak --no-ai${RST}"
echo -e "  Refrescar IA:    ${CYN}microbreak --refresh-ai${RST}"
echo -e "  Actualizar app:  ${CYN}cd $SCRIPT_DIR && ./install.sh${RST}"
echo ""
echo -e "  Config:   $CONFIG_FILE"
echo -e "  Sesiones: $HOME/.workout/sessions/"
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
