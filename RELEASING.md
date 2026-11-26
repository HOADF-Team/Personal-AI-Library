# Release process

This document defines how Personal AI Library versions are identified, checked, and published.

## Current development version

The repository's `VERSION` file contains the current collection version. At the moment it is `0.1.0`.

This is a development version marker, not a claim that a GitHub Release has been published. A version becomes a published release only after a matching Git tag and GitHub Release are created.

## Version format

Use Semantic Versioning: `MAJOR.MINOR.PATCH`.

- **PATCH** — compatible corrections: wording, broken links, small fixes that do not change a Skill's intended workflow or installation behavior.
- **MINOR** — new Skills, retired Skills, or backward-compatible workflow improvements.
- **MAJOR** — incompatible changes to installation paths, installer behavior, repository layout, licensing, or established Skill contracts.

While the project remains below `1.0.0`, MINOR updates may still contain changes that would be considered breaking before a stable 1.x release. Document such changes clearly.

## Before publishing

1. Update `VERSION`.
2. Update `CHANGELOG.md` with user-visible changes and migration notes.
3. Confirm the README and catalogs match the actual collection.
4. Run:
   - `python validate_skills.py`
   - `python -m unittest discover -s tests -v`
   - `.\tests\test_install.ps1` on Windows PowerShell 5.1 and PowerShell 7.
5. Confirm all required GitHub Actions jobs pass on the exact commit to be released.
6. Review the final diff, licenses, included files, and installer safety.
7. Create an annotated tag named `vX.Y.Z` pointing to the verified commit.
8. Create a GitHub Release for that tag and summarize the changes from `CHANGELOG.md`.

Do not publish a release from a commit with failing or incomplete required checks. Do not describe scenario-based Skill evaluations as production tests.

## Updating an existing installation

1. Download the ZIP archive for the desired GitHub Release.
2. Extract it and inspect the release notes.
3. Run `install.ps1 -Force` from the extracted folder.
4. Restart Codex if it was already running.

## Rolling back to a previous release

1. Keep a backup of any locally modified Skill files.
2. Download and extract the ZIP archive of the previous release.
3. Run that older release's `install.ps1 -Force` against the same target directory.
4. The installer restores files present in the older release and removes newer library-managed files only when their hashes still match the current manifest.
5. Review the installed files and restart Codex.

The rollback path is covered by a Windows regression test that installs a simulated older version, updates to a newer version, and then restores the older version. This does not provide an automatic backup of local edits or a full filesystem snapshot.

The installer manifest's `version: 1` is the **manifest format version**, not the library version. The installer currently does not enforce version ordering or automatically download updates. Users choose which release archive to install.

## Release policy

Releases are manual and intentional. A normal push or successful CI run does not publish a release. No automatic release workflow is configured.
