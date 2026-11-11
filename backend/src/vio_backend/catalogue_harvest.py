"""Fetch public FUNAAB programme/course pages into reviewable source snapshots.

This command never accesses login-protected services and never writes to Neon.
Its output is evidence for manual review, not an automatic production import.
"""

import argparse
import asyncio
from datetime import UTC, datetime
import json
from pathlib import Path
import re
from urllib.parse import urlparse

import httpx
from bs4 import BeautifulSoup


ALLOWED_HOSTS = {"funaab.edu.ng", "www.funaab.edu.ng"}
COURSE_CODE = re.compile(r"\b[A-Z]{2,5}\s?\d{3,4}\b")
DEFAULT_URLS = (
    "https://admission.funaab.edu.ng/2026/programmes.php",
    "https://funaab.edu.ng/mts-course-synopsis/",
)


def validate_public_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS | {"admission.funaab.edu.ng"}:
        raise ValueError("Only public HTTPS FUNAAB pages are allowed")


def extract_snapshot(url: str, html: str, fetched_at: str) -> dict:
    validate_public_url(url)
    soup = BeautifulSoup(html, "html.parser")
    for element in soup(["script", "style", "noscript"]):
        element.decompose()
    title = soup.title.get_text(" ", strip=True) if soup.title else ""
    text = "\n".join(line.strip() for line in soup.get_text("\n").splitlines() if line.strip())
    codes = sorted({match.group(0).replace(" ", "") for match in COURSE_CODE.finditer(text)})
    return {
        "source_url": url,
        "fetched_at": fetched_at,
        "page_title": title,
        "course_code_candidates": codes,
        "text": text,
    }


async def fetch_snapshot(client: httpx.AsyncClient, url: str) -> dict:
    validate_public_url(url)
    response = await client.get(url)
    validate_public_url(str(response.url))
    response.raise_for_status()
    return extract_snapshot(url, response.text, datetime.now(UTC).isoformat())


async def harvest(urls: tuple[str, ...]) -> list[dict]:
    async with httpx.AsyncClient(timeout=20, follow_redirects=True, headers={"User-Agent": "VIO-public-catalogue-research/0.1"}) as client:
        snapshots = []
        for url in urls:
            snapshots.append(await fetch_snapshot(client, url))
        return snapshots


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("docs/data/source_snapshots"))
    parser.add_argument("urls", nargs="*", default=DEFAULT_URLS)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    snapshots = asyncio.run(harvest(tuple(args.urls)))
    for index, snapshot in enumerate(snapshots, start=1):
        path = args.output / f"funaab-public-{index}.json"
        path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Saved public-source snapshot: {path} ({len(snapshot['course_code_candidates'])} code candidates)")


if __name__ == "__main__":
    main()
