# pi5-agent

A single-file agent that drives the local model through `gh` and `git`. Stdlib
Python, no pip dependencies, ~500 lines. Drop it into any repo's harness.

## What spec does it follow?

**The OpenAI chat-completions tool-calling format, with a fallback of its own.**
`tools` goes out, `tool_calls` comes back, results return as `role: "tool"`
messages.

When the runtime cannot produce `tool_calls` — common, since parsing a model's
tool format lags its release — the agent switches to a text protocol instead of
giving up:

```
TOOL: read_file
ARGS: {"path": "README.md"}
```

The model writes those two lines, the agent parses them and feeds the result
back as ordinary text. Every tool, guard rail and the queue work identically;
only the transport changes. `AGENT_TOOL_MODE=auto` probes native once per run
and falls back, reusing that first reply if it already came back in the text
format rather than paying for another round.

This is how agents worked before native tool calling existed, and on a small
model it is often the more reliable of the two — a two-line format is easier to
produce correctly than a JSON schema the runtime must also parse.

It is deliberately **not**:

| | Why not |
| --- | --- |
| Claude Code's agent spec | Different runtime; no subagents, hooks or plugins here |
| MCP | A server's tool menu is dozens of entries. Tool-choice accuracy collapses at that size on a 4B model — see [why the menu is short](#why-eleven-tools) |
| Agent Skills (`SKILL.md`) | Progressive disclosure assumes context to spend. There is 8K here, and tool results have to fit in it |

The one convention it does follow is **`AGENTS.md`**.

## AGENTS.md

Put project instructions in `AGENTS.md` at the repo root and the agent prepends
them to its system prompt. `CLAUDE.md` and `.github/AGENTS.md` work as
fallbacks, in that order.

