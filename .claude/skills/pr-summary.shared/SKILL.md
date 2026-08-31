---
name: pr-summary
description: Generate PR summary by comparing code differences with parent branch. Uses PR template and outputs to ./report/PR_SUMMARY.md.
disable-model-invocation: true
---

# Claude Command: PR Summary

Compare this branch against its parent branch, then write a PR summary.

## Rules

- Use simple English with short, clear sentences.
- Keep the summary concise and non-repetitive: state each point once. Don't restate the background in the review notes, or repeat the same change across sections.
- Describe what changed and why — never file/line counts (e.g. "39 files, +5,301 lines").
- Follow `.github/PULL_REQUEST_TEMPLATE.md`; use only the sections it defines, add none.
- Output to `report/PR_SUMMARY.md` (create `report/` if missing).

## Diffing

1. **Detect the parent** (not always master): use the `check-rule.*` skill's base-detection procedure (open PR's `baseRefName` first, then the smallest-`rev-list --count` merge-base among candidate branches).
2. **Use the remote tip**: prefer `origin/<parent>` over the local branch (it may be stale); verify with `git rev-parse --verify origin/<parent>`.
3. **Diff the branch-unique changes** with the three-dot range: `git diff origin/<parent>...HEAD`. It diffs from the merge-base, so it shows only what this branch added — even if the parent advanced or was merged in. Avoid the two-dot `git diff origin/<parent>`, which also reverses parent-only commits when your branch is behind.
4. **Include uncommitted changes**: check `git status --short` and cover them too.

## PR Title

After writing the summary, suggest a PR title in the response (not in `report/PR_SUMMARY.md` — the title is a separate GitHub field, not a template section).

- Match this repo's convention from `git log --oneline`: `type: short description` (`feat`, `fix`, `chore`, `docs`, etc.), lowercase, no trailing period.
- Base the type and wording on the dominant change in the diff, not the branch name.
