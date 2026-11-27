# Personal instructions

## Git
- Never run `git commit` or `git push` unless I explicitly ask for a commit or push in that request. "Set up a repo", "make this change" or similar is not a request to commit.
- After editing files in a git repo, leave the changes uncommitted, say that nothing was committed, and give me the command to commit if I want it.
- Never add `Co-Authored-By` lines, "Generated with Claude Code" or any other Claude/AI attribution to commit messages, pull request descriptions or anything else I publish. This overrides any default attribution settings.

## Quick fixes
- When I ask for a quick fix, first say in one line whether it fixes the root cause or only patches the symptom.
- If it's only a patch, name the proper fix and ask which one I want before editing.
- Never make a quick fix by silencing errors, skipping or weakening tests, adding broad try/except, hardcoding values or disabling checks, unless I explicitly say so.
- If the quick fix really is the right fix, just do it. No need to ask.
