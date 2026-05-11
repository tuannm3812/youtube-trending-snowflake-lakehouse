-- =============================================================================
-- YouTube Trending Snowflake Lakehouse
-- Part 1: Raw ingestion and curated model build
--
-- Source files:
--   - <COUNTRY>_youtube_trending_data.csv
--   - <COUNTRY>_category_id.json
--
-- Notes:
--   - Replace the stage URL and credential placeholder before running.
--   - Prefer a Snowflake STORAGE INTEGRATION for production workloads.
--   - Never commit live cloud credentials.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS ASSIGNMENT_1;
CREATE SCHEMA IF NOT EXISTS ASSIGNMENT_1.PUBLIC;

USE DATABASE ASSIGNMENT_1;
USE SCHEMA PUBLIC;

ALTER SESSION SET QUERY_TAG = 'YOUTUBE_SNOWFLAKE_PART_1_INGESTION';

-- -----------------------------------------------------------------------------
-- 1. External stage
-- -----------------------------------------------------------------------------
CREATE OR REPLACE STAGE stage_youtube_raw
  URL = 'azure://<storage-account>.blob.core.windows.net/<container-name>'
  CREDENTIALS = (AZURE_SAS_TOKEN = '<AZURE_SAS_TOKEN>')
  COMMENT = 'Raw YouTube Trending CSV and category JSON files staged from Azure Blob Storage';

LIST @stage_youtube_raw;

-- -----------------------------------------------------------------------------
-- 2. File formats
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FILE FORMAT ff_youtube_trending_csv
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null', 'NaN')
  EMPTY_FIELD_AS_NULL = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

CREATE OR REPLACE FILE FORMAT ff_youtube_category_json
  TYPE = JSON
  STRIP_OUTER_ARRAY = FALSE;

-- -----------------------------------------------------------------------------
-- 3. External table over trending CSV files
-- -----------------------------------------------------------------------------
CREATE OR REPLACE EXTERNAL TABLE ex_youtube_trending_csv (
  country          STRING AS (REGEXP_SUBSTR(METADATA$FILENAME, '([A-Z]{2})_youtube_trending_data[.]csv', 1, 1, 'e', 1)),
  video_id         STRING AS (VALUE:c1::STRING),
  title            STRING AS (VALUE:c2::STRING),
  published_at_raw STRING AS (VALUE:c3::STRING),
  channel_id       STRING AS (VALUE:c4::STRING),
  channel_title    STRING AS (VALUE:c5::STRING),
  category_id_raw  STRING AS (VALUE:c6::STRING),
  trending_date_raw STRING AS (VALUE:c7::STRING),
  view_count_raw   STRING AS (VALUE:c8::STRING),
  likes_raw        STRING AS (VALUE:c9::STRING),
  dislikes_raw     STRING AS (VALUE:c10::STRING),
  comment_count_raw STRING AS (VALUE:c11::STRING),
  source_file_name STRING AS (METADATA$FILENAME)
)
WITH LOCATION = @stage_youtube_raw
FILE_FORMAT = ff_youtube_trending_csv
PATTERN = '.*[A-Z]{2}_youtube_trending_data[.]csv';

ALTER EXTERNAL TABLE ex_youtube_trending_csv REFRESH;

-- -----------------------------------------------------------------------------
-- 4. Curated trending table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE table_youtube_trending (
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
  dislikes NUMBER,
  comment_count NUMBER,
  source_file_name STRING,
  loaded_at TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT OVERWRITE INTO table_youtube_trending (
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
  dislikes,
  comment_count,
  source_file_name
)
SELECT
  country,
  NULLIF(TRIM(video_id), '') AS video_id,
  NULLIF(TRIM(title), '') AS title,
  TRY_TO_TIMESTAMP_TZ(published_at_raw)::TIMESTAMP_NTZ AS published_at,
  NULLIF(TRIM(channel_id), '') AS channel_id,
  NULLIF(TRIM(channel_title), '') AS channel_title,
  TRY_TO_NUMBER(category_id_raw) AS category_id,
  TRY_TO_TIMESTAMP_TZ(trending_date_raw)::DATE AS trending_date,
  TRY_TO_NUMBER(view_count_raw) AS view_count,
  TRY_TO_NUMBER(likes_raw) AS likes,
  TRY_TO_NUMBER(dislikes_raw) AS dislikes,
  TRY_TO_NUMBER(comment_count_raw) AS comment_count,
  source_file_name
FROM ex_youtube_trending_csv;

-- -----------------------------------------------------------------------------
-- 5. External table and view over category JSON files
-- -----------------------------------------------------------------------------
CREATE OR REPLACE EXTERNAL TABLE ex_youtube_category_json
WITH LOCATION = @stage_youtube_raw
FILE_FORMAT = ff_youtube_category_json
PATTERN = '.*[A-Z]{2}_category_id[.]json';

ALTER EXTERNAL TABLE ex_youtube_category_json REFRESH;

CREATE OR REPLACE VIEW v_youtube_category AS
SELECT
  REGEXP_SUBSTR(METADATA$FILENAME, '([A-Z]{2})_category_id[.]json', 1, 1, 'e', 1) AS country,
  TRY_TO_NUMBER(category.value:"id"::STRING) AS category_id,
  NULLIF(TRIM(category.value:"snippet":"title"::STRING), '') AS category_title,
  METADATA$FILENAME AS source_file_name
FROM ex_youtube_category_json,
  LATERAL FLATTEN(INPUT => VALUE:"items") AS category;

CREATE OR REPLACE TABLE table_youtube_category AS
SELECT
  country,
  category_id,
  category_title,
  source_file_name,
  CURRENT_TIMESTAMP() AS loaded_at
FROM v_youtube_category;

-- -----------------------------------------------------------------------------
-- 6. Final analytical table
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE table_youtube_final AS
SELECT
  UUID_STRING() AS id,
  trending.country,
  trending.video_id,
  trending.title,
  trending.published_at,
  trending.channel_id,
  trending.channel_title,
  trending.category_id,
  category.category_title,
  trending.trending_date,
  trending.view_count,
  trending.likes,
  trending.dislikes,
  trending.comment_count,
  trending.source_file_name,
  CURRENT_TIMESTAMP() AS loaded_at
FROM table_youtube_trending AS trending
LEFT JOIN table_youtube_category AS category
  ON trending.country = category.country
  AND trending.category_id = category.category_id;

-- -----------------------------------------------------------------------------
-- 7. Validation checks
-- -----------------------------------------------------------------------------
SELECT
  'table_youtube_trending' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT country) AS country_count,
  MIN(trending_date) AS min_trending_date,
  MAX(trending_date) AS max_trending_date
FROM table_youtube_trending
UNION ALL
SELECT
  'table_youtube_final' AS table_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT country) AS country_count,
  MIN(trending_date) AS min_trending_date,
  MAX(trending_date) AS max_trending_date
FROM table_youtube_final;

SELECT
  country,
  COUNT(*) AS row_count
FROM table_youtube_final
GROUP BY country
ORDER BY country;

SELECT
  country,
  category_id,
  COUNT(*) AS missing_category_rows
FROM table_youtube_final
WHERE category_title IS NULL
GROUP BY country, category_id
ORDER BY missing_category_rows DESC, country, category_id
LIMIT 20;

