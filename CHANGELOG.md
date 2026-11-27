# Changelog

## 2026-11-27

### Added
- Added the server-security Skill with a practical Linux/VPS security checklist covering access control, SSH, network exposure, patching, encryption at rest and in transit, key management, TLS, databases, containers, backups, monitoring, and incident response.
- Added explicit safety boundaries: read-only audit by default, approval before changes, lockout prevention, secret redaction, and evidence preservation during incidents.
- Preserved the limited historical PASS notes for crypto-security and server-security as records 28–29; added reproducible current manual scenarios 30–31 with exact prompts and limitations.
- Added the historical automation-vps webhook evaluation summary as record 32 and a reproducible current webhook scenario as record 33; missing historical details are explicitly marked as unavailable.

### Changed
- Added official Telegram and MAX documentation sources; documented current MAX eligibility, API host/auth, HTTPS webhook and HTTP 200 error-body checkpoints, plus Telegram update-retention considerations.
- Extended the Python AST audit to detect keyword-based write modes, Path.open write modes, additional pathlib/os/shutil mutations, and os.open review candidates; added regression coverage and documented remaining false-negative limits.
- Recorded automated evaluation 34: 12 Python AST audit regression tests passed on Python 3.9, 3.12 and 3.14.
- Added the missing crypto-security entry to the English catalog and corrected its ready-skill count.
- Clarified that AI-Toolbox environment preflight executes detected PATH binaries with fixed version/help arguments and therefore requires a trusted PATH.
- Hardened crypto-security dependency-scanning guidance: pip-audit dependency resolution can run package build/install processes, and Trivy's exit code must not be treated as a findings-free guarantee without configuration.
- Added official cryptography, backup, SBOM, signing and scanner sources for crypto-security; documented tool limitations and Gitleaks maintenance status.
- Extended repository validation to require both catalogs to list exactly the Skills present in the repository; added a regression test for missing and unexpected catalog entries.

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
