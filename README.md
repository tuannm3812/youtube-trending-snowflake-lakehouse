# YouTube Trending Snowflake Lakehouse

![Snowflake](https://img.shields.io/badge/Snowflake-Data%20Warehouse-29B5E8?logo=snowflake&logoColor=white)
![YouTube Data API](https://img.shields.io/badge/YouTube%20Data%20API-Live%20Refresh-FF0000?logo=youtube&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?logo=python&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-Analytics-336791)
![Status](https://img.shields.io/badge/Status-Portfolio%20Ready-0B6E69)

<p align="center">
  <img src="assets/youtube-trending-hero.jpeg" alt="YouTube analytics dashboard on a laptop" width="86%">
</p>

Snowflake lakehouse pipeline for ingesting, cleaning, and analyzing multi-country YouTube Trending data, with optional live refreshes from the YouTube Data API.

## Overview

This repository packages a Big Data Engineering assignment as a polished data science project. It combines static Kaggle YouTube Trending files, Snowflake external tables, SQL-based cleaning, reproducible analytics, and a Python live-refresh utility.

The workflow is intentionally simple and auditable:

1. Store raw YouTube Trending CSV and category JSON files under `data/raw/static/`.
2. Stage those files in Azure Blob Storage for Snowflake ingestion.
3. Build external tables over raw CSV/JSON files.
4. Materialize typed Snowflake tables for analytics.
5. Clean category, ID, and duplicate issues deterministically.
6. Run analytical and business-question SQL.
7. Optionally fetch current YouTube most-popular videos through the YouTube Data API.

## Project Highlights

- Historical dataset period from the report: `2020-08-12` to `2024-04-15`.
- Countries covered: `BR`, `CA`, `DE`, `FR`, `GB`, `IN`, `JP`, `KR`, `MX`, `US`.
- Final cleaned Snowflake table: `TABLE_YOUTUBE_FINAL`.
- Final cleaned row count: `2,597,494`.
- Global recommendation after excluding `Music` and `Entertainment`: `Sports`.
- Key business finding: the global Sports strategy matches only 3 of 10 countries, so localized category strategy matters.

## Data

Static Kaggle inputs are included under:

```text
data/raw/static/youtube_trending/
data/raw/static/youtube_category/
```

Generated live extracts are written to:

```text
data/raw/live/
```

The live output folder is ignored by Git so API-derived refreshes do not pollute the repository history.

## Repository Structure

```text
.
|-- assets/
|   |-- banner.svg
|   `-- youtube-trending-hero.jpeg
|-- data/
|   |-- README.md
|   |-- processed/
|   `-- raw/
|       |-- live/
|       `-- static/
|           |-- youtube_category/
|           `-- youtube_trending/
|-- docs/
|   `-- project_summary.md
|-- reports/
|   `-- youtube_snowflake_assignment_report.docx
|-- scripts/
|   `-- fetch_youtube_trending.py
|-- snowflake/
|   |-- live_ingest_template.sql
|   |-- part_1_ingestion.sql
|   |-- part_2_cleaning.sql
|   |-- part_3_analysis.sql
|   `-- part_4_business_question.sql
|-- .env.example
|-- .gitattributes
|-- .gitignore
|-- pyproject.toml
|-- README.md
`-- requirements.txt
```

## Snowflake Workflow

Run the SQL scripts in order:

```text
snowflake/part_1_ingestion.sql
snowflake/part_2_cleaning.sql
snowflake/part_3_analysis.sql
snowflake/part_4_business_question.sql
```

Before running `part_1_ingestion.sql`, upload the static files to your Azure Blob container and update:

```sql
URL = 'azure://<storage-account>.blob.core.windows.net/<container-name>'
CREDENTIALS = (AZURE_SAS_TOKEN = '<AZURE_SAS_TOKEN>')
```

For production, replace the SAS-token pattern with a Snowflake storage integration.

## Live YouTube API Refresh

The live refresh script uses the official YouTube Data API v3 `videos.list` endpoint with `chart=mostPopular`.

Set up the environment:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```

Add your API key to `.env`:

```text
YOUTUBE_API_KEY=your_key_here
```

Fetch live data:

```powershell
python scripts/fetch_youtube_trending.py --regions US GB JP KR IN --max-results 50
```

The script writes:

- `data/raw/live/youtube_trending_live_<date>.csv`
- `data/raw/live/<region>_category_<date>.json`
- `data/raw/live/manifest_<date>.json`

After uploading the live CSV to your cloud stage, use:

```text
snowflake/live_ingest_template.sql
```

## Analytical Questions

The SQL answers:

- Top 3 most-viewed Gaming videos per country on `2024-04-01`.
- Distinct videos with `BTS` in the title by country.
- Monthly most-viewed videos and likes ratio for 2024.
- Dominant category per country from 2022 onward.
- Most prolific channel by distinct videos.
- Best non-Music/non-Entertainment category for trending probability.

## Security Notes

Do not commit live credentials. The Snowflake stage script uses placeholders for cloud credentials, and `.env` is ignored by Git.
