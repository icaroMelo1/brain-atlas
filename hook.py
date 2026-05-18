#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.error
import time

TOOL_NODE_MAP = {
    "mcp__obsidian__": "MCP Obsidian",
    "mcp__context7__": "MCP Context7",
    "mcp__claude-in-chrome__": "MCP Chrome",
    "mcp__claude_ai_Google_Drive__": "MCP Google Drive",
    "mcp__linkedin__": "MCP LinkedIn",
    "mcp__mermaid__": "MCP Mermaid",
    "mcp__plugin_atlassian_atlassian__": "MCP Atlassian",
}

FILE_TOOLS = {"Read", "Edit", "Write", "Bash"}

SKILL_NODE_MAP = {
    "commit": "/commit",
    "commit-qa": "/commit-qa",
    "plan-executor": "/plan-executor",
    "plan-analyzer": "/plan-analyzer",
    "review-diff": "/review-diff",
    "compact-v2": "/compact-v2",
    "pr-review": "/pr-review",
}


def resolve_node(data):
    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}

    # MCP prefix match
    for prefix, node in TOOL_NODE_MAP.items():
        if tool_name.startswith(prefix):
            return node

    # File/bash tools — detect by path
    if tool_name in FILE_TOOLS:
        path = tool_input.get("file_path") or tool_input.get("command") or ""
        if "/dsg/" in path:
            return "Tech Lead DSG"
        if "/cast/" in path:
            return "Tech Lead CAST"
        return None

    # Agent tool
    if tool_name == "Agent":
        subagent = tool_input.get("subagent_type") or ""
        description = tool_input.get("description") or ""
        combined = (subagent + " " + description).lower()
        if "task-worker" in combined:
            return "Task Worker"
        return "Claudicaro"

    # Skill tool
    if tool_name == "Skill":
        skill = tool_input.get("skill") or ""
        # normalize: strip leading slash
        skill_key = skill.lstrip("/")
        if skill_key in SKILL_NODE_MAP:
            return SKILL_NODE_MAP[skill_key]
        return None

    return None


def send_event(node, tool):
    payload = json.dumps({
        "node": node,
        "tool": tool,
        "ts": int(time.time()),
    }).encode("utf-8")

    req = urllib.request.Request(
        "http://localhost:8766/event",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=0.5):
            pass
    except (urllib.error.URLError, OSError):
        pass


if __name__ == "__main__":
    try:
        raw = sys.stdin.read()
        data = json.loads(raw)
        node = resolve_node(data)
        if node:
            send_event(node, data.get("tool_name", ""))
    except Exception:
        pass
    sys.exit(0)
