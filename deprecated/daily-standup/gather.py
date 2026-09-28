#!/usr/bin/env python3
"""Gather deterministic standup signal since a cutoff.

Scans Claude + Codex session logs and per-worktree git commits, prints one
compact markdown digest. The stochastic sources (Linear, Slack, GitHub PRs,
yesterday's standup) are gathered by the agent via MCP/gh, NOT here.

Usage:
  gather.py                # window = yesterday 00:00 local -> now
  gather.py --hours 30     # window = now-30h -> now
  gather.py --since 2026-07-14T09:00
"""
import argparse, glob, json, os, subprocess, sys
from datetime import datetime, timedelta, timezone

HOME = os.path.expanduser("~")
CLAUDE_GLOB = f"{HOME}/.claude/projects/*/*.jsonl"
CODEX_GLOB = f"{HOME}/.codex/sessions/**/*.jsonl"

# text prefixes that mark a wrapper/injected message, not a human prompt
NOISE_PREFIXES = (
    "<", "caveat:", "base directory for this skill", "you are working inside conductor",
    "system-reminder", "this session is being continued", "<system", "<command-",
    "respond directly to the user", "launching skill:",
)
NOISE_CONTAINS = ("system-reminder", "<command-name>", "recommended_plugins")


def parse_cutoff(args):
    if args.since:
        dt = datetime.fromisoformat(args.since)
        return dt if dt.tzinfo else dt.astimezone()
    if args.hours:
        return datetime.now(timezone.utc).astimezone() - timedelta(hours=args.hours)
    # default: yesterday 00:00 local
    now = datetime.now().astimezone()
    return (now - timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)


def to_dt(ts):
    if not ts:
        return None
    try:
        if isinstance(ts, (int, float)):
            return datetime.fromtimestamp(ts, timezone.utc).astimezone()
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).astimezone()
    except Exception:
        return None


def is_human(text):
    if not text:
        return False
    t = text.strip()
    low = t.lower()
    if len(t) < 3:
        return False
    if any(low.startswith(p) for p in NOISE_PREFIXES):
        return False
    if any(c in low[:200] for c in NOISE_CONTAINS):
        return False
    return True


def clean(text, n=180):
    t = " ".join(text.split())
    return t[:n] + ("…" if len(t) > n else "")


