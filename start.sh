#!/usr/bin/env bash
# brain-atlas start — sobe Bridge SSE + HTTP server + abre o browser
# Uso: bash start.sh  (a partir do diretório do projeto)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$HOME/Documents/Obsidian/Dev"
BRIDGE_PORT=8766
HTTP_PORT=8765
BRIDGE_LOG="$SCRIPT_DIR/bridge.log"
HTTP_LOG="$SCRIPT_DIR/http.log"

# ── Matar processos antigos ─────────────────────────────────────────────
echo "Parando processos anteriores..."
pkill -f "bridge.py" 2>/dev/null || true
pkill -f "http.server $HTTP_PORT" 2>/dev/null || true
sleep 0.5

# ── Subir bridge SSE ────────────────────────────────────────────────────
echo "Subindo Brain Atlas Bridge na porta $BRIDGE_PORT..."
python3 "$SCRIPT_DIR/bridge.py" > "$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!
echo "  Bridge PID: $BRIDGE_PID"

# ── Subir HTTP server para o vault ──────────────────────────────────────
echo "Subindo HTTP server na porta $HTTP_PORT para $VAULT_DIR..."
python3 -m http.server $HTTP_PORT --directory "$VAULT_DIR" > "$HTTP_LOG" 2>&1 &
HTTP_PID=$!
echo "  HTTP PID: $HTTP_PID"

# ── Aguardar bridge ficar pronto ────────────────────────────────────────
echo "Aguardando bridge..."
for i in $(seq 1 10); do
  if curl -sf "http://localhost:$BRIDGE_PORT/health" > /dev/null 2>&1; then
    echo "  Bridge OK ✓"
    break
  fi
  sleep 0.4
done

# ── Abrir browser ───────────────────────────────────────────────────────
URL="http://localhost:$HTTP_PORT/Cerebro.html"
echo "Abrindo $URL ..."
open "$URL" 2>/dev/null || xdg-open "$URL" 2>/dev/null || echo "  Abra manualmente: $URL"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Brain Atlas rodando                         ║"
echo "║  Browser  → http://localhost:$HTTP_PORT/Cerebro.html ║"
echo "║  Bridge   → http://localhost:$BRIDGE_PORT/health     ║"
echo "║  Logs     → $SCRIPT_DIR/*.log       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Para parar: pkill -f bridge.py && pkill -f 'http.server $HTTP_PORT'"
