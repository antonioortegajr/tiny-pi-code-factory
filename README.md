# my-pi5-setup

Scripts that put my Raspberry Pi 5 back the way I like it after a reflash or an
OS change — and, above all, make it **dark everywhere, every time**.

Target: **Raspberry Pi OS 64-bit Desktop**, the image Raspberry Pi Imager offers
by default. Trixie (labwc) and Bookworm (wayfire) are both handled; the scripts
detect which one they are on. Boot is from USB, with an SSD on a HAT as extra
storage.

## Use it

**One command. Copy this:**

```sh
curl -sL github.com/antonioortegajr/my-pi5-setup/raw/main/bootstrap.sh | bash
```

That is the whole thing: it gets git, fetches this repo, and runs `make all`.

### Pasting it on a fresh Pi

The terminal has not disabled paste — Raspberry Pi OS uses **`Ctrl+Shift+V`**,
not `Ctrl+V`, because `Ctrl+C` is SIGINT and cannot be a copy key. Three ways in,
best first:

1. **SSH in from your Mac and paste there.** Imager already put your key on the
   Pi, so `ssh pi5.local` works on first boot and your Mac's normal `Cmd+V`
   applies. Nothing to fight.
2. **On the Pi:** `Ctrl+Shift+V`, or right-click → Paste, or middle-click to
   paste the selection.
3. **Type it.** The URL above is the short form — `github.com/…/raw/…` redirects
   to `raw.githubusercontent.com`, so it is about 25 characters less to type.

After the first run, `make dark` binds copy and paste explicitly in
`lxterminal.conf`, so this stops being a question.

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

Default stack is **headless LM Studio** plus Open WebUI:

- **`lm-studio`** — installs the `lms` CLI via `lmstudio.ai/install.sh`, symlinks
  the models directory onto the SSD, and runs the OpenAI-compatible server as
  `lmstudio-server.service` with lingering enabled, so it comes back after a
  reboot with nobody logged in. Endpoint: `http://127.0.0.1:1234/v1`. Local only
  unless you set `LMS_EXPOSE=1` — there is no authentication on it.
- **`open-webui`** — the browser front end. Detects which model server is
  installed and points at it; runs in Docker with `--network=host` and opens its
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

## Surviving an OS change

The OS lives on the USB drive and gets wiped. The SSD does not. So the rule is:
**anything slow to rebuild goes on the SSD**, and `make ssd-state` puts it there.

| | Where | After a reflash |
| --- | --- | --- |
| Docker images + volumes | `/mnt/ssd/docker` | still there |
| LM Studio models | `/mnt/ssd/lm-studio` | still there |
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
