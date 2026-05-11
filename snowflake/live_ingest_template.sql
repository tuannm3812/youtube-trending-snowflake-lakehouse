-- =============================================================================
-- YouTube Trending Snowflake Lakehouse
-- Optional live-data ingestion template
--
-- 1. Run scripts/fetch_youtube_trending.py.
-- 2. Upload data/raw/live/youtube_trending_live_<date>.csv to @stage_youtube_raw/live/.
-- 3. Run this script to append the live extract to Snowflake.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE ASSIGNMENT_1;
USE SCHEMA PUBLIC;

ALTER SESSION SET QUERY_TAG = 'YOUTUBE_SNOWFLAKE_LIVE_INGEST';

CREATE OR REPLACE FILE FORMAT ff_youtube_live_csv
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null', 'NaN')
  EMPTY_FIELD_AS_NULL = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

CREATE TABLE IF NOT EXISTS table_youtube_live_trending (
  country STRING,
  video_id STRING,
  title STRING,
  published_at TIMESTAMP_NTZ,
  channel_id STRING,
  channel_title STRING,
  category_id NUMBER,
  trending_date DATE,
  view_count NUMBER,
  likes NUMBER,
  comment_count NUMBER,
  thumbnail_link STRING,
  description STRING,
  fetched_at TIMESTAMP_TZ,
  loaded_at TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO table_youtube_live_trending (
  country,
  video_id,
  title,
  published_at,
  channel_id,
  channel_title,
  category_id,
  trending_date,
  view_count,
  likes,
  comment_count,
  thumbnail_link,
  description,
  fetched_at
)
FROM (
  SELECT
    $1::STRING AS country,
    $2::STRING AS video_id,
    $3::STRING AS title,
    TRY_TO_TIMESTAMP_TZ($4)::TIMESTAMP_NTZ AS published_at,
    $5::STRING AS channel_id,
    $6::STRING AS channel_title,
    TRY_TO_NUMBER($7) AS category_id,
    TRY_TO_DATE($8) AS trending_date,
    TRY_TO_NUMBER($9) AS view_count,
    TRY_TO_NUMBER($10) AS likes,
    TRY_TO_NUMBER($11) AS comment_count,
    $12::STRING AS thumbnail_link,
    $13::STRING AS description,
    TRY_TO_TIMESTAMP_TZ($14) AS fetched_at
  FROM @stage_youtube_raw/live/
)
FILE_FORMAT = ff_youtube_live_csv
PATTERN = '.*youtube_trending_live_.*[.]csv'
ON_ERROR = 'CONTINUE';

SELECT
  COUNT(*) AS live_rows,
  COUNT(DISTINCT country) AS live_country_count,
  MAX(fetched_at) AS latest_fetch_time
FROM table_youtube_live_trending;

