# my-pi5-setup

Scripts that put my Raspberry Pi 5 back the way I like it after a reflash or an
OS change — and, above all, make it **dark everywhere, every time**.

Target: **Raspberry Pi OS 64-bit Desktop**, the image Raspberry Pi Imager offers
by default. Trixie (labwc) and Bookworm (wayfire) are both handled; the scripts
detect which one they are on. Boot is from USB, with an SSD on a HAT as extra
storage.

> **Run on Raspberry Pi OS Lite, 2026-06-18.** Start with `DRY_RUN=1 make all`,
> then `make doctor` for what actually works. LM Studio was tried and dropped —
> its installer would not run on a Lite image — so Ollama is the model server.

## Use it

This repo is **private**, so an anonymous `curl` gets a 404 page rather than a
script. The fix removes typing rather than adding it: after writing the image,
the boot partition mounts on your Mac. Copy two files onto it.

**On your Mac, right after Raspberry Pi Imager finishes:**

```sh
cp bootstrap.sh /Volumes/bootfs/
printf '%s' 'github_pat_xxxxx' > /Volumes/bootfs/gh-token
```

**On the Pi, first boot:**

```sh
bash /boot/firmware/bootstrap.sh
```

Short enough to type, no token in your shell history, nothing fetched before you
have credentials. It reads the token from `/boot/firmware/gh-token`, clones, and
runs `make all`.

Use a **fine-grained token, read-only, scoped to this repo alone**. It sits in
plain text on a FAT partition, so it should be worth as little as possible.

### If you would rather clone it yourself

Perfectly fine, and probably simplest if you are already SSHed in from your Mac.
GitHub accepts your username plus a personal access token as the password:

```sh
git clone https://github.com/antonioortegajr/my-pi5-setup.git
cd my-pi5-setup
DRY_RUN=1 make all      # read this first
make all
make llm-test           # is the local AI actually working?
make doctor             # everything else
```

Afterwards, check the remote did not keep your token:

```sh
git remote -v           # should NOT contain your token
```

If it does, scrub it — and consider switching to SSH, since `make ssd-state`
puts `~/.ssh` on the SSD and the key then survives every future reflash:

```sh
git remote set-url origin git@github.com:antonioortegajr/my-pi5-setup.git
```

### If you would rather curl it

```sh
GH_TOKEN=github_pat_xxxxx
curl -fsSL -H "Authorization: Bearer $GH_TOKEN" \
  https://raw.githubusercontent.com/antonioortegajr/my-pi5-setup/main/bootstrap.sh \
  | GH_TOKEN=$GH_TOKEN bash
```

The `-f` is not optional. Without it curl pipes GitHub's HTML error page into
bash, which reports a syntax error around line 9 instead of a failed download.

### Second reflash onward

If `make mirror` has run, the repo is already on the SSD and none of the above
applies — no token, no network:

```sh
sudo mount /dev/sda1 /mnt/ssd        # whatever lsblk shows
cd /mnt/ssd/my-pi5-setup && make all
```

### On pasting

Paste is not disabled — Raspberry Pi OS uses **`Ctrl+Shift+V`**, not `Ctrl+V`,
because `Ctrl+C` is SIGINT and cannot be a copy key. Right-click → Paste and
middle-click also work.

Easiest is not to fight it: **SSH in from your Mac** and paste there — by
password if you did not give Imager a key.

After the first run, `make dark` binds copy and paste explicitly in
`lxterminal.conf`.

### Afterwards

```sh
cd ~/my-pi5-setup
make all            # everything, idempotent - safe to rerun
make dark           # just re-assert the dark theme
DRY_RUN=1 make all  # show every change without making it
```

If there is no network but the SSD is mounted, the repo mirror is already there
and needs nothing downloaded:

```sh
cd /mnt/ssd/my-pi5-setup && make all
```

## Raspberry Pi OS Lite

Lite works, and for this particular setup it is arguably the better choice.
`00-preflight.sh` sets `HAS_DESKTOP=0` and the desktop scripts stand down on
their own — nothing to configure.

