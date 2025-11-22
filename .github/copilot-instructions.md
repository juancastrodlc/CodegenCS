# GitHub Copilot Instructions for CodegenCS

## Git History Management

**NEVER ALTER GIT HISTORY** - Do not use `git commit --amend`, `git rebase`, or any other history-rewriting commands unless explicitly requested by the user for a specific commit.

When working with Git:
- Use regular `git commit` for new changes
- Do not rebase commits that have already been pushed
- Do not amend existing commits unless specifically asked
- Do not use `git rebase --onto` or other complex rebase operations
- If history needs to be changed, ask the user first and explain the consequences

## Build System

This project uses PowerShell scripts for cross-platform builds:
- Scripts support Windows, Linux, and macOS
- Platform detection is handled in `src/build-include.ps1`
- Test changes on both Windows and Linux when modifying build scripts

## Code Style

Follow .NET Core guidelines as specified in the CONTRIBUTING.md files found in the repository.
