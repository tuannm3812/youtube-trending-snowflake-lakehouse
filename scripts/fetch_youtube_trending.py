"""Fetch current YouTube most-popular videos for configured regions.

The historical assignment data comes from staged CSV/JSON files in Azure Blob Storage.
This script adds an optional live refresh path using the official YouTube Data API v3.
It writes API extracts to data/raw/live/ so they can be uploaded to cloud storage or
loaded into Snowflake with your preferred ingestion flow.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd
import requests
from dotenv import load_dotenv


API_BASE = "https://www.googleapis.com/youtube/v3"
DEFAULT_REGIONS = ["BR", "CA", "DE", "FR", "GB", "IN", "JP", "KR", "MX", "US"]


def request_json(endpoint: str, params: dict[str, Any]) -> dict[str, Any]:
    response = requests.get(f"{API_BASE}/{endpoint}", params=params, timeout=30)
    response.raise_for_status()
    return response.json()


def fetch_categories(api_key: str, region_code: str) -> list[dict[str, Any]]:
    payload = request_json(
        "videoCategories",
        {"part": "snippet", "regionCode": region_code, "key": api_key},
    )
    return payload.get("items", [])


def fetch_most_popular(
    api_key: str,
    region_code: str,
    max_results: int,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    page_token: str | None = None

    while len(rows) < max_results:
        params: dict[str, Any] = {
            "part": "snippet,statistics,contentDetails",
            "chart": "mostPopular",
            "regionCode": region_code,
            "maxResults": min(50, max_results - len(rows)),
            "key": api_key,
        }
        if page_token:
            params["pageToken"] = page_token

        payload = request_json("videos", params)
        rows.extend(payload.get("items", []))
        page_token = payload.get("nextPageToken")
        if not page_token:
            break

    return rows


def normalize_video(item: dict[str, Any], region_code: str, fetched_at: str) -> dict[str, Any]:
    snippet = item.get("snippet", {})
    stats = item.get("statistics", {})

    return {
        "country": region_code,
        "video_id": item.get("id"),
        "title": snippet.get("title"),
        "published_at": snippet.get("publishedAt"),
        "channel_id": snippet.get("channelId"),
        "channel_title": snippet.get("channelTitle"),
        "category_id": snippet.get("categoryId"),
        "trending_date": fetched_at[:10],
        "view_count": int(stats.get("viewCount", 0)),
        "likes": int(stats.get("likeCount", 0)) if "likeCount" in stats else None,
        "comment_count": int(stats.get("commentCount", 0)) if "commentCount" in stats else None,
        "thumbnail_link": snippet.get("thumbnails", {}).get("high", {}).get("url"),
        "description": snippet.get("description"),
        "fetched_at": fetched_at,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch live YouTube trending data by region.")
    parser.add_argument(
        "--regions",
        nargs="+",
        default=DEFAULT_REGIONS,
        help="ISO-style YouTube region codes to fetch, e.g. US GB JP.",
    )
    parser.add_argument(
        "--max-results",
        type=int,
        default=50,
        help="Maximum videos per region. YouTube allows up to 50 per request.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/raw/live"),
        help="Directory for CSV and JSON outputs.",
    )
    return parser.parse_args()


def main() -> None:
    load_dotenv()
    args = parse_args()
    api_key = os.getenv("YOUTUBE_API_KEY")
    if not api_key:
        raise SystemExit("Missing YOUTUBE_API_KEY. Copy .env.example to .env and add your key.")

    fetched_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    run_date = fetched_at[:10]
    args.output_dir.mkdir(parents=True, exist_ok=True)

    all_rows: list[dict[str, Any]] = []
    manifest: dict[str, Any] = {
        "fetched_at": fetched_at,
        "regions": args.regions,
        "max_results": args.max_results,
        "files": [],
    }

    for region in args.regions:
        region_code = region.upper()
        videos = fetch_most_popular(api_key, region_code, args.max_results)
        rows = [normalize_video(item, region_code, fetched_at) for item in videos]
        all_rows.extend(rows)

        categories = fetch_categories(api_key, region_code)
        category_path = args.output_dir / f"{region_code.lower()}_category_{run_date}.json"
        category_path.write_text(json.dumps({"items": categories}, indent=2), encoding="utf-8")
        manifest["files"].append(str(category_path))

    csv_path = args.output_dir / f"youtube_trending_live_{run_date}.csv"
    pd.DataFrame(all_rows).to_csv(csv_path, index=False)
    manifest["files"].append(str(csv_path))

    manifest_path = args.output_dir / f"manifest_{run_date}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote {len(all_rows)} video rows to {csv_path}")
    print(f"Wrote run manifest to {manifest_path}")


if __name__ == "__main__":
    main()