| Stage | On Lite |
| --- | --- |
| `dark-desktop` | skipped entirely — no GTK, no panel, no compositor |
| `dark-apps` | skipped — no Chromium, VS Code, Thonny or Geany |
| `dark-system` | greeter skipped (no lightdm); **console palette and `/etc/skel` still apply** |
| `dark-terminal` | **fully applies** — `LS_COLORS`, bat/fzf/tmux/neovim. LXTerminal is skipped |
| everything else | unchanged |

So `make dark` shrinks to the console and the shell, which on a headless box is
all "dark theme" can mean anyway.

**The upside is RAM.** The desktop costs roughly 0.5–1 GB, and on an 8 GB Pi with
no GPU to offload to, that is memory the model could be using. Every part of
what this repo builds is headless already: the Ollama server, Open WebUI
browsed from another machine, and `pi5-agent` over SSH. None of it needs a
screen attached to the Pi.

**Two things to watch:**

- LM Studio was the one component that did not survive a minimal image: its
  installer failed on Lite, which is why Ollama is now the only model server.
  Ollama is a static binary plus a systemd unit, with far less to go wrong.
- Lite has less preinstalled in general. `bootstrap.sh` installs `git` and `curl`
  if they are missing, and `BASE_PACKAGES` covers the rest.

## Targets

| Target | What it does |
| --- | --- |
| `make all` | preflight → network → base → storage → ssd-state → dark → dev → harden → apps |
| `make dark` | the whole dark theme; safe to run any time something goes light |
| `make dark-desktop` | GTK 3/4, window decorations, panel, desktop background, Qt apps |
| `make dark-terminal` | LXTerminal palette, `LS_COLORS`, bat/fzf/tmux/neovim |
| `make dark-apps` | VS Code, Chromium, Firefox, Thonny, Geany |
| `make dark-system` | login greeter, text console, `/etc/skel` for future accounts |
| `make llm` | fast path to a working local model, skipping the slow apt upgrade |
| `make llm-test` | prove the local AI works: inference, speed, tool calling |
| `make doctor` | check the whole chain and say what to fix |
| `make queue` | work every GitHub issue labelled `agent:queued`, opening PRs |
| `make queue-timer` | poll GitHub for labelled issues unattended (`ARGS=off` stops) |
| `make labels` | create the `agent:*` labels in a repo |
| `make network` | verify the Pi can reach github.com, join Wi-Fi if configured |
| `make base` | updates, hostname, timezone, locale, core packages |
| `make storage` | boot order check, HAT SSD mount, zram, trim |
| `make ssd-state` | keep Docker/model/project data on the SSD, not the boot drive |
| `make dev` | git identity, SSH key, optional uv / node / docker |
| `make apps` | install everything in `$APPS` (see below) |
| `make app APP=ollama` | install a single app |
| `make harden` | key-only SSH, ufw, unattended-upgrades |
| `make capture` | record this Pi's packages and config into `captured/` |
| `make capture-theme` | snapshot the live theme files into `config/captured/` |
| `make apply-captured` | replay `config/captured/` onto this machine |
| `make restore-packages` | reinstall what `make capture` recorded |
| `make mirror` | copy this repo onto the SSD for the next reflash |
| `make check` | `bash -n` + shellcheck; runs on macOS too |

`make help` lists the same thing.

## Apps

Third-party software is à la carte. `settings.env` lists what you want:

```sh
APPS="ollama gh opencode open-webui"
```

Each name maps to `apps/<name>.sh`, which defines one idempotent `app_install()`.
Adding something later is a new file plus a word in that list. A failing app is
reported and the rest still run.

### Getting a model running first

```sh
make llm
```

The model server cannot genuinely go first — it needs the network, `curl`, and the SSD
mounted, or a multi-gigabyte model lands on the USB boot drive. So `make llm` is
the shortest honest route: everything Ollama depends on and nothing else, with
the 20-minute `apt full-upgrade` skipped. Model running in a few minutes; run
`make all` afterwards for the rest.

