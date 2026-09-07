# my-pi5-setup

Scripts that put my Raspberry Pi 5 back the way I like it after a reflash or an
OS change — and, above all, make it **dark everywhere, every time**.

Target: **Raspberry Pi OS 64-bit Desktop**, the image Raspberry Pi Imager offers
by default. Trixie (labwc) and Bookworm (wayfire) are both handled; the scripts
detect which one they are on. Boot is from USB, with an SSD on a HAT as extra
storage.

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

Easiest is not to fight it: **SSH in from your Mac** and paste there. Imager
already put your key on the image, so `ssh pi5.local` works on first boot.

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
what this repo builds is headless already: the LM Studio server, Open WebUI
browsed from another machine, and `pi5-agent` over SSH. None of it needs a
screen attached to the Pi.

**Two things to watch:**

- LM Studio's installer is the one component not verified on a minimal image. If
  it pulls in a shared library the desktop image happened to already have, the
  install will say so — `apps/lm-studio.sh` reports the failure rather than
  carrying on.
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
| `make llm-test` | check the local model can actually call tools |
| `make doctor` | check the whole chain and say what to fix |
| `make network` | verify the Pi can reach github.com, join Wi-Fi if configured |
| `make base` | updates, hostname, timezone, locale, core packages |
| `make storage` | boot order check, HAT SSD mount, zram, trim |
| `make ssd-state` | keep Docker/model/project data on the SSD, not the boot drive |
| `make dev` | git identity, SSH key, optional uv / node / docker |
| `make apps` | install everything in `$APPS` (see below) |
| `make app APP=lm-studio` | install a single app |
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
APPS="lm-studio open-webui"
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
the shortest honest route: everything LM Studio depends on and nothing else, with
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

Two interchangeable backends. Both expose an OpenAI-compatible endpoint, so Open
WebUI and `pi5-agent` work against either:

```sh
APPS="lm-studio gh open-webui"     # default
APPS="ollama gh open-webui"        # Ollama instead
make llm LLM_APP=ollama            # fast path, either way
```

### Ollama, and why you might prefer it

**If tool calling matters, start here.** `pi5-agent` depends on the runtime
turning the model's tool-call format into OpenAI-shaped `tool_calls`, and that
parsing is the part that lags a model's release. Ollama's parser for the Hermes
`<tool_call>` format has been in place for a long time, and Hermes 3 is trained
for function calling.

Default is **`hermes3:3b`** — 2.0 GB, comfortable on 8 GB, tool-capable.
`hermes3:8b` (4.7 GB) fits too but runs at ~2–3 tok/s. Set `OLLAMA_MODEL`.

```sh
make app APP=ollama
pi5-agent --backend ollama --selftest
```

If Gemma 4 fails `make llm-test` under LM Studio, this is the thing to try
before concluding tool calling does not work.

### LM Studio

Default stack is **headless LM Studio** plus Open WebUI:

- **`lm-studio`** — installs the `lms` CLI via `lmstudio.ai/install.sh`, symlinks
  the models directory onto the SSD, and runs the OpenAI-compatible server as
  `lmstudio-server.service` with lingering enabled, so it comes back after a
  reboot with nobody logged in. Endpoint: `http://127.0.0.1:1234/v1`. Local only
  unless you set `LMS_EXPOSE=1` — there is no authentication on it.
- **`ollama`** — the alternative runner. systemd service, models on the SSD,
  endpoint on `127.0.0.1:11434`.
- **`open-webui`** — the browser front end. Detects which model server is
  installed and points at it (both, if both are); runs in Docker with `--network=host` and opens its
  port in ufw. Docker installs on demand even if `INSTALL_DOCKER=0`.

Then: `http://pi5.local:8080`, and the first account you create is the admin.

**Default model: Gemma 4 E2B** —
[`lmstudio-community/gemma-4-E2B-it-GGUF`](https://huggingface.co/lmstudio-community/gemma-4-E2B-it-GGUF).
Downloaded and loaded automatically; override with `LMS_MODEL`.

Gemma 4 comes in E2B, E4B, 26B-A4B and 31B. **E2B is the only one that fits an
8 GB Pi** — there is no GPU to offload to, so the model sits in system RAM next
to everything else.

Its 256K context window is a trap on this hardware: the KV cache at that length
costs more memory than the model does. The server loads at `LMS_CONTEXT`,
default `8192`. Raise it only if you have watched the memory while doing so.

```sh
lms ls                  # what is downloaded
lms ps                  # what is loaded
lms get --help          # find something else
```

What to expect on a Pi 5, CPU-only, Q4 quantised — there is no usable GPU
offload:

| Model size | Speed |
| --- | --- |
| 1–3B | ~5–10 tok/s, comfortable |
| 7–8B | ~2–3 tok/s, usable but slow |
| larger | don't |

More RAM raises the ceiling on model size, not the speed.

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

Issues and a checkout, writes only on an `agent/` branch, opens draft PRs, never
merges or closes. Predictable on a small model because the tool menu is short.
Covered below.

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

arm64 is a supported target — Nous ship a Termux/Android path — so the Pi is not
exotic. **The constraint is the model, not the harness.** Nous' own Ollama guide
points at 32 GB for the models this is really meant to drive; on an 8 GB Pi with
a 3B model, expect it to manage small tasks rather than behave like it does on a
workstation.

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
pi5-agent --issue 12 --allow-write   # read it, branch, work it, open a draft PR
pi5-agent "summarise open issues"    # read-only question
```

`--issue 12` seeds the whole workflow: read the issue, find the relevant code,
branch, edit, commit, open a **draft** PR describing what it changed and what it
was unsure about. Then it prints the diff command and stops.

### The containment boundary

Not "read nothing" — the point is to get work done. The boundary is **nothing
lands anywhere you have to undo**:

- **Never the default branch.** Every edit requires an `agent/`-prefixed branch
  first; `write_file` refuses until `git_branch` has run, and `git_commit`
  refuses on the default branch.
- **PRs are always drafts**, and opening one prompts. Nothing merges.
- **It never closes issues.** That is explicitly not in the tool list — you
  review and close.
- **Refuses to start on a dirty tree** (unless `--force`), so the review diff is
  the agent's work and not tangled with your own.
- `gh` and `git` run with fixed argv, never a shell string.
- File access is confined to the checkout, and `.git/` internals are off limits.

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
it in two seconds, and catches it regressing after an LM Studio update.

### Expectations

A 2B model will get argument names wrong, occasionally rewrite more of a file
than it needed to, and sometimes stall. `write_file` takes complete file
contents, so it works best on small files and focused issues. Treat the draft PR
as a first pass to review, not a finished change — which is the workflow anyway.

## Surviving an OS change

The OS lives on the USB drive and gets wiped. The SSD does not. So the rule is:
**anything slow to rebuild goes on the SSD**, and `make ssd-state` puts it there.

| | Where | After a reflash |
| --- | --- | --- |
| Docker images + volumes | `/mnt/ssd/docker` | still there |
| LM Studio models | `/mnt/ssd/lm-studio` | still there |
| Repos | `/mnt/ssd/GitHub`, bind-mounted to `~/GitHub` | still there |
| Projects | `/mnt/ssd/projects`, bind-mounted to `~/projects` | still there |
| SSH keys | `/mnt/ssd/ssh`, bind-mounted to `~/.ssh` | still there — no re-adding to GitHub |
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

- Docker and the LM Studio server get `RequiresMountsFor=/mnt/ssd`. Without it they can start
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
config/           tracked config fragments, plus config/captured/ snapshots
captured/         output of 'make capture' - this machine's inventory
state/            gitignored: detection results and backups
```
