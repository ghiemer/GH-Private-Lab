# Maintenance Task Proposals

## Typo Correction
- **Issue:** The German/English mixed comment in `docker-compose.yml` reads "# kein ports" which mixes singular and plural forms, making the message unclear.
- **Proposed Task:** Update the comment to proper English (e.g., "# no ports exposed; reachable only via Caddy") for clarity. 【F:docker-compose.yml†L71-L71】

## Bug Fix
- **Issue:** `scripts/backup.sh` tries to archive `backup.sh` from the project root even though the script lives under `scripts/`. As a result, the configuration archive never includes the backup script.
- **Proposed Task:** Change the entry in `CONFIG_ITEMS` to `scripts/backup.sh` (and adjust related documentation if needed) so the backup script is actually captured. 【F:scripts/backup.sh†L121-L140】

## Documentation Discrepancy
- **Issue:** The README instructs operators to copy and use a `deploy.sh` script that is not part of the repository, which can confuse anyone following the setup guide.
- **Proposed Task:** Either add the missing `deploy.sh` script or update the documentation to reflect the actual files provided. 【F:README.md†L60-L139】

## Test Improvement
- **Issue:** `scripts/backup.sh` contains non-trivial logic (e.g., selective volume archiving) without any automated test coverage, leaving regressions undetected.
- **Proposed Task:** Introduce a shell-based test (for example, using `bats`) that exercises the backup workflow, including the `archive_volume` helper and configuration bundle, to verify it handles present and missing volumes correctly. 【F:scripts/backup.sh†L90-L155】
