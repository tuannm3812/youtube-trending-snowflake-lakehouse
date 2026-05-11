# Data Directory

This repository separates curated static inputs from generated or live API outputs.

- `raw/static/youtube_trending/`: Kaggle YouTube Trending CSV files by country.
- `raw/static/youtube_category/`: YouTube category JSON files by country.
- `raw/live/`: optional live YouTube API extracts created by `scripts/fetch_youtube_trending.py`.
- `processed/`: local analysis-ready exports or notebook outputs.

The original assignment pipeline staged these files in Azure Blob Storage and queried them from Snowflake external tables. Do not commit API keys, SAS tokens, or generated live extracts.
