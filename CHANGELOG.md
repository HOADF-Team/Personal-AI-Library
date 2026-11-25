# Changelog

Notable changes to Personal AI Library are recorded here. This file tracks repository changes; it does not imply that every Skill has been validated in every project or environment.

## 2026-11-25

### Added
- A SHA256-based installer manifest at the installation root to track files managed by the library.
- Safe cleanup of obsolete library files during `install.ps1 -Force`, including files belonging to Skills removed from the repository.
- Preservation of user-created files and obsolete library files that have been modified locally.
- Validation of local Markdown links in every Markdown document inside each Skill, including `references/`.
- Unit tests for Markdown link validation and additional installer lifecycle and safety scenarios.

### Changed
- The installer validates manifest paths and refuses path traversal or linked destination directories.
- Repository validation and Python tests run against Python 3.9, 3.12, and 3.14 in GitHub Actions.
- README documents the tested Python versions and the manifest-based update behavior.

### Compatibility note
- If an existing installation has no installer manifest, the first forced update does not delete unknown files. The installer cannot safely determine whether those files belong to the library or were created by the user.
