# Project Summary

This project packages the 94693 Big Data Engineering Assignment 1 work as a professional data science repository.

The original pipeline ingests multi-country YouTube Trending CSV files and YouTube category JSON files from Azure Blob Storage into Snowflake external tables. It then materializes typed internal tables, joins trending rows to category metadata, cleans category and duplicate issues, and answers analysis and business questions from the final fact table.

Key results from the report:

- Analytical period: 2020-08-12 to 2024-04-15.
- Clean final table: `TABLE_YOUTUBE_FINAL`.
- Final record count after cleaning: 2,597,494 rows.
- Business recommendation: `Sports` is the best global non-Music/non-Entertainment category by distinct trending videos, but the strategy is not universal across countries.
- Localized category leaders include `Gaming` in several Western markets and `People & Blogs` in selected Asian markets.