The model has to fit in RAM — an 8 GB Pi has no GPU to offload to — so stay
around 2–4B parameters at Q4. Gemma 4 shipped April 2026 and is a reasonable
pick, but its largest variants will not fit; take a small one.

One thing worth being clear about: a small local model is a good explainer and a
poor sysadmin. It will invent `nmcli` flags and does not know that Trixie uses
labwc where Bookworm used wayfire. The scripts in this repo encode that, verified
and idempotent. Use the model to ask about the setup, not to perform it.

### Local LLMs on a Pi 5

**Ollama** is the model server. LM Studio was tried and dropped: its installer
would not run on a Lite image, and one runner for one job beats two.

```sh
make llm        # ollama + qwen3.5:4b-q4_K_M, skipping the slow apt upgrade
```

`pi5-agent` depends on the runtime turning the model's tool-call format into
OpenAI-shaped `tool_calls`, and that parsing is the part that lags a model's
release. Ollama's parser for the Hermes `<tool_call>` format has been in place
for years, which is why `hermes3:3b` is the fallback when tool calling
misbehaves.

Default is **`qwen3.5:4b-q4_K_M`** — about 2.5 GB, and Qwen3.5 is built for
agentic coding, which is what the issue queue asks of it.

If tool calling misbehaves, fall back to **`hermes3:3b`** (2.0 GB): smaller, and
Ollama has parsed the Hermes `<tool_call>` format for years. `hermes3:8b`
(4.7 GB) fits but runs at ~2–3 tok/s. Set `OLLAMA_MODEL`.

```sh
make app APP=ollama
pi5-agent --selftest
```

If `make llm-test` stage 4 fails, `hermes3:3b` is the thing to try before
concluding tool calling does not work.


## Is the local AI working?

```sh
make llm-test
```

Four stages in dependency order, each printing what it saw:

```
1. endpoint        reachable at http://127.0.0.1:11434/v1
2. model           qwen3.5:4b-q4_K_M
3. inference       asks a real question, prints the answer and tok/s
4. tool calling    offers tools, checks tool_calls come back
```

Stage 3 matters because it separates "the model is not generating" from "the
model generates but the runtime cannot parse its tool calls" — very different
problems with the same symptom. It also reports **tokens per second**, which is
the number that tells you whether this is usable day to day: above 5 is
comfortable, 2–5 is slow but workable, below 2 means pick a smaller model.

If stage 4 fails, chat and `opencode` still work — only `pi5-agent` and
`hermes-agent` need tool calling. The fallback is Ollama with Hermes 3, whose
format has had parser support for years.

## Troubleshooting

```sh
make doctor
```

Walks the chain in dependency order — system, storage, model server, loaded
model, tool calling, GitHub, web UI — and prints a fix line under anything that
fails. **The first FAIL is usually the real problem**; the ones below it tend to
be consequences.

It is also where the tool-calling check lives in context: if the model does not
return `tool_calls`, it tells you to try Ollama with Hermes 3, whose format has
had parser support for years.

## Agents

Two, with different appetites for risk.

### `bin/pi5-agent` — narrow, in this repo

Issues and a checkout, writes only on an `agent/` branch, opens signed PRs, never
merges or closes. Predictable on a small model because the tool menu is short.

**Full documentation: [docs/pi5-agent.md](docs/pi5-agent.md)** — the spec it
follows, the tool list, the safety model, `AGENTS.md` support, and the limits.

It follows no agent framework: just the OpenAI tool-calling wire format, plus
`AGENTS.md` for project instructions — the same file `opencode` reads, so one
file steers both.

### Label-driven queue

Three labels, one per state. Create them once per repo:

```sh
make labels                    # this checkout
make labels ARGS=owner/name    # anywhere else
```

| Label | Meaning | Colour |
| --- | --- | --- |
| `agent:queued` | you want the agent to attempt this | blue |
| `agent:done` | PR opened, awaiting your review | green |
| `agent:failed` | agent could not do it, no PR | red |
| `agent:opencode` | add alongside `agent:queued` to route it via opencode | purple |

