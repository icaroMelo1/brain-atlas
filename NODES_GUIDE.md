# Brain Atlas — Guide for AI Assistants

This guide explains how to create and maintain `nodes.json` — the file that drives the Brain Atlas visualization. Read this before generating or editing any nodes.

---

## What Brain Atlas Does

Brain Atlas renders a 3D brain-shaped knowledge graph. Each node represents a tool, agent, skill, MCP integration, or domain area that you use when working. When Claude uses a tool, the corresponding node lights up in real time via a PostToolUse hook → SSE bridge.

The graph is divided into anatomical regions:

| Region | Maps to | Node categories |
|---|---|---|
| `cerebellum` | Orchestration layer — skills, agents | `skill`, `agent` |
| `cerebrum-L` | Left hemisphere — project A or context A | any category |
| `cerebrum-R` | Right hemisphere — project B or context B | any category |
| `brainstem` | Integration layer — MCPs, external tools | `mcp` |

You can use the regions however you want. The anatomical split is just visual.

---

## nodes.json Structure

```json
{
  "nodes": [...],
  "links": [...],
  "satellites": {...},
  "toolMap": [...]
}
```

### `nodes` — the graph nodes

Each entry represents one named node:

```json
{
  "name": "Node Name",
  "region": "cerebellum",
  "hub": true,
  "category": "agent",
  "weight": 0.88,
  "desc": "Short description shown in tooltip",
  "md": "relative/path/to/file.md"
}
```

| Field | Type | Description |
|---|---|---|
| `name` | string | Unique display name. Used as the identifier in toolMap and links. |
| `region` | string | `cerebellum`, `cerebrum-L`, `cerebrum-R`, or `brainstem` |
| `hub` | boolean | Hub nodes are placed near the center and get more connections |
| `category` | string | Controls color. Built-in: `agent`, `skill`, `mcp`, `dsg`, `cast`. Add your own freely. |
| `weight` | float 0–1 | Visual size and activation intensity. Hub nodes ≥ 0.8, leaf nodes 0.4–0.7 |
| `desc` | string | Tooltip description (optional) |
| `md` | string | Relative path from `sourceDir` to the .md file to open on click (optional) |

**Color palette** (customizable in `CAT_COLOR` in `Cerebro.html`):
- `agent` → amber `#fbbf24`
- `skill` → purple `#c084fc`
- `mcp` → orange `#fb923c`
- `dsg` → blue `#4cc3ff`
- `cast` → green `#7dd4a4`
- `session` → silver `#e2e8f0` (auto-injected, do not add manually)

### `links` — explicit connections

Array of `[nameA, nameB]` pairs. The renderer also auto-generates kNN proximity links, so you only need to list meaningful semantic connections.

```json
"links": [
  ["Hub Node", "Specialist A"],
  ["Hub Node", "Specialist B"],
  ["Specialist A", "Specialist B"]
]
```

### `satellites` — domain knowledge fragments

Satellites are small dimmer nodes that orbit a parent node. They show domain keywords — things the node "knows about". They are clickable but don't open files; clicking them shows a panel explaining they belong to the parent.

```json
"satellites": {
  "Node Name": ["keyword1", "keyword2", "keyword3"],
  "Another Node": ["alpha", "beta", "gamma"]
}
```

Keep satellite lists to 4–9 entries per node. Too many crowds the visualization.

### `toolMap` — hook routing rules

Controls which node lights up when Claude uses a specific tool. Evaluated in order; first match wins.

```json
"toolMap": [
  { "type": "mcp_prefix",    "match": "mcp__obsidian__",       "node": "MCP Obsidian" },
  { "type": "file_path",     "match": "/backend/",              "node": "Backend Node" },
  { "type": "skill",         "match": "commit",                 "node": "/commit" },
  { "type": "agent_keyword", "match": "task-worker",            "node": "Task Worker" },
  { "type": "agent_default",                                     "node": "Center Node" }
]
```

| Rule type | Triggers when | `match` value |
|---|---|---|
| `mcp_prefix` | Tool name starts with `match` | MCP tool prefix e.g. `mcp__obsidian__` |
| `file_path` | Read/Edit/Write/Bash tool has `match` in file path or command | Path fragment e.g. `/src/` |
| `skill` | `Skill` tool called with `skill == match` | Skill name without `/` prefix |
| `agent_keyword` | `Agent` tool called; `subagent_type + description` contains `match` (lowercase) | Keyword |
| `agent_default` | `Agent` tool called with no other match | *(no match field needed)* |

---

## How to Design Your Graph

### Step 1 — Identify your center

Pick one node to be the "center" — the main orchestrating agent or persona. This node:
- Gets `hub: true`, `weight: 1.0`
- Should be in `cerebellum` (or wherever feels right)
- Should link to everything it can activate

