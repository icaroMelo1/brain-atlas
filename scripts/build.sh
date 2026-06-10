#!/usr/bin/env bash
set -euo pipefail

SRC="brain-atlas.html"
OUT_DIR="site"

mkdir -p "$OUT_DIR"

# Inject <base href="/brain/"> into <head> and add intro-gate before </body>
python3 - "$SRC" "$OUT_DIR/index.html" << 'PYEOF'
import sys, re

src_path, out_path = sys.argv[1], sys.argv[2]
html = open(src_path, encoding='utf-8').read()

# Inject base tag after <head>
html = re.sub(r'(<head[^>]*>)', r'\1\n  <base href="/brain/">', html, count=1, flags=re.IGNORECASE)

# Intro-gate block
intro_gate = '''
<div id="intro-gate">
  <div class="ig-inner">
    <div class="ig-pulse"></div>
    <div class="ig-label">// visualização interativa</div>
    <h1 class="ig-title">Brain&nbsp;Atlas</h1>
    <p class="ig-sub">
      Um mapa vivo do conhecimento: cada <b>nó</b> é uma ideia, cada <b>conexão</b> um elo.
      A rede acende em tempo real enquanto o raciocínio acontece.
    </p>
    <button id="ig-start" class="ig-btn">Iniciar visualização →</button>
    <div class="ig-hint">arraste para girar · scroll para zoom · clique num nó para abrir</div>
  </div>
</div>
<style>
#intro-gate{position:fixed;inset:0;z-index:9999;display:grid;place-items:center;
  background:radial-gradient(ellipse 60% 50% at 50% 38%, rgba(76,195,255,0.10), transparent 70%), #0B0F19;
  font-family:'Inter',system-ui,sans-serif;color:#cdd6f4;
  transition:opacity .6s ease, visibility .6s ease;}
#intro-gate.hide{opacity:0;visibility:hidden;}
.ig-inner{max-width:560px;text-align:center;padding:0 28px;}
.ig-pulse{width:64px;height:64px;margin:0 auto 26px;border-radius:50%;
  background:radial-gradient(circle,#79e8ff,#4cc3ff 55%,transparent 72%);
  box-shadow:0 0 40px rgba(76,195,255,.6);animation:igp 2.4s ease-in-out infinite;}
@keyframes igp{0%,100%{transform:scale(1);opacity:.85}50%{transform:scale(1.18);opacity:1}}
.ig-label{font-family:'JetBrains Mono',monospace;font-size:12px;color:#6b7593;letter-spacing:.04em;margin-bottom:14px;}
.ig-title{font-size:clamp(40px,8vw,68px);font-weight:600;letter-spacing:-.03em;margin:0;
  background:linear-gradient(180deg,#fff,#9fd9ff);-webkit-background-clip:text;background-clip:text;color:transparent;}
.ig-sub{margin:20px auto 0;font-size:17px;line-height:1.65;color:#9fb0d0;max-width:460px;}
.ig-sub b{color:#cdd6f4;font-weight:600;}
.ig-btn{margin-top:34px;font-family:'JetBrains Mono',monospace;font-size:14px;font-weight:600;
  color:#06121c;background:#4cc3ff;border:none;border-radius:10px;padding:14px 26px;cursor:pointer;
  box-shadow:0 8px 30px rgba(76,195,255,.35);transition:transform .15s,filter .15s;}
.ig-btn:hover{transform:translateY(-2px);filter:brightness(1.08);}
.ig-hint{margin-top:26px;font-family:'JetBrains Mono',monospace;font-size:11px;color:#3a4361;}
</style>
<script>
(function(){
  var g=document.getElementById('intro-gate'),b=document.getElementById('ig-start');
  if(b)b.addEventListener('click',function(){g.classList.add('hide');
    setTimeout(function(){g.style.display='none';},650);});
})();
</script>
'''

html = re.sub(r'(</body>)', intro_gate + r'\1', html, count=1, flags=re.IGNORECASE)

open(out_path, 'w', encoding='utf-8').write(html)
print(f"Built {out_path}")
PYEOF

cp nodes.json "$OUT_DIR/nodes.json"
echo "Build complete: $OUT_DIR/"
