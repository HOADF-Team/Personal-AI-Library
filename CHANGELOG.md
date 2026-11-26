# Changelog

Notable changes to Personal AI Library are recorded here. This file tracks repository changes; it does not imply that every Skill has been validated in every project or environment.

## 2026-11-26

### Added
- Recorded the simulated `python-development` traceback, minimal input-validation correction, and four passing regression checks.

### Added
- Recorded the simulated `crypto-futures-risk` linear-position calculation pilot.

### Changed
- Strengthened `devops-vps` secret-handling guidance: systemd unit output, journal entries, and process command lines are treated as potentially sensitive and must be redacted before sharing.
- Recorded the simulated `devops-vps` pilot evaluation and its safety-guidance correction.

## 2026-11-25

### Added
- A SHA256-based installer manifest at the installation root to track files managed by the library.
- Safe cleanup of obsolete library files during `install.ps1 -Force`, including files belonging to Skills removed from the repository.
- Preservation of user-created files and obsolete library files that have been modified locally.
- Validation of local Markdown links in every Markdown document inside each Skill, including `references/`.
- Unit tests for Markdown link validation and additional installer lifecycle and safety scenarios.
- A repeatable manual evaluation protocol with five pilot Skill scenarios and a scoring rubric.

### Changed
- The installer validates manifest paths and refuses path traversal, linked target roots/directories/files, and linked manifests.
- The installer preserves files under source folders that exist but are invalid because they lack `SKILL.md`.
- Repository validation and Python tests run against Python 3.9, 3.12, and 3.14 in GitHub Actions.
- Fixed Python 3.9 fallback detection for standard-library source modules and platform extension modules.
- Added detection of missing local submodule candidates in `from package import name` statements while accounting for statically visible package exports.
- README documents the tested Python versions and the manifest-based update behavior.

### Compatibility note
- If an existing installation has no installer manifest, the first forced update does not delete unknown files. The installer cannot safely determine whether those files belong to the library or were created by the user.
