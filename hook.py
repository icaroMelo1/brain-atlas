#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.error
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()


def _load_nodes() -> dict:
    try:
        return json.loads((SCRIPT_DIR / "nodes.json").read_text(encoding="utf-8"))
    except Exception:
        return {}


def _bridge_port() -> int:
    try:
        cfg = json.loads((SCRIPT_DIR / "config.json").read_text(encoding="utf-8"))
        return int(cfg.get("bridgePort", 8766))
    except Exception:
        return 8766


def resolve_node(data: dict, tool_map: list) -> str | None:
    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("command") or ""

    agent_default = None

    for rule in tool_map:
        rule_type = rule.get("type")
        match = rule.get("match", "")
        node = rule.get("node")

        if rule_type == "mcp_prefix":
            if tool_name.startswith(match):
                return node

        elif rule_type == "file_path":
            if tool_name in ("Read", "Edit", "Write", "Bash") and match in path:
                return node

        elif rule_type == "skill":
            if tool_name == "Skill":
                skill = (tool_input.get("skill") or "").lstrip("/")
                if skill == match:
                    return node

        elif rule_type == "agent_keyword":
            if tool_name == "Agent":
                combined = (
                    (tool_input.get("subagent_type") or "") + " " +
                    (tool_input.get("description") or "")
                ).lower()
                if match in combined:
                    return node

        elif rule_type == "agent_default":
            if tool_name == "Agent":
                agent_default = node

    if agent_default and tool_name == "Agent":
        return agent_default

    return None


def send_event(node: str, tool: str, port: int):
    payload = json.dumps({"node": node, "tool": tool, "ts": int(time.time())}).encode("utf-8")
    req = urllib.request.Request(
        f"http://localhost:{port}/event",
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
        nodes_data = _load_nodes()
        tool_map = nodes_data.get("toolMap", [])
        node = resolve_node(data, tool_map)
        if node:
            send_event(node, data.get("tool_name", ""), _bridge_port())
    except Exception:
        pass
    sys.exit(0)
