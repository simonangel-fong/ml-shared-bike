"""Download Bike Share Toronto ridership data into data/raw/<year>/.

Source: https://open.toronto.ca/dataset/bike-share-toronto-ridership-data/
Toronto Open Data runs on CKAN; the API is documented at
https://docs.ckan.org/en/latest/api/

The dataset publishes one resource per year. For 2017 onward each resource is a
ZIP of monthly/quarterly CSVs, so this script resolves the resource URL from the
CKAN package metadata, downloads it, and extracts the CSVs per year.

Usage:
    python download-raw.py                    # 2019-2025 (default)
    python download-raw.py --years 2019 2020
    python download-raw.py --start 2019 --end 2025 --force
"""

from __future__ import annotations

import argparse
import logging
import re
import shutil
import sys
import zipfile
from pathlib import Path

import requests

# --- Configuration -----------------------------------------------------------

BASE_URL = "https://ckan0.cf.opendata.inter.prod-toronto.ca"
PACKAGE_ID = "bike-share-toronto-ridership-data"

# Repo root is the parent of data-engineer/
RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"

DEFAULT_START_YEAR = 2019
DEFAULT_END_YEAR = 2025

CHUNK_SIZE = 1024 * 1024  # 1 MiB
TIMEOUT = (10, 300)  # (connect, read) seconds

log = logging.getLogger("download")


# --- CKAN metadata -----------------------------------------------------------


def fetch_resources() -> list[dict]:
    """Return the resource list for the ridership package."""
    resp = requests.get(
        f"{BASE_URL}/api/3/action/package_show",
        params={"id": PACKAGE_ID},
        timeout=TIMEOUT,
    )
    resp.raise_for_status()
    payload = resp.json()
    if not payload.get("success"):
        raise RuntimeError(f"CKAN package_show failed: {payload.get('error')}")
    return payload["result"]["resources"]


def resource_year(resource: dict) -> int | None:
    """Extract the year a resource covers, or None if it is not year-scoped.

    Resource names look like 'bikeshare-ridership-2019.zip'. Multi-year and
    readme resources (e.g. 'bikeshare-ridership-2014-2015') are skipped: they
    predate the yearly ZIP layout and are outside the modelling window.
    """
    match = re.fullmatch(r"bikeshare-ridership-(\d{4})(?:\.zip)?", resource["name"])
    return int(match.group(1)) if match else None


def index_by_year(resources: list[dict]) -> dict[int, dict]:
    """Map year -> resource for the year-scoped resources."""
    indexed: dict[int, dict] = {}
    for resource in resources:
        year = resource_year(resource)
        if year is not None:
            indexed[year] = resource
    return indexed


# --- Download / extract ------------------------------------------------------


def download(url: str, dest: Path) -> None:
    """Stream `url` to `dest`, writing to a .part file first."""
    part = dest.with_suffix(dest.suffix + ".part")
    with requests.get(url, stream=True, timeout=TIMEOUT) as resp:
        resp.raise_for_status()
        total = int(resp.headers.get("Content-Length", 0))
        written = 0
        with part.open("wb") as handle:
            for chunk in resp.iter_content(CHUNK_SIZE):
                handle.write(chunk)
                written += len(chunk)
        if total and written != total:
            part.unlink(missing_ok=True)
            raise IOError(f"Truncated download: got {written} of {total} bytes")
    part.replace(dest)
    log.info("  downloaded %.1f MB", written / 1024 / 1024)


def extract_csvs(archive: Path, dest_dir: Path) -> list[Path]:
    """Extract CSV members of `archive` flat into `dest_dir`.

    Nested directories inside the archive are flattened and member names are
    reduced to their basename, which also guards against path traversal.
    """
    written: list[Path] = []
    with zipfile.ZipFile(archive) as zf:
        members = [
            info
            for info in zf.infolist()
            if not info.is_dir() and info.filename.lower().endswith(".csv")
        ]
        if not members:
            raise ValueError(f"No CSV members inside {archive.name}")
        for info in members:
            target = dest_dir / Path(info.filename).name
            with zf.open(info) as src, target.open("wb") as out:
                shutil.copyfileobj(src, out, CHUNK_SIZE)
            written.append(target)
    return written


def collect_year(year: int, resource: dict, *, force: bool) -> bool:
    """Download and extract one year. Returns True on success."""
    dest_dir = RAW_DIR / str(year)
    existing = sorted(dest_dir.glob("*.csv"))
    if existing and not force:
        log.info("[%s] skip - %d CSV file(s) already present", year, len(existing))
        return True

    dest_dir.mkdir(parents=True, exist_ok=True)
    url = resource["url"]
    archive = dest_dir / f"bikeshare-ridership-{year}.zip"

    log.info("[%s] downloading %s", year, url)
    try:
        download(url, archive)
        csvs = extract_csvs(archive, dest_dir)
    except (requests.RequestException, zipfile.BadZipFile, ValueError, IOError) as exc:
        log.error("[%s] failed: %s", year, exc)
        return False
    finally:
        archive.unlink(missing_ok=True)

    log.info("[%s] extracted %d CSV file(s) -> %s", year, len(csvs), dest_dir)
    for path in csvs:
        log.info("    %s (%.1f MB)", path.name, path.stat().st_size / 1024 / 1024)
    return True


# --- CLI ---------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download Bike Share Toronto ridership data into data/raw/<year>/."
    )
    parser.add_argument(
        "--years", type=int, nargs="+", help="explicit years (overrides --start/--end)"
    )
    parser.add_argument("--start", type=int, default=DEFAULT_START_YEAR)
    parser.add_argument("--end", type=int, default=DEFAULT_END_YEAR)
    parser.add_argument(
        "--force", action="store_true", help="re-download years already on disk"
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    wanted = args.years if args.years else list(range(args.start, args.end + 1))

    available = index_by_year(fetch_resources())
    log.info("Available years: %s", ", ".join(str(y) for y in sorted(available)))

    missing = [y for y in wanted if y not in available]
    for year in missing:
        log.warning("[%s] no resource published - skipping", year)

    failed = [
        year
        for year in wanted
        if year in available and not collect_year(year, available[year], force=args.force)
    ]

    if failed or missing:
        log.error(
            "Done with problems - failed: %s; unavailable: %s",
            failed or "none",
            missing or "none",
        )
        return 1

    log.info("Done - %d year(s) in %s", len(wanted), RAW_DIR)
    return 0


if __name__ == "__main__":
    sys.exit(main())