If you don't want a center node, just skip it — the graph works without one.

### Step 2 — Map your contexts/projects

Each major project or domain area becomes a region. For example:
- A work project → `cerebrum-L`
- A personal project → `cerebrum-R`
- Or split by tech stack, client, team, etc.

### Step 3 — Add specialists / sub-agents

Each specialist or focused agent is a leaf node inside its region. Link it to its tech lead / hub.

### Step 4 — Map your tools

- Claude Code skills → `cerebellum`, category `skill`
- Claude subagents → `cerebellum`, category `agent`
- MCP servers → `brainstem`, category `mcp`

### Step 5 — Add toolMap rules

For every node that should light up from a Claude tool use, add a toolMap rule. Order matters: more specific rules go first.

### Step 6 — Add satellites

For each node, list 4–8 domain keywords. Think: "what concepts does this node know about?"

---

## Example: Minimal Setup (single project, no center)

```json
{
  "nodes": [
    { "name": "Backend",  "region": "cerebrum-L", "hub": true,  "category": "backend", "weight": 0.85, "desc": "NestJS API" },
    { "name": "Frontend", "region": "cerebrum-R", "hub": true,  "category": "frontend","weight": 0.80, "desc": "React App" },
    { "name": "Database", "region": "cerebrum-L", "hub": false, "category": "backend", "weight": 0.65, "desc": "PostgreSQL" },
    { "name": "MCP Files","region": "brainstem",  "hub": false, "category": "mcp",     "weight": 0.55, "desc": "File access MCP" }
  ],
  "links": [
    ["Backend", "Database"],
    ["Frontend", "Backend"]
  ],
  "satellites": {
    "Backend":  ["NestJS", "REST", "JWT", "TypeORM"],
    "Frontend": ["React", "Vite", "TailwindCSS"],
    "Database": ["PostgreSQL", "migration", "index"]
  },
  "toolMap": [
    { "type": "mcp_prefix", "match": "mcp__files__", "node": "MCP Files" },
    { "type": "file_path",  "match": "/backend/",    "node": "Backend" },
    { "type": "file_path",  "match": "/frontend/",   "node": "Frontend" }
  ]
}
```

## Example: With center node (orchestrating agent)

```json
{
  "nodes": [
    { "name": "Claudicaro", "region": "cerebellum", "hub": true,  "category": "agent", "weight": 1.0, "desc": "Main orchestrating persona" },
    { "name": "/commit",    "region": "cerebellum", "hub": true,  "category": "skill", "weight": 0.88, "desc": "Full commit + PR flow", "md": "tools/skills/commit.md" }
  ],
  "links": [
    ["Claudicaro", "/commit"]
  ],
  "satellites": {
    "Claudicaro": ["bypass", "plan", "session", "memory"],
    "/commit":    ["branch", "push", "PR", "staged"]
  },
  "toolMap": [
    { "type": "skill",         "match": "commit",   "node": "/commit" },
    { "type": "agent_default",                       "node": "Claudicaro" }
  ]
}
```

---

## Questions to ask the user when setting up

If generating nodes.json for a new user, ask:

1. **What projects or contexts do you work on?** (These become regions or node groups)
2. **Do you want a "center" node?** (An agent/persona that orchestrates everything — gets placed in cerebellum with weight 1.0 and links to everything)
3. **What Claude Code skills do you use?** (e.g., `/commit`, `/plan-executor` — these become skill nodes in cerebellum)
4. **What MCP servers do you have installed?** (These become brainstem nodes)
5. **Do you have custom subagents?** (These become agent nodes in cerebellum)
6. **What are the main domain areas inside each project?** (These become specialist leaf nodes)
7. **Where are your .md files?** (For the `md` field and `sourceDir` in config.json)

---

## config.json

Created on first run via the browser setup screen. Format:

```json
{
  "sourceDir": "~/Documents/notes",
  "bridgePort": 8766,
  "httpPort": 8765
}
```

- `sourceDir`: absolute path (~ expanded) to the folder containing your .md files. The HTTP server serves this directory; `md` field paths in nodes are relative to it.
- `bridgePort`: port for the bridge SSE server (default 8766)
- `httpPort`: port for the HTTP static file server (default 8765)

`config.json` is gitignored — it's per-machine configuration, never committed.

---

## hook.py — toolMap integration

`hook.py` is registered as a Claude Code PostToolUse hook. On every tool use, it:
1. Reads `nodes.json` for the `toolMap`
2. Matches the tool name/input against toolMap rules
3. POSTs `{ node, tool, ts }` to `http://localhost:{bridgePort}/event`
4. The bridge fans this out via SSE to the browser, which triggers `triggerThought()`

The hook is registered in `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "python3 ~/projetos/pessoal/brain-atlas/hook.py" }] }]
  }
}
```