A failure escalates on its own: if the built-in loop opens no PR, the queue
tries opencode before marking the issue `agent:failed`. The label then means
both approaches were tried.

Unless the agent *said why it stopped*. `cannot_complete` is a tool, so an issue
needing a fact it cannot obtain ends with the model's own reason quoted on the
issue rather than a guess at what went wrong — and skips the escalation, since
opencode runs the same model and would hit the same wall. See
[stopping is an outcome](docs/pi5-agent.md#stopping-is-an-outcome).

They are a state machine rather than a category, which is why they read
`agent:state` — the prefix groups them in GitHub's label dropdown, and the names
stay accurate if this queue ever runs somewhere other than the Pi. Change them
with `AGENT_LABEL` and friends.

Then tag an issue **`agent:queued`**:

```sh
make queue                        # list what it would work - read-only
make queue ARGS=--allow-write     # actually work them
```

For each labelled issue it branches, edits, commits, opens a **PR**, then
relabels the issue `agent:done` and comments with the PR link. Failures get
`agent:failed` and a comment saying no PR was opened. Nothing is merged or
closed — that stays yours.

Idempotence comes from two places: the label swap, and the branch. An issue
whose `agent/issue-N` branch already exists on `origin` is treated as attempted
and skipped, so a rerun after a crash does not duplicate work. Each issue starts
from a clean default branch, or its diff would include the previous one's.

### Leaving it running

```sh
# settings.local.env
QUEUE_AUTO=1
QUEUE_INTERVAL=15min
```

```sh
make queue-timer
```

Installs `pi5-queue.timer`, which polls every repo under `~/GitHub` for
`agent:queued` issues. Label an issue, close your laptop, review the PR
later.

```sh
systemctl list-timers pi5-queue.timer   # when it next runs
journalctl -u pi5-queue -f              # watch it work
systemctl start pi5-queue               # run one cycle now
make queue-timer ARGS=off               # stop
```

**Repos it does not have yet.** By default it only checks checkouts already
under `~/GitHub`, so an issue labelled in a repo the Pi has never cloned is
invisible. Turn on discovery and it will find and clone them:

```sh
QUEUE_DISCOVER=1
QUEUE_TOPIC=pi-agent           # opt repos in, on GitHub
```

**Opting a repo in is a GitHub topic, not a config change here.** Add the topic
`pi-agent` to a repository and the Pi will start working its labelled issues;
remove the topic and it stops. Nothing to edit on the Pi, and it is a query
rather than a judgement — no model decides what gets cloned.

Discovery asks which of your repos have an open labelled issue, intersects that
with the topic, shallow-clones anything missing, then works it. `QUEUE_REPOS`
narrows further if set. Each repo is fetched and fast-forwarded first, so the
agent branches off current `main` rather than whatever was on disk last time.

Leaving `QUEUE_TOPIC` empty puts **every repo you own** in scope, which is
rarely what you want running unattended — the installer warns if you do.

A systemd timer rather than cron, for three reasons: it will not start a second
run while one is still going — which matters when a single issue takes ten
minutes on this hardware — `Persistent=true` catches up after a reboot instead
of waiting a full interval, and the output lands in the journal rather than a
stray log file.

Each cycle asks `gh` for the issue count before starting anything. Most cycles
have nothing to do, and waking a 4B model to discover that would spend minutes
of CPU the Pi does not have spare.

**`QUEUE_AUTO=1` is required and defaults off.** This opens pull requests while
you are not watching, so nothing else implies it. If the Telegram bridge is
installed, a cycle that opens PRs sends you the links.

Write issues for it accordingly: small, specific, one file where possible. A 4B
model will not work a vague ticket, and `write_file` replaces whole files.

### Telegram — tell it a repo has work

```sh
# settings.local.env
TELEGRAM_TOKEN=123456:ABC...        # from @BotFather
TELEGRAM_ALLOWED_IDS=987654321      # from @userinfobot
TELEGRAM_ALLOW_WRITE=1              # let it actually open PRs
TELEGRAM_PASSPHRASE=Doom            # optional second lock
```

```sh
make app APP=telegram
```

**Not a chat bot.** There is no free-form path to the model — four commands,
and anything else gets a one-line rejection without the model ever seeing it:

| Message | Does |
| --- | --- |
| `/work my-repo` | works the `agent:queued` issues there, opening PRs |
| `/repos` | which repos it can see |
| `/status` | is the local model up |
| `/help` | the above |

Plain phrasing works too — **naming a repo means "work it"**, since that is the
only action available:

```
Doom check for new github issues in this repo my-pi5-setup
```

That is matched by **string comparison against your checkout names**, not by
asking the model. Nothing in a message is ever sent to it as a prompt, so the
friendlier phrasing does not widen anything: however you word it, you can only
reach the same four workflows.

So the whole loop is: label an issue `agent:queued`, tell the bot the repo,
review the PR.

Restricting it this way is not only about safety. Free-form chat with a 4B model
on a CPU is slow and mediocre, and every message would occupy the board for
minutes. A fixed command surface means a message can only ever trigger a
workflow you have already reviewed.

**Three boundaries:**

- **The allowlist is mandatory.** A bot token is a URL anyone can POST to, so
  without `TELEGRAM_ALLOWED_IDS` a stranger who found the bot could drive it.
  The bridge exits at startup rather than run open, and messages from unlisted
  chats are logged and dropped rather than answered — replying would confirm the
  bot is live.
- **Repos are resolved by name against checkouts under `GITHUB_DIR`**, so a
  message cannot name an arbitrary path. Narrow it further with
  `TELEGRAM_REPOS`.
- **Writes are off by default.** Without `TELEGRAM_ALLOW_WRITE=1`, `/work`
  reports what it would have done. With it, PRs are still branch-only and signed.

**Optional passphrase.** With `TELEGRAM_PASSPHRASE` set, every message must
start with it or the bot replies *"I don't know you."* Short is right — you type
it every time — and it is **case-insensitive**, because a phone capitalises the
first word of a message.

```
Doom check for new github issues in my-pi5-setup
```

Be clear about what that buys, since it is checked **after** the allowlist:
against a stranger it is redundant — they never get past the chat id, and are
met with silence rather than a reply. It earns its place in a narrower case: if
your own Telegram account is compromised, or someone picks up your unlocked
phone. The allowlist checks *who you are*; the passphrase checks *what you
know*.

It is not a strong secret either way — it sits in plaintext chat history on both
devices and on Telegram's servers. Treat it as a speed bump, not a lock.

A wrong passphrase does get an answer, unlike an unlisted chat. That is
deliberate: anyone reaching this check is already an allowlisted id, so it is
almost certainly you mistyping, and silence would just look broken.

The token is written to `/etc/my-pi5-setup/telegram.env` at mode 0600, not into
the systemd unit — `systemctl show` prints `Environment=` lines to any local
user.

### `opencode` — terminal coding agent

```sh
make app APP=opencode
cd ~/GitHub/<repo> && opencode
```

Configured against whichever local server is running: the installer asks the
endpoint what model is actually loaded and writes
`~/.config/opencode/opencode.json` with a matching
`@ai-sdk/openai-compatible` provider. Nothing leaves the Pi.

> **Not `opencode-pi`.** That package on pi.dev has a different "Pi" — the Pi
> Coding Agent, not a Raspberry Pi — and it bridges OpenCode's free *hosted*
> models into that agent. It has no local model support, so it would send your
> work off the box. Plain `opencode` is the one that talks to localhost.

### `hermes-agent` — Nous Research's harness

```sh
make app APP=hermes-agent
hermes setup      # then point it at the local endpoint
```

[Hermes Agent](https://github.com/NousResearch/hermes-agent) is a full agent
harness: terminal commands, file editing, process management, web search,
browser control — driven by whichever local model you are already running. It
speaks to Ollama, LM Studio, vLLM, SGLang and llama.cpp, so it slots onto the
backend this repo already sets up.

**Expect this not to work well on an 8 GB Pi.** Nous state that *"every
recommended model gets at least a 64K context window"*, and they size against
GPU memory — *"a GPU with 8 GB+ runs the small catalog models comfortably."* The
Pi has no GPU and holds everything in system RAM, so the KV cache alone settles
it:

| Model | Weights | KV @ 8K | KV @ 64K | Total @ 64K |
| --- | --- | --- | --- | --- |
| `qwen3.5:4b-q4_K_M` | 2.5 GB | 1.1 GB | 9.0 GB | **11.5 GB** |
| `hermes3:3b` | 2.0 GB | 0.9 GB | 7.0 GB | **9.0 GB** |
| `gemma-4-E2B` | 3.0 GB | 0.9 GB | 7.5 GB | **10.5 GB** |

fp16 KV cache, approximate layer and head counts, before the OS. Every row
exceeds 8 GB at the context Hermes expects.

arm64 itself is fine — Nous ship a Termux path — so this is a memory ceiling,
not a portability one. It is installed here because it is worth having on a
bigger machine. **On the Pi, use `pi5-agent` or `opencode`**, both of which keep
a short tool menu and work inside 8K.

It also has a **terminal tool**, so it can run commands on the Pi. That is the
point of it, and it is a different bargain from `pi5-agent`'s branch-only
writes. Pick per task.

The installer brings its own Node 22, Python 3.11, ripgrep and ffmpeg — upwards
of a gigabyte, on the boot drive. `apps/hermes-agent.sh` refuses to start if
there is under 4 GB free.

## Working issues with the local model

`bin/pi5-agent` is a single self-contained file — stdlib Python, no pip deps —
that drives the local model through `gh` and `git`. Drop it into any repo's
agent harness. Inference never leaves the Pi.

```sh
make llm-test                        # can the model call tools at all?
pi5-agent --issue 12 --allow-write   # read it, branch, work it, open a PR
pi5-agent "summarise open issues"    # read-only question
```

`--issue 12` seeds the whole workflow: read the issue, find the relevant code,
branch, edit, commit, open a PR describing what it changed and what it
was unsure about. Then it prints the diff command and stops.

### The containment boundary

Not "read nothing" — the point is to get work done. The boundary is **nothing
lands anywhere you have to undo**:

- **Never the default branch.** Every edit requires an `agent/`-prefixed branch
  first; `write_file` refuses until `git_branch` has run, and `git_commit`
  refuses on the default branch.
- **PRs open ready for review**, and opening one prompts. Nothing merges by
  itself. `AGENT_PR_DRAFT=1` puts drafts back — on a repo without branch
  protection that flag is the only mechanical brake there is.
- **Every PR and commit is signed.** The PR body carries `Written by pi5-agent
  on <host> using <model>`, and the commit gets an `Agent:` trailer so a squash
  merge keeps the attribution in git history. The harness supplies the model id;
  it never depends on the model reporting anything about itself.
- **Closing an issue is not a tool.** The agent cannot close anything; what it
  can do is link the PR to its issue with `Closes #N`, so *merging* closes it —
  the harness adds the keyword, since a model that writes "addresses #9" or a
  bare `#9` produces a link that does nothing. `AGENT_PR_CLOSES=0` downgrades
  that to `Refs #N` and keeps closing in your hands, which is worth doing while
  a harness is new: a drifting model here once opened a PR redoing a different,
  already-merged ticket, and the stamped keyword closed the wrong issue.
- **The branch name comes from the issue number**, not the model. `agent/issue-N`
  is the queue's only idempotence key; a model asked for #3 has named its branch
  after #1 more than once.
- **A run never hands back a dirty checkout.** Edits from a run that stopped
  early are committed on its branch as `wip:` and the default branch comes back
  clean — otherwise the queue's own dirty guard skips every later issue, every
  cycle, silently.
- **Refuses to start on a dirty tree** (unless `--force`), so the review diff is
  the agent's work and not tangled with your own.
- `gh` and `git` run with fixed argv, never a shell string.
- File access is confined to the checkout, and `.git/` internals are off limits.
- Working on **this** repo it may edit its own code — your review is the guard
  — but it returns to the default branch afterwards, so the next run never
  executes unreviewed code. `AGENT_PROTECTED_PATHS` bans paths outright if you
  want that instead.

Local edits on a throwaway branch do *not* prompt — they are reviewable and
revertible, so per-write confirmation would just be noise. Only the two outward
facing actions, opening a PR and commenting on an issue, ask first.

### Tools

Read: `gh_issue_list`, `gh_issue_view`, `list_files`, `read_file`,
`search_files`, `git_diff`. Write (needs `--allow-write`): `git_branch`,
`write_file`, `git_commit`, `gh_pr_create`, `gh_issue_comment`.

Short on purpose. Tool-choice accuracy falls off as the menu grows and E2B is a
2B-effective model — which is also the case against pointing a GitHub MCP server
at it, since those expose dozens of tools at once.

### Check tool calling first

Gemma 4 emits tool calls as trained special tokens (`<|tool_call|>`) and the
runtime has to parse those into OpenAI-shaped `tool_calls`. That parsing lags
model releases and has been reported broken elsewhere. `make llm-test` settles
it in two seconds, and catches it regressing after an Ollama update.

### Expectations

A 2B model will get argument names wrong, occasionally rewrite more of a file
than it needed to, and sometimes stall. `write_file` takes complete file
contents, so it works best on small files and focused issues. Treat the PR
as a first pass to review, not a finished change — which is the workflow anyway.

`read_file` pages rather than returning whole files: the result says which lines
you got and how to fetch the next ones, and `offset` takes a line number from
`search_files`. Without that, anything past the first few thousand characters of
a file is unreachable no matter how good the model is —
[details](docs/pi5-agent.md#reading-a-file-that-does-not-fit).

## Out of scope, deliberately

**Agent memory or learning.** The SSD makes storage trivial, so it is tempting.
But storage was never the constraint — retrieval is. After the system prompt,
tool definitions and tool results, only two or three thousand tokens reach the
model per turn. Keeping gigabytes of history on disk does not raise that
ceiling; it only changes which fragment fills it, and choosing well needs real
usage data to tune.

That is application behaviour, not provisioning. `/mnt/ssd/agent-data` is
reserved so anything you build later persists across a reflash, and nothing in
this repo writes to it.

If you do build something, the cheapest version that fits 8K is probably not
embeddings: append what you learn to `AGENTS.md`, which both `pi5-agent` and
`opencode` already read. A short list of project conventions and past failures
beats a vector database you have to query and then squeeze into the same window.

## Surviving an OS change

The OS lives on the USB drive and gets wiped. The SSD does not. So the rule is:
**anything slow to rebuild goes on the SSD**, and `make ssd-state` puts it there.

| | Where | After a reflash |
| --- | --- | --- |
| Docker images + volumes | `/mnt/ssd/docker` | still there |
| Ollama models | `/mnt/ssd/ollama` | still there |
| Repos | `/mnt/ssd/GitHub`, bind-mounted to `~/GitHub` | still there |
| Projects | `/mnt/ssd/projects`, bind-mounted to `~/projects` | still there |
| SSH keys | `/mnt/ssd/ssh`, bind-mounted to `~/.ssh` | still there — no re-adding to GitHub |
| Agent notes | `/mnt/ssd/agent-data` — reserved, unused | still there |
| apt packages, binaries | boot drive | reinstalled — minutes, see `make restore-packages` |
| `~/.config` dotfiles | boot drive | regenerated by `make dark`, which is what you want |

Docker is the interesting one. A container image carries its own userland, so it
does not care that the host OS changed underneath it — move `/var/lib/docker` to
the SSD and Open WebUI comes back with its chat history, no pull, no rebuild.
Which suggests a habit: **anything you would hate to reinstall, run in a
container.**

apt packages cannot move. A `.deb` scatters files across `/usr`, `/etc` and
`/var/lib/dpkg`, and mixing one release's binaries with another's libc breaks.
Reinstalling them is cheap, so it is not worth fighting.

Two details that matter:

- Docker and Ollama get `RequiresMountsFor=/mnt/ssd`. Without it they can start
  before the SSD mounts, find their data directory missing, and silently
  recreate it on the boot drive.
- If Docker already has images in `/var/lib/docker`, the script refuses to just
  switch — that would strand them, invisible but still occupying the boot drive.
  Move them deliberately: `make ssd-state ARGS=--migrate-docker`.

### When you reflash

Point Raspberry Pi Imager at the **USB drive**. The SSD shows up in the same
picker; selecting it wipes everything above. Nothing in this repo formats or
partitions anything — `20-storage.sh` only reads the SSD's existing UUID and
adds an `/etc/fstab` line.

## Repos

Clones live in `~/GitHub`, which is bind-mounted from `/mnt/ssd/GitHub` — so a
reflash does not take your checkouts with it. `40-dev.sh` installs a shell
function to get there:

```sh
github                # cd ~/GitHub
github my-pi5-setup   # cd straight into a repo, with tab completion
```

A function rather than an alias, so it can take the argument. Path comes from
`GITHUB_DIR`.

## Settings

Defaults live in `settings.env`. Override them in **`settings.local.env`**, which
is gitignored — hostname, timezone, git identity, which optional toolchains to
install, where the SSD mounts:

```sh
cp settings.env settings.local.env   # then edit
```

At minimum set your git identity there — `settings.env` deliberately ships
without one, so this repo carries nobody's details and a fork does not inherit
someone else's name on its commits:

```sh
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL=you@example.com
```

## How the dark theme holds

Getting one account dark is easy; keeping it dark is the actual problem. Four
things cover it:

- **`gtk-application-prefer-dark-theme` + `PiXnoir`** for GTK 3 apps, and
  `gsettings color-scheme prefer-dark` for GTK 4 / libadwaita, which ignores the
  ini file.
- **`GTK_THEME` and `QT_QPA_PLATFORMTHEME=gtk3`** exported from both
  `/etc/profile.d` and `~/.config/environment.d`, so apps launched from the panel
  and from a shell agree.
- **The login greeter and the text console**, so there is no white flash before
  the desktop loads.
- **`/etc/skel`**, so any account created later starts dark without running
  anything.

### When a key name changes between releases

Pi OS moves these settings around between releases. Rather than chase them:

1. Set the desktop up by hand (Appearance Settings) until it looks right.
2. `make capture-theme` — snapshots the real files into `config/captured/`.
3. Commit that.
4. After the next reflash: `make dark && make apply-captured`.

The generated defaults get you most of the way; the capture pins the rest.

## Safety

- Every script is idempotent — run them as often as you like.
- `DRY_RUN=1` prints changes instead of making them.
- Any system file is copied to `state/backups/<timestamp>/` before it is touched.
- **The EEPROM boot order is never changed** unless you ask:
  `make storage ARGS=--fix-boot-order`, and it still prompts.
- `20-storage.sh` never formats or partitions. If the SSD has no filesystem it
  tells you and stops.
- `50-harden.sh` refuses to disable SSH password login until an authorized key is
  actually present, so it cannot lock you out.
- With `~/.ssh` bind-mounted from the SSD, a failed mount would break key auth
  with passwords already off. `50-harden.sh` therefore keeps a copy of your
  public keys at `/etc/ssh/authorized_keys.d/<user>` on the boot drive and has
  sshd read both paths.

## Layout

```
bootstrap.sh      curl-able entry point
Makefile          the targets above
settings.env      defaults; override in settings.local.env
lib/              logging, detection, idempotent file editing, apt helpers
scripts/          numbered stages, each runnable on its own
apps/             one installer per third-party app, listed in $APPS
docs/             pi5-agent reference
config/           tracked config fragments, plus config/captured/ snapshots
captured/         output of 'make capture' - this machine's inventory
state/            gitignored: detection results and backups
```

This line written autonomously by a Raspberry Pi 5