This is the [cross-tool convention](https://agents.md/) — `opencode` reads it
too, along with 20-odd other agents — so one file steers everything you run on
this Pi. Plain Markdown, no schema.

It is **truncated to 3000 characters** (`AGENT_INSTRUCTIONS_MAX_CHARS`). Context
is the scarce resource here; instructions that crowd out tool results make the
agent worse, not better. Keep it to build commands, conventions and gotchas.

## Modes

```sh
pi5-agent --selftest                 # four-stage check: endpoint, model, inference, tools
pi5-agent "summarise open issues"    # read-only question
pi5-agent --issue 12 --allow-write   # work one issue end to end
pi5-agent --queue --allow-write      # work every issue labelled agent:queued
```

`--issue` seeds the whole workflow: read the issue, find the code, branch, edit,
commit, open a draft PR, print the review diff, stop.

## Tools

| Tool | Needs `--allow-write` |
| --- | --- |
| `gh_issue_list`, `gh_issue_view` | no |
| `list_files`, `read_file`, `search_files` | no |
| `git_diff` | no |
| `git_branch`, `write_file`, `git_commit` | yes |
| `gh_pr_create`, `gh_issue_comment` | yes, and prompts |

### Why eleven tools

Tool-choice accuracy falls off sharply as the menu grows, and a 4B model is
choosing. Eleven it picks correctly beats forty it guesses between. This is the
same reason an MCP server is the wrong shape here.

## Safety model

The boundary is not "read nothing" — it has to write to be useful. It is
**nothing lands anywhere you have to undo**:

- `write_file` refuses until `git_branch` has run. Every edit is on an `agent/`
  branch.
- `git_commit` refuses on the default branch.
- PRs are **always drafts**, and opening one prompts.
- **Closing issues is not a tool.** Review and close are yours.
- Refuses to start on a dirty tree (`--force` overrides), so the review diff is
  the agent's work alone.
- `git` and `gh` run with fixed argv, never a shell string.
- File access is confined to the checkout; `.git/` internals are off limits.

Local edits on a throwaway branch do not prompt — they are reviewable and
revertible. Only the two outward-facing actions ask first.

## Queue

```sh
make labels                       # create agent:queued / agent:done / agent:failed
make queue                        # list what it would work
make queue ARGS=--allow-write     # work them
```

Idempotence comes from the label swap plus the branch: an issue whose
`agent/issue-N` branch exists on `origin` counts as attempted and is skipped, so
a rerun after a crash does not duplicate work. Each issue starts from a clean
default branch.

### Unattended

`make queue-timer` installs a systemd timer that polls every checkout under
`GITHUB_DIR`. Requires `QUEUE_AUTO=1` — it writes without supervision, so it is
never implied. `bin/pi5-queue-all` is what it runs: it checks the issue count
with `gh` before waking the model, and reports any PR links over Telegram if
that bridge is configured.

### Handing an issue to opencode

Label an issue **both** `agent:queued` and `agent:opencode` and the queue
delegates it to `opencode run --auto` instead of the built-in loop.

Same model — the win is the harness. `write_file` here replaces a whole file,
which costs a full read plus a full write against 8K of context; opencode edits
by patch. That is the difference between "works on small files" and "works on
real ones".

The guard rails do not change: this agent creates the branch before handing
over, and commits and opens the draft PR afterwards. opencode edits files; it
never picks the branch, never touches the default branch, and never opens
anything but a draft.

Rule of thumb: default loop for one-line and single-file changes, `agent:opencode`
for anything touching a larger file or more than one.

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `AGENT_BASE_URL` | `http://127.0.0.1:11434/v1` | Ollama's OpenAI-compatible endpoint |
| `AGENT_MODEL_ID` | *(whatever is loaded)* | pin a specific model |
| `AGENT_MAX_TURNS` | `20` | tool-call rounds before giving up |
| `AGENT_MAX_TOOL_CHARS` | `4000` | truncation per tool result |
| `AGENT_INSTRUCTIONS_MAX_CHARS` | `3000` | truncation for AGENTS.md |
| `AGENT_SHOW_THINKING` | `0` | `1` keeps a reasoning model's narration |
| `AGENT_TOOL_MODE` | `auto` | `native`, `text`, or `auto` (probe then fall back) |
| `AGENT_BRANCH_PREFIX` | `agent/` | branch namespace |
| `AGENT_LABEL` | `agent:queued` | queue trigger |

## Reasoning models

Qwen3.5 and similar narrate before answering — `<think>…</think>` blocks, or a
`Thinking Process:` preamble. Three things suppress it:

1. `"think": false` on the request, which Ollama honours for models that
   support it and anything else ignores.
2. A system prompt rule against narrating.
3. Stripping whatever still arrives, by pattern.

The stripping applies to the **conversation history**, not just the display.
That is the part that matters: on an 8K context, several turns of narration
crowd out the tool results the model needs to do the job. An unclosed `<think>`
is left alone, since that means the answer never arrived and hiding it would
just look like a hang.

`AGENT_SHOW_THINKING=1` keeps it, which is occasionally useful for working out
why the model chose a tool.

## Limits worth knowing before you rely on it

- **`write_file` replaces whole files.** No patches. Reliable for a small model,
  but a large file costs a full read plus a full write against 8K of context.
  Focused issues on small files work; sprawling refactors do not.
- **A 4B model gets argument names wrong**, occasionally rewrites more than it
  needed to, and sometimes stalls. `agent:failed` is the honest signal for
  "too vague or too large" — treat it as calibration, not a bug.
- **Tool calling may not parse at all** depending on the runtime. `make llm-test`
  stage 4 tells you. If it fails, chat and `opencode` still work.

## Driving it from Telegram

`apps/telegram.sh` installs a bridge that runs this agent as a subprocess. It is
a trigger, not a chat interface: `/work <repo>` runs the queue there, and no
message reaches the model as free text. Same rails - draft PRs only, writes
behind `TELEGRAM_ALLOW_WRITE=1`. See the README for setup.

## Writing issues it can actually do

Small, specific, one file where possible. State the file path if you know it.
"Fix the typo in the README heading" lands. "Refactor the auth layer" will not.
