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

### Instructions for every repo

A per-repo file cannot say *"you are running unattended on a Pi, never touch
lockfiles"* without that being copied into every checkout and drifting. So there
is a machine-level file too, read from the first of:

```
$AGENT_GLOBAL_INSTRUCTIONS
~/.config/pi5-agent/AGENTS.md
/etc/my-pi5-setup/AGENTS.md
```

It is prepended, and the repo's own file comes after it — so where the two
disagree, the nearer file is the one the model reads last and follows. Its cap
is smaller on purpose (1200 chars, `AGENT_GLOBAL_INSTRUCTIONS_MAX_CHARS`): the
repo file knows the build command and the layout, and the two share one 8K
context. Both files are named in the run output, so you can see what the model
actually got.

Keep it to things true of every repo on the machine:

```markdown
- You are running unattended on a Raspberry Pi. Nothing interactive.
- Make the smallest change that addresses the issue. Do not refactor around it.
- If the issue needs a fact you have no tool to obtain, call cannot_complete.
- Never edit lockfiles, CI config, or anything under .github/.
```

**opencode gets it too.** It does not read this file - it reads the project's
`AGENTS.md` and its own global config - so an escalated run has the contents
passed to it in the prompt instead. One file, both harnesses.

## Modes

```sh
pi5-agent --selftest                 # four-stage check: endpoint, model, inference, tools
pi5-agent "summarise open issues"    # read-only question
pi5-agent --issue 12 --allow-write   # work one issue end to end
pi5-agent --queue --allow-write      # work every issue labelled agent:queued
```

`--issue` seeds the whole workflow: read the issue, find the code, branch, edit,
commit, open a PR, print the review diff, stop.

## Tools

| Tool | Needs `--allow-write` |
| --- | --- |
| `gh_issue_list`, `gh_issue_view` | no |
| `list_files`, `read_file` (paged), `search_files` | no |
| `git_diff` | no |
| `cannot_complete` | no |
| `git_branch`, `append_file`, `replace_in_file`, `write_file`, `git_commit` | yes |
| `gh_pr_create`, `gh_issue_comment` | yes, and prompts |

### Reading a file that does not fit

`read_file` returns a page, not a file:

```
[README.md lines 780-786 of 786]
state/            gitignored: detection results and backups
...
[12 more lines. Read them with read_file(path="README.md", offset=787), or use
search_files to jump straight to the line you need.]
```

Whole-file reads were a dead end. Every tool result is cut at
`AGENT_MAX_TOOL_CHARS`, so a 32 KB README arrived as its first 12% with no way
to reach the rest, and an issue about its **last** lines was unachievable by any
model: `search_files` would report line 783, `read_file` would hand back line 1
onwards, and the loop re-read the same head until the repeat guard stopped it.

`offset` is what closes that loop — grep gives the line number, `offset` goes
there. The page is trimmed to fit the result budget before the footer is added,
so the instruction for getting the next page is never the part that gets cut.

The text itself carries **no line-number prefixes**, deliberately.
`replace_in_file` needs the old string verbatim, and a model that copies
`783: foo` back into it produces a match that exists nowhere. Line numbers come
from `search_files`; exact text comes from here.

### Editing without rewriting

Three write tools, in the order you should reach for them:

| Tool | For |
| --- | --- |
| `append_file` | adding to the end of a file |
| `replace_in_file` | changing part of one — give the old text verbatim |
| `write_file` | a new or tiny file only |

`write_file` needs the model to emit the **complete** file. For anything large
that is impossible on an 8K context, and it fails silently — an empty reply, no
error. The other two let the model name only the part it is changing, which is
what makes a real file editable at this size.

`replace_in_file` refuses a string that matches zero times or more than once,
and says which, rather than guessing at the intended one.

### Stopping is an outcome

`cannot_complete(reason)` ends the run and posts the model's reason on the
issue, verbatim.

It exists because the alternative exits are both bad. A model that cannot do the
job can only write prose, and prose is indistinguishable from a model that
merely failed to answer — the queue is left guessing, which is why its failure
comment used to *infer* a reason from whether a branch existed. And a small model
asked for something it cannot obtain does not usually stop at all: it invents a
plausible answer, which arrives as a plausible-looking PR. A wrong PR costs more
review than an honest stop.

So the issue gets this instead of a bare `agent:failed`:

> The local agent stopped and said why:
>
> > The issue asks which model wrote the line. Nothing I can call reports that.
>
> No pull request was opened, and opencode was not tried…

