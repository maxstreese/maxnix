---
name: commit
description: Create a git commit for the current changes. Use when the user asks to commit.
disable-model-invocation: true
argument-hint: [optional hint for the message]
allowed-tools: Bash(git add *) Bash(git commit *) Bash(git status *) Bash(git diff *) Bash(git log *)
---

## Context

- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Staged diff: !`git diff --cached`
- Unstaged diff: !`git diff`
- Recent commits: !`git log --oneline -10 2>/dev/null || true`

## Task

Create a commit for the changes above. User hint: $ARGUMENTS

- If something is staged, commit only that. Otherwise propose which files to stage.
- If the changes cover unrelated concerns, propose splitting them into separate commits.
- Match the style of the recent commits (e.g. Conventional Commits if the repo uses them).
- If the branch name contains a Jira issue id (e.g. `PROJ-123`), start the subject with `[PROJ-123]`,
  also in repos that use Conventional Commits (e.g. `[PROJ-123] fix(auth): ...`).
- Subject: imperative mood, ideally ≤50 characters (max 72), no trailing period,
  specific enough to identify the change in `git log --oneline`.
- Add a body unless the subject says everything (typos, renames, version bumps,
  formatting). Separate it with a blank line and wrap at 72 columns.
- The body explains why: the problem or motivation, the approach where it isn't
  obvious, rejected alternatives, and side effects or risks. Include numbers for
  performance claims. Don't restate the diff file by file.
- The message must stand on its own: no references to this conversation.
- Put references in trailers at the end, e.g. `Fixes: <sha> ("<subject>")`,
  `Refs: <issue>`, `BREAKING CHANGE: <description>`.
- End the message with the attribution trailer from Claude Code's git
  instructions (set via the `attribution` setting). Leave it out of the
  choice list options.

Before committing, ask me via a UI choice list instead of plain text:
- The first option is the recommended message.
- Then one or two alternative messages.
- The last option is to restate the message completely.
If I choose a concrete message, treat that as approval and commit immediately with that exact message, followed by the attribution trailer.
Only if I choose the restate option, continue the discussion instead of committing.
