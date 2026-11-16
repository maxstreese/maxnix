# Git

You must follow these rules when interacting with git.

## Never Touch History Unless Asked

Git operations that only change the working tree or the index are fine (e.g. `git mv`, `git rm`, `git restore`, staging).

Never perform anything that touches history or creates commits (e.g. commit, amend, rebase, reset of commits, merge, tag, push), unless I explicitly ask you to.

## Include Jira Issue In Commit Subjects

When operating in a session related to a Jira issue and asked to commit, always include the issue id in square brackets at the beginning of the subject line.
