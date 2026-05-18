#!/usr/bin/env bash
# brain-atlas start
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"

# Read config.json if it exists, else use defaults
if [ -f "$CONFIG" ]; then
  SOURCE_DIR=$(python3 -c "import json,pathlib; c=json.load(open('$CONFIG')); print(pathlib.Path(c.get('sourceDir','$SCRIPT_DIR')).expanduser())")
  BRIDGE_PORT=$(python3 -c "import json; c=json.load(open('$CONFIG')); print(c.get('bridgePort',8766))")
  HTTP_PORT=$(python3 -c "import json; c=json.load(open('$CONFIG')); print(c.get('httpPort',8765))")
else
  SOURCE_DIR="$SCRIPT_DIR"
  BRIDGE_PORT=8766
  HTTP_PORT=8765
fi

BRIDGE_LOG="$SCRIPT_DIR/bridge.log"
HTTP_LOG="$SCRIPT_DIR/http.log"

echo "Parando processos anteriores..."
pkill -f "bridge.py" 2>/dev/null || true
pkill -f "http.server $HTTP_PORT" 2>/dev/null || true
sleep 0.5

echo "Subindo Brain Atlas Bridge na porta $BRIDGE_PORT..."
python3 "$SCRIPT_DIR/bridge.py" > "$BRIDGE_LOG" 2>&1 &
echo "  Bridge PID: $!"

echo "Subindo HTTP server na porta $HTTP_PORT para $SOURCE_DIR..."
python3 -m http.server $HTTP_PORT --directory "$SOURCE_DIR" > "$HTTP_LOG" 2>&1 &
echo "  HTTP PID: $!"

echo "Aguardando bridge..."
for i in $(seq 1 10); do
  if curl -sf "http://localhost:$BRIDGE_PORT/health" > /dev/null 2>&1; then
    echo "  Bridge OK ✓"
    break
  fi
  sleep 0.4
done

URL="http://localhost:$HTTP_PORT/brain-atlas.html"
echo "Abrindo $URL ..."
open "$URL" 2>/dev/null || xdg-open "$URL" 2>/dev/null || echo "  Abra manualmente: $URL"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Brain Atlas rodando                             ║"
echo "║  Browser  → http://localhost:$HTTP_PORT/brain-atlas.html ║"
echo "║  Bridge   → http://localhost:$BRIDGE_PORT/health         ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Para parar: pkill -f bridge.py && pkill -f 'http.server $HTTP_PORT'"
