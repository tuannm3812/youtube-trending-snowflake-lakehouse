-- =============================================================================
-- YouTube Trending Snowflake Lakehouse
-- Part 2: Data quality checks and deterministic cleaning
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE ASSIGNMENT_1;
USE SCHEMA PUBLIC;

ALTER SESSION SET QUERY_TAG = 'YOUTUBE_SNOWFLAKE_PART_2_CLEANING';

-- -----------------------------------------------------------------------------
-- Q1. Duplicate category labels after normalization
-- -----------------------------------------------------------------------------
WITH normalized_categories AS (
  SELECT
    LOWER(REGEXP_REPLACE(TRIM(category_title), '\\s+', ' ')) AS normalized_category_title
  FROM table_youtube_category
),
duplicate_titles AS (
  SELECT normalized_category_title
  FROM normalized_categories
  GROUP BY normalized_category_title
  HAVING COUNT(*) > 1
)
SELECT
  LISTAGG(normalized_category_title, ', ')
    WITHIN GROUP (ORDER BY normalized_category_title) AS duplicate_category_titles
FROM duplicate_titles;

-- -----------------------------------------------------------------------------
-- Q2. Category labels that appear in only one country
-- -----------------------------------------------------------------------------
WITH normalized_categories AS (
  SELECT
    LOWER(REGEXP_REPLACE(TRIM(category_title), '\\s+', ' ')) AS normalized_category_title,
    country
  FROM table_youtube_category
)
SELECT
  normalized_category_title,
  LISTAGG(DISTINCT country, ', ') WITHIN GROUP (ORDER BY country) AS countries
FROM normalized_categories
GROUP BY normalized_category_title
HAVING COUNT(DISTINCT country) = 1
ORDER BY normalized_category_title;

-- -----------------------------------------------------------------------------
-- Q3. Category IDs with missing category titles
-- -----------------------------------------------------------------------------
SELECT DISTINCT
  category_id
FROM table_youtube_final
WHERE category_title IS NULL
ORDER BY category_id;

SELECT
  country,
  category_id,
  COUNT(*) AS missing_category_rows
FROM table_youtube_final
WHERE category_title IS NULL
GROUP BY country, category_id
ORDER BY missing_category_rows DESC, country, category_id;

-- -----------------------------------------------------------------------------
-- Q4. Impute missing category titles with category_id text
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE table_youtube_final_backup_before_category_imputation AS
SELECT *
FROM table_youtube_final;

UPDATE table_youtube_final
SET category_title = TO_VARCHAR(category_id)
WHERE category_title IS NULL;

SELECT
  COUNT(*) AS remaining_null_category_titles
FROM table_youtube_final
WHERE category_title IS NULL;

-- -----------------------------------------------------------------------------
-- Q5. Videos without a channel title
-- -----------------------------------------------------------------------------
SELECT DISTINCT
  title
FROM table_youtube_final
WHERE channel_title IS NULL
  OR TRIM(channel_title) = ''
ORDER BY title;

-- -----------------------------------------------------------------------------
-- Q6. Remove spreadsheet-ingestion artifact video_id = '#NAME?'
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*) AS bad_video_id_rows_before_delete
FROM table_youtube_final
WHERE video_id = '#NAME?';

DELETE FROM table_youtube_final
WHERE video_id = '#NAME?';

SELECT
  COUNT(*) AS bad_video_id_rows_after_delete
FROM table_youtube_final
WHERE video_id = '#NAME?';

-- -----------------------------------------------------------------------------
-- Q7. Stage duplicate rows for audit
--
-- Business key: one row per video, country, and trending date.
-- Keep the highest-view row and stage lower-ranked rows for deletion.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE table_youtube_duplicates AS
WITH ranked_rows AS (
  SELECT
    id,
    video_id,
    country,
    trending_date,
    view_count,
    likes,
    comment_count,
    published_at,
    ROW_NUMBER() OVER (
      PARTITION BY video_id, country, trending_date
      ORDER BY
        view_count DESC NULLS LAST,
        likes DESC NULLS LAST,
        comment_count DESC NULLS LAST,
        published_at DESC NULLS LAST,
        id ASC
    ) AS duplicate_rank
  FROM table_youtube_final
)
SELECT *
FROM ranked_rows
WHERE duplicate_rank > 1;

SELECT
  COUNT(*) AS duplicate_rows_to_delete
FROM table_youtube_duplicates;

-- -----------------------------------------------------------------------------
-- Q8. Delete duplicate rows and validate uniqueness
-- -----------------------------------------------------------------------------
DELETE FROM table_youtube_final AS final
USING table_youtube_duplicates AS duplicate
WHERE final.id = duplicate.id;

WITH duplicate_groups AS (
  SELECT
    video_id,
    country,
    trending_date,
    COUNT(*) AS row_count
  FROM table_youtube_final
  GROUP BY video_id, country, trending_date
  HAVING COUNT(*) > 1
)
SELECT
  COUNT(*) AS remaining_duplicate_groups
FROM duplicate_groups;

-- -----------------------------------------------------------------------------
-- Q9. Final record count and country distribution
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*) AS final_row_count
FROM table_youtube_final;

SELECT
  country,
  COUNT(*) AS rows_after_cleaning
FROM table_youtube_final
GROUP BY country
ORDER BY country;

