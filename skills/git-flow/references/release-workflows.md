# The release workflows — inputs and guard rails

Read this when you need the exact inputs of `release-branch.yml` or `release.yml`,
or when a dispatch is rejected and you need to know which field was wrong. The
day-to-day commands are already in SKILL.md; this is the detail behind them.


Read from the YAML in all four repos, not from memory.

### ① `release-branch.yml` — "Release Branch"

Cuts `release/<version>` from the base branch. **Touches nothing inside the
branch** — it is a copy of `prod` and nothing more.

| Input | Meaning |
|---|---|
| `bump` (required, choice) | `patch (eg v1.2.3 → v1.2.4)` · `minor (eg v1.2.3 → v1.3.0)` · `major (eg v1.2.3 → v2.0.0)` · `custom (use the version input below)`. The label carries its example — it must be passed **verbatim**, arrow and all. |
| `from` (optional) | Cut from this branch instead. Empty → `env.BASE_BRANCH`, which is `prod` in every repo. **Leave it empty.** |
| `version` (optional) | Only read when `bump` is `custom`; ignored otherwise, so a leftover value cannot silently override a bump. |

The version comes from the latest tag moved on by `bump` — **repo-toolkit computes
it, not you.** Do not predict the number in the plan as if it were settled; the
run writes the real branch URL, an example PR link, and the gh/git commands to its
job summary. Read the branch back afterwards (below).

### ② `release.yml` — "Release"

Tags the release branch tip, writes the notes with GitHub's own generate-notes
endpoint, and publishes.

| Input | Meaning |
|---|---|
| `branch` (optional) | The release branch. Empty → `github.ref_name`, i.e. whatever was picked in "Use workflow from". |
| `previous` (optional) | Previous tag for the notes. Only needed for a side-line tag such as `for-other-thing-v1.2.3`, where GitHub's own pick reaches across to an unrelated tag. |

Guard rails already in the workflow:

- It **aborts unless the branch starts with `release/`**, so it cannot tag `dev`.
- It publishes with `ACTION_TOKEN`, not `GITHUB_TOKEN` — *a release published by
  `GITHUB_TOKEN` does not trigger the `release: published` deploy*. This is why
  the release goes through the workflow. Do not invent another route to creating
  the release.

The tag is the branch name minus the `release/` prefix — `release/v3.11.2-a`
published tag `v3.11.2-a`. Verified against the live release list.
