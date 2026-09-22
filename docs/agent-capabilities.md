# What the local agent can do

A living record of where `pi5-agent` on a Pi 5 (Ollama, `qwen3.5:4b-q4_K_M`,
20 turns) succeeds and where it fails, with the evidence. Update it whenever an
issue teaches something new. The numbers below come from
`gh pr list --state all --json additions,deletions,changedFiles` and from the
failure comments the queue leaves on issues.

## Scoreboard (as of 2026-09-22)

| Outcome | Count | Issues |
| --- | --- | --- |
| Merged PR, first attempt | 36 | most of #2-#79 |
| Failed, "answered in prose without ever calling a tool" | 4 | #36, #41, #63, #72 |
| Failed, "started work on a branch but opened no pull request" | 1 | #3 (later succeeded on retry) |

Largest merged diff: #79, +0/-161 across 2 files (a `git rm`). Largest merged
edit that added text: #62, +8/-18 in one file (replace one README block with
another). Every merged PR touched three files or fewer.

## Where it excels

**Exact-text replacement in one file.** Given the old text and the new text
quoted verbatim, it lands the change every time: #44-#48, #52-#56, #60-#62,
#70, #73-#75. Two or three such edits in one issue are fine (#73 had three
edits in one file). Line numbers in the issue are ignored or wrong more often
than not - "match on the text, not line numbers" is the phrase that works.

**Deleting files - usually.** `git rm` of one to three named files with a grep\nto verify nothing else references them worked first try in #64, #65 and #68\n(PRs #76-#79). But see "Emptying a file instead of deleting it" below: the same\nissue shape failed differently in #66. Saying "use `git rm <path>`, not an edit\nthat empties the file" in the issue is what makes it reliable.

**Small config or code changes with a stated reason.** One-line default
changes (#33, #35), a short block added to a shell script (#13, #16, #17), a
guard added to a Python function (#29). The issue named the file, the current
text and the desired behaviour.

**Following a verification step.** When the issue ends with "afterwards
`grep -n foo file` should return nothing", the diff reflects that check having
been run.

## Where it struggles

**Five or more edits in one issue.** #63 asked for five separate edits to the
Makefile. #41 asked for twelve occurrences of one string across a README. Both
failed without a single tool call. The same edits, split one to three per
issue (#47-#51 for the README, and the Makefile split that replaced #63),
succeed.

**Deleting a region by its boundaries.** #72 said "delete from heading X to
line Y inclusive". It failed. Deleting an explicitly quoted block succeeds (#60, #71), so the fix is to quote the whole block to remove, even when it is long.

**Anything needing a decision.** #36 bundled a rename across 20 files with a
migration design and an either/or. It failed the same way. Design questions
are not agent work at all; they belong in an unlabelled issue for a person.

**Multi-file edits with different changes per file.** #43 (four one-line
comment edits across three files) worked, but it is the ceiling. Bigger
multi-file changes have not been attempted after #36.

## Why it fails the way it does

The failure is almost always the same: the model reads the issue, writes a
plan or a description of the diff in prose, and never calls the edit tool.
Observations from the failures:

- **Long issues push the model into explaining instead of acting.** A 4B
  model at q4 has a short effective context for instruction following. Once the
  issue body is long enough, the reply becomes a summary of the task.
- **Enumerated edits look like a plan, so it writes a plan.** Five numbered
  steps read as an outline to restate. One quoted before/after pair reads as
  a command to execute.
- **Boundaries need reasoning; blocks need matching.** "Delete from X to Y"
  requires locating two points and understanding the span. A quoted block is
  a single string match.
- **opencode as the fallback did not rescue any of these.** The queue
  escalates to opencode when the built-in loop fails (#3 was rescued that
  way, once). For #36, #41, #63 and #72 it also failed, which suggests the
  issue shape, not the harness, is the limit.

## The issue shape that works

```
<one sentence of why>

<file path>, match on the text, not line numbers.

Old:
<verbatim block>

New:
<verbatim block>

Only that changes. Nothing else in this issue.
```

- One file. One to three edits.
- Quote the exact old text, including indentation, and the exact new text.
- For a deletion, quote the entire block to delete, even if it is 30 lines.
- For a new file, put the complete content in the issue.
- End with a check the agent can run (`grep`, `make -n`).
- No options, no "consider", no "either/or".

## Open questions

- Does a larger model (8B) or a higher-precision quant of the same model
  handle the five-edit and delete-by-boundary cases? Not yet tried.
- Is there an issue length (in characters) above which the no-tool-call
  failure becomes likely? #63 was about 2,300 characters; #62 (succeeded)
  was about 1,700.
- Creating a new file from content given in the issue works: this document was
  created that way, first try, from #80.
- Does an explicit negative ("not an edit that empties the file") generalise?
  It fixed the `git rm` case; whether stating what not to do helps elsewhere
  is untested.

## How to update this document

After any issue teaches something, edit the scoreboard and the relevant
section. The evidence commands:

```sh
gh pr list --state all --limit 100 --json number,additions,deletions,changedFiles,title
gh issue list --state all --limit 100 --json number,title,labels,comments \
  --jq '.[] | select(.comments | any(.body | test("did not finish")))'
```

**Emptying a file instead of deleting it.** #66 asked for `git rm` of
`scripts/32-dark-apps.sh` and `config/chromium.d/99-dark-mode`. The PR merged
as +1/-73: both files were rewritten to a single byte and left in the tree.
The issue said "delete these files with `git rm`" but did not say what not to do. #98 restates it as "use `git rm <path>`, not an edit that empties the
file".

**Applying only part of a multi-edit issue.** #81 quoted a six-line block (a
`##` help line, a comment, a recipe, two echo lines) and asked for it to be
replaced. The PR changed the recipe and the echo but left the `##` help line
untouched, so `make help` printed a target list that was no longer true. #82
deleted four sub-targets but left the aggregate target that depended on them,
breaking `make dark`. Both PRs looked plausible and merged. The lesson is that
a partial application is more expensive than an outright failure, because it
passes review: a quoted block should be one contiguous thing that must change
together, and the issue should end with a check that catches a half-done job
(`make -n dark`, `grep -n dark Makefile`).
