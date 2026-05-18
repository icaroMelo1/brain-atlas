# brain-atlas

Visualizador 3D interativo do conhecimento técnico, integrado em tempo real com o Claude Code.

## O que é

Um grafo cerebral 3D que mapeia agentes, skills, MCPs e domínios de conhecimento em regiões anatômicas do cérebro. Cada vez que o Claude usa uma ferramenta, o nó correspondente acende via SSE — o cérebro "pensa" em tempo real enquanto você trabalha.

## Estrutura

```
brain-atlas/
  Cerebro.html    # Visualizador 3D (React + Canvas2D)
  bridge.py       # Servidor SSE (porta 8766) — recebe eventos do hook e faz fan-out para o browser
  hook.py         # PostToolUse hook do Claude Code — mapeia tools → nós do grafo
  start.sh        # Sobe bridge + HTTP server + abre o browser
```

## Como usar

```bash
bash ~/projetos/pessoal/brain-atlas/start.sh
```

Abre `http://localhost:8765/Cerebro.html` com o bridge ativo.

### Parar

```bash
pkill -f bridge.py && pkill -f "http.server 8765"
```

## Integração com Claude Code

O hook `hook.py` precisa estar registrado no `~/.claude/settings.json`:

```json
{
  "PostToolUse": [
    {
      "matcher": "",
      "hooks": [{ "type": "command", "command": "python3 ~/projetos/pessoal/brain-atlas/hook.py", "async": true }]
    }
  ]
}
```

O visualizador serve os arquivos `.md` do vault Obsidian em `~/Documents/Obsidian/Dev/` via HTTP na porta 8765. Clicar em um nó abre o arquivo diretamente no leitor inline.

## Regiões cerebrais

| Região | Conteúdo |
|--------|----------|
| Hemisfério esquerdo | Domínio DSG (v1, v2, microserviços) |
| Hemisfério direito | Domínio CAST (TJAM — SGSA, Contratos, SisDoc) |
| Cerebelo | Skills e Agentes do Claude Code |
| Tronco encefálico | MCPs (Obsidian, Chrome, Context7...) |
