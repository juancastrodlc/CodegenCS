# GitHub Copilot Instructions for CodegenCS

## Git History Management

**NEVER ALTER GIT HISTORY** - Do not use `git commit --amend`, `git rebase`, or any other history-rewriting commands unless explicitly requested by the user for a specific commit.

When working with Git:
- Use regular `git commit` for new changes
- Do not rebase commits that have already been pushed
- Do not amend existing commits unless specifically asked
- Do not use `git rebase --onto` or other complex rebase operations
- If history needs to be changed, ask the user first and explain the consequences

Exception: The following operations are acceptable:
- `git commit --amend --no-edit` to add forgotten files to the last commit
- `git push --force-with-lease` when explicitly requested for fixing commit messages

## Build System

This project uses PowerShell scripts for cross-platform builds:
- All executable scripts must start with `#!/usr/bin/env pwsh` shebang
- Scripts support Windows, Linux, and macOS
- Platform detection is handled in `src/build-include.ps1`
- Use `$script:isWindowsPlatform` for platform-specific code
- Use `$env:USERPROFILE` (Windows) and `$env:HOME` (Linux/macOS) for home directory
- Never hardcode paths - use `$PSScriptRoot` for script location
- Test changes on both Windows and Linux when modifying build scripts

### Build Script Standards
- All scripts use `ErrorActionPreference = "Stop"` for fail-fast behavior
- All scripts use try-finally blocks for cleanup
- Common configuration is sourced from `build-include.ps1`
- Temporary files go to workspace `.tmp` directory, not system temp

## Code Style

Follow .NET Core guidelines as specified in the CONTRIBUTING.md files found in the repository.

## Commit Messages

When generating commit messages, follow these guidelines:
- Use conventional commit format (feat:, fix:, docs:, chore:, refactor:, etc.)
- Focus on code changes only - ignore VS Code configuration files (.vscode/*, *.code-workspace)
- First line (title) must not exceed 52 characters
- All subsequent lines must not exceed 72 characters
- Wrap body text at 72 characters for readability
- Use bullet points for multiple changes in commit body

## Project Goals and Documentation

Inspect all documents in the `docs/` directory and the root `README.md` for:
- Project architecture and design decisions
- Cross-platform development roadmap (`docs/development/crossplatform-roadmap.md`)
- File system abstraction strategy (`docs/development/filesystem-abstraction-analysis.md`)
- Project dependencies (`docs/development/CodegenCS Non-Test Project Dependencies.md`)

## Communication Style

Do not provide summaries of documentation changes you just made. The documentation speaks for itself.a simple Done! is enough.

## Version Management

This project uses Nerdbank.GitVersioning (nbgv):
- Version is controlled by `src/version.json`
- Do not manually edit `<Version>` tags in `.csproj` files
- Build automatically generates version from git history
- Use `dotnet nbgv get-version` to check current version
