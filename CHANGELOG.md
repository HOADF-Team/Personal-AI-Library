# Changelog

Notable changes to Personal AI Library are recorded here. This file tracks repository changes; it does not imply that every Skill has been validated in every project or environment.

## 2026-11-26

### Added
- Recorded scenario evaluations 19–27 for documents-office, google-sheets, github-portfolio, marketplace-listings, product-marketing, research-fact-checking, seo-audit, social-media, and marketing-copywriting.
- Added Office workbook safeguards for formula recalculation and VBA preservation; Google Sheets safeguards against formula injection from untrusted imported values.
- Added repository credential incident response guidance, marketplace photo privacy checks, research prompt-injection defenses and source provenance requirements.
- Added SEO staging/privacy and lab-versus-field performance checks; social-media media-rights/consent checks; marketing-copy transparency and regulated-claims checks.

### Changed
- Updated the README to distinguish the five initial pilot cases from the expanded scenario evaluation records.
- Extended repository validation to check local Markdown links in root documentation and all other repository Markdown files, with a regression test for root-level links.
- Pinned `actions/checkout` and `actions/setup-python` in the CI workflow to immutable commit SHAs to reduce mutable-tag supply-chain risk.
- Refreshed `SOURCES.md` with current official OpenAI Skills and evaluation documentation links and the verification date.
- Hardened installer target validation to reject reparse-point ancestors before creating the destination, with a Windows regression test for junction-based paths.
- Clarified in the README that non-forced installation is file-level: missing files are added while untracked and locally modified files are preserved.
- Added `VERSION` (`0.1.0`) as the current development version and documented Semantic Versioning, release checks, manual GitHub Releases, and update steps in `RELEASING.md`.
- Clarified in the README that `0.1.0` is a development version marker and not a published GitHub Release.
- Added a Windows regression test for rolling back from a newer simulated installation to an older one, including restoration of removed files and cleanup of newer-only files.
- Documented the tested manual rollback procedure and updated repository self-links to the organization address.
- Added a transaction journal and verified backups for installer-managed destination paths and the manifest; the next run attempts guarded rollback after an interrupted update.
- Added a Windows regression scenario that interrupts an update after a file mutation and verifies recovery on the next invocation.


### Added
- Recorded the automation-vps webhook evaluation and strengthened atomic event acceptance to prevent lost events between deduplication and queue insertion.

### Changed
- Updated automation-vps webhook guidance to require durable atomic enqueue and idempotent worker-side effects.

### Added
- Recorded the synthetic `trading-bot-audit` ledger evaluation covering partial fills, duplicate event delivery, fees, funding and closed-trade statistics.

### Added
- Recorded a multi-module `python-development` pilot tracing an environment-variable type mismatch from settings through a worker call, with four passing regression checks.

### Added
- Recorded the synthetic `product-images` mask-quality pilot, including the limits of alpha-channel metadata checks.

### Added
- Recorded the simulated `python-development` traceback, minimal input-validation correction, and four passing regression checks.

### Added
- Recorded the simulated `crypto-futures-risk` linear-position calculation pilot.

### Changed
- Strengthened `devops-vps` secret-handling guidance: systemd unit output, journal entries, and process command lines are treated as potentially sensitive and must be redacted before sharing.
- Recorded the simulated `devops-vps` pilot evaluation and its safety-guidance correction.


### Added
- Recorded the synthetic `crypto-market-analysis` evaluation covering conflicting timeframes, market breadth, BTC dominance, funding, open interest and liquidity deterioration.


### Added
- Recorded a synthetic `crypto-research` evaluation covering fees, funding, chronological train/validation/out-of-sample separation, and the limits of a small sample.

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