**A stated reason skips the escalation.** Escalation answers the *harness's*
limits — opencode edits by patch where `write_file` rewrites whole files — and
it runs [the same local model](#handing-an-issue-to-opencode). It cannot know
anything this loop did not. Retrying "I have no way to find this out" spends up
to an hour of the board to reach the same wall, so a give-up goes straight to
`agent:failed` with the reason attached. Add `agent:opencode` by hand if you
want the wider harness tried anyway.

What it does **not** do is guarantee the stop happens. Nothing enforces the
call, and a small model's characteristic failure is not stopping — it asserts
success. This makes an honest stop legible; it does not make a dishonest finish
impossible. That is what your review of the pull request is for.

### Why so few tools

Tool-choice accuracy falls off sharply as the menu grows, and a 4B model is
choosing. A dozen it picks correctly beats forty it guesses between. This is the
same reason an MCP server is the wrong shape here.

## Safety model

The boundary is not "read nothing" — it has to write to be useful. It is
**nothing lands anywhere you have to undo**:

- `write_file` refuses until `git_branch` has run. Every edit is on an `agent/`
  branch.
- `git_commit` refuses on the default branch.
- **PRs open ready for review**, and opening one prompts. Nothing merges.
  `AGENT_PR_DRAFT=1` restores drafts, which is the only mechanical brake on a
  repo without branch protection.
- **Every PR and commit is signed** with the machine and model that wrote it —
  a `Written by pi5-agent on <host> using <model>` footer, and an `Agent:`
  trailer on the commit so a squash merge keeps the attribution.
- **Closing issues is not a tool.** The agent cannot close one; merging its PR
  can, via a `Closes #N` the harness adds rather than trusting the model to
  write. `AGENT_PR_CLOSES=0` downgrades it to `Refs #N` — no close on merge —
  which is the safer setting while you still expect the model to drift.
- **The branch name comes from the issue number**, not the model. `agent/issue-N`
  is the queue's only idempotence key.
- **A run never hands back a dirty checkout.** Unfinished edits are committed on
  the agent branch as `wip:`; the default branch comes back clean.
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
over, and commits and opens the PR afterwards. opencode edits files; it
never picks the branch, never touches the default branch, and never opens
the pull request itself.

Rule of thumb: default loop for one-line and single-file changes, `agent:opencode`
for anything touching a larger file or more than one.

**It also escalates on its own.** If the built-in loop produces no PR, the queue
resets the checkout and tries opencode before marking the issue failed
(`AGENT_ESCALATE=0` to stop that).

Under the timer this needs `opencode` on the **service's** PATH, not yours.
systemd does not read a login profile, so a binary in `~/.opencode/bin` is
invisible to it and `shutil.which` finds nothing — the escalation is then skipped
on every failure, silently. `make queue-timer` resolves opencode as your user at
install time and writes its directory into `queue.env`; re-run it after
installing or moving opencode. When it is missing the failure comment on the
issue says so rather than leaving you to wonder. This is a second approach rather than a
retry: the built-in loop's characteristic failure is a whole-file rewrite it
cannot produce, which is precisely what patch-based editing avoids.

The PR comment says when a change came from the escalation, and `agent:failed`
now means both approaches were tried.

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `AGENT_BASE_URL` | `http://127.0.0.1:11434/v1` | Ollama's OpenAI-compatible endpoint |
| `AGENT_MODEL_ID` | *(whatever is loaded)* | pin a specific model |
| `AGENT_MAX_TURNS` | `20` | tool-call rounds before giving up |
| `AGENT_MAX_TOOL_CHARS` | `4000` | truncation per tool result |
| `AGENT_READ_LINES` | `200` | lines per `read_file` page |
| `AGENT_TIMEOUT` | `900` | seconds to wait for a reply |
| `AGENT_INSTRUCTIONS_MAX_CHARS` | `3000` | truncation for the repo's AGENTS.md |
| `AGENT_GLOBAL_INSTRUCTIONS` | *(see above)* | machine-level instructions file |
| `AGENT_GLOBAL_INSTRUCTIONS_MAX_CHARS` | `1200` | truncation for that file |
| `AGENT_SHOW_THINKING` | `0` | `1` keeps a reasoning model's narration |
| `AGENT_TOOL_MODE` | `auto` | `native`, `text`, or `auto` (probe then fall back) |
| `AGENT_BRANCH_PREFIX` | `agent/` | branch namespace |
| `AGENT_LABEL` | `agent:queued` | queue trigger |
| `AGENT_PR_DRAFT` | `0` | `1` opens pull requests as drafts again |
| `AGENT_PR_CLOSES` | `1` | `0` links with `Refs #N` so merging does not close |

## Speed

A reasoning model on a Pi 5 generates a few tokens a second, and it spends some
of them thinking before it answers. A single reply can take minutes; the first
one also waits for the weights to load from the SSD.

`AGENT_TIMEOUT` defaults to 900 seconds for that reason. If you hit it, either
raise it or use a model that does not reason before answering — `hermes3:3b` is
both smaller and more direct, which is why it is the fallback.

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

## Can it loop forever?

No. Every loop is bounded:

| Loop | Bound |
| --- | --- |
| tool-call turns | `AGENT_MAX_TURNS`, default 20 |
| nudges when no tool is used | 2 |
| issues per repo per run | 20 |
| repeated identical tool call | warned at 3, run stops at 5 |
| every `git`/`gh` call | 120s timeout |
| an `opencode` handoff | 3600s timeout |
| a model request | 600s timeout |
| the queue timer | `TimeoutStartSec=3600`, and systemd will not start a second run while one is going |

The repeat check matters more than the turn limit in practice. A small model
that gets stuck re-reading one file would otherwise spend all twenty turns doing
it — half an hour of this board achieving nothing. It is told the result will
not change, and the run ends if it keeps going.

The only unbounded loop in the repo is the Telegram bridge's polling loop, which
is a daemon and meant to be.

## Secret scanning

Before committing, the agent scans the **staged diff** for secret-shaped
strings — GitHub tokens, private key headers, AWS key ids, Slack and Telegram
tokens, JWTs — and refuses the commit if it finds any, unstaging the change and
saying what it saw.

Three deliberate choices:

- **Added lines only.** What is already in a file is not this commit's doing,
  and flagging it would block every future commit to that file.
- **After `git add`, before `git commit`.** The staged diff is exactly what
  would be recorded.
- **Narrow patterns.** A check that cries wolf gets switched off, and then it
  protects nothing.

This is not agent-specific insurance — committing a secret is a risk with any
contributor. It is here because the agent commits, and a secret in git history
is the one mistake a later revert does not undo. If you make a repo public,
enable GitHub's push protection as well; it catches the same shapes server-side
and does not depend on this running.

## Working on itself

The agent can be pointed at `my-pi5-setup`, so it can edit its own code. That is
allowed, because the guard is the same one as everywhere else: the work lands on
an `agent/` branch as a pull request, and nothing reaches `main` without you merging
it. Banning it outright would also stop you asking the agent to improve its own
scripts, which is a reasonable thing to want.

**The residual risk is the checkout, not the merge.** After editing
`bin/pi5-agent` the tree is sitting on that branch, and the *next* invocation
would run the unreviewed version. So a run that touched this repo switches back
to the default branch when it finishes. The work is committed on the branch and
pushed, so nothing is lost:

```sh
git switch agent/issue-12    # to inspect it
```

`make queue` already did this between issues; now single `--issue` runs do too.

If you want belt and braces anyway, `AGENT_PROTECTED_PATHS` refuses writes to
matching paths in this repo — `bin/,lib/,scripts/,apps/,Makefile` is the
sensible value. Empty by default. For an `opencode` handoff the same list is
checked after the fact, since opencode edits files itself.

## Limits worth knowing before you rely on it

- **Large files need `append_file` or `replace_in_file`.** `write_file` is a
  whole-file rewrite and will not work on anything substantial at this context
  size. The system prompt says so, but a model can still choose badly.
- **A 4B model gets argument names wrong**, occasionally rewrites more than it
  needed to, and sometimes stalls. `agent:failed` is the honest signal for
  "too vague or too large" — treat it as calibration, not a bug.
- **Tool calling may not parse at all** depending on the runtime. `make llm-test`
  stage 4 tells you. If it fails, chat and `opencode` still work.

## Driving it from Telegram(Work In Progress)

`apps/telegram.sh` installs a bridge that runs this agent as a subprocess. It is
a trigger, not a chat interface: `/work <repo>` runs the queue there, and no
message reaches the model as free text. Same rails - signed PRs, writes
behind `TELEGRAM_ALLOW_WRITE=1`. See the README for setup.

## Writing issues it can actually do

Small, specific, one file where possible. State the file path if you know it.
"Fix the typo in the README heading" lands. "Refactor the auth layer" will not.