def extract_claude(path, cutoff):
    """Return (project, human_prompts[]) for msgs at/after cutoff."""
    project, prompts = None, []
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            o = json.loads(line)
        except Exception:
            continue
        if not project and o.get("cwd"):
            project = o["cwd"]
        if o.get("type") != "user":
            continue
        ts = to_dt(o.get("timestamp"))
        if ts and ts < cutoff:
            continue
        msg = o.get("message")
        if not isinstance(msg, dict) or msg.get("role") != "user":
            continue
        c = msg.get("content")
        if isinstance(c, list):
            # skip tool_result-only turns
            txt = " ".join(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
        elif isinstance(c, str):
            txt = c
        else:
            txt = ""
        if is_human(txt):
            prompts.append(clean(txt))
    return project, prompts


def extract_codex(path, cutoff):
    project, prompts = None, []
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            o = json.loads(line)
        except Exception:
            continue
        p = o.get("payload", {})
        if not project and isinstance(p, dict) and p.get("cwd"):
            project = p["cwd"]
        ts = to_dt(o.get("timestamp"))
        if ts and ts < cutoff:
            continue
        if isinstance(p, dict) and p.get("type") == "user_message":
            txt = p.get("message", "")
            # conductor preamble may prefix the real ask; keep tail after last sentinel
            for sep in ("</system_instruction>", "</system-reminder>"):
                if sep in txt:
                    txt = txt.split(sep)[-1]
            if is_human(txt):
                prompts.append(clean(txt))
    return project, prompts


def proj_label(cwd):
    if not cwd:
        return "(unknown)"
    parts = cwd.rstrip("/").split("/")
    return "/".join(parts[-2:]) if len(parts) >= 2 else parts[-1]


def scan(glob_pat, tag, cutoff, recursive=False):
    """Group touched sessions by project."""
    by_proj = {}
    for path in glob.glob(glob_pat, recursive=recursive):
        try:
            mtime = to_dt(os.path.getmtime(path))
        except OSError:
            continue
        if mtime < cutoff:
            continue
        proj, prompts = (extract_claude if tag == "claude" else extract_codex)(path, cutoff)
        key = proj_label(proj)
        rec = by_proj.setdefault(key, {"cwd": proj, "count": 0, "last": mtime, "prompts": []})
        rec["count"] += 1
        rec["last"] = max(rec["last"], mtime)
        rec["prompts"].extend(prompts)
    return by_proj


def git_commits(cwds, cutoff):
    """Commits authored by me since cutoff, deduped by hash across worktrees.

    Sibling worktrees share one object store, so --all would repeat the same
    commit under every worktree; global hash-dedup collapses that. First repo
    to report a hash owns it.
    """
    out, seen = {}, set()
    iso = cutoff.isoformat()
    for cwd in sorted(cwds):
        if not cwd or not os.path.isdir(cwd):
            continue
        try:
            email = subprocess.run(["git", "-C", cwd, "config", "user.email"],
                                   capture_output=True, text=True).stdout.strip()
            log = subprocess.run(
                ["git", "-C", cwd, "log", "--all", f"--since={iso}",
                 f"--author={email}", "--pretty=%h %s", "--no-merges", "-n", "50"],
                capture_output=True, text=True, timeout=15).stdout.strip()
        except Exception:
            continue
        fresh = []
        for line in log.splitlines():
            h = line.split(" ", 1)[0]
            if h in seen:
                continue
            seen.add(h)
            fresh.append(line)
        if fresh:
            out[proj_label(cwd)] = fresh
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float)
    ap.add_argument("--since")
    args = ap.parse_args()
    cutoff = parse_cutoff(args)

    claude = scan(CLAUDE_GLOB, "claude", cutoff)
    codex = scan(CODEX_GLOB, "codex", cutoff, recursive=True)

    cwds = {r["cwd"] for r in list(claude.values()) + list(codex.values()) if r["cwd"]}
    commits = git_commits(cwds, cutoff)

    buf = []
    P = buf.append
    raw_dir = os.path.join(HOME, ".claude", "standup", "raw",
                           datetime.now().strftime("%Y-%m-%d"))
    os.makedirs(raw_dir, exist_ok=True)

    P(f"## WINDOW\nsince {cutoff.isoformat()}  ->  now {datetime.now().astimezone().isoformat()}\n")

    def dump(title, data):
        P(f"## {title}")
        if not data:
            P("(none)\n")
            return
        for proj, rec in sorted(data.items(), key=lambda kv: kv[1]["last"], reverse=True):
            P(f"- {proj} | {rec['count']} session(s) | last {rec['last'].strftime('%m-%d %H:%M')}")
            seen = set()
            for pr in rec["prompts"][:4]:
                if pr in seen:
                    continue
                seen.add(pr)
                P(f"    · {pr}")
        P("")

    dump("CLAUDE SESSIONS", claude)
    dump("CODEX SESSIONS", codex)

    P("## GIT COMMITS (author=me, since cutoff)")
    if not commits:
        P("(none)")
    for proj, clines in commits.items():
        P(f"### {proj}")
        for l in clines:
            P(f"  {l}")

    text = "\n".join(buf)
    # dump digest to the audit trace dir so a later "why did it miss X?" can
    # check fetched-but-dropped vs never-fetched
    with open(os.path.join(raw_dir, "sessions.txt"), "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print(f"# RAW_DIR: {raw_dir}")
    print(text)


if __name__ == "__main__":
    main()
