-- =============================================================================
-- YouTube Trending Snowflake Lakehouse
-- Part 4: Business question
--
-- Question:
--   Excluding Music and Entertainment, which category is the best bet to appear
--   in Trending overall, and does this strategy work in every country?
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE ASSIGNMENT_1;
USE SCHEMA PUBLIC;

ALTER SESSION SET QUERY_TAG = 'YOUTUBE_SNOWFLAKE_PART_4_BUSINESS_QUESTION';

-- -----------------------------------------------------------------------------
-- 1. Global category leaderboard
-- -----------------------------------------------------------------------------
WITH eligible_videos AS (
  SELECT
    country,
    category_title,
    video_id,
    view_count
  FROM table_youtube_final
  WHERE category_title NOT IN ('Music', 'Entertainment')
),
global_category_metrics AS (
  SELECT
    category_title,
    COUNT(DISTINCT video_id) AS distinct_videos,
    COUNT(*) AS video_days,
    MEDIAN(view_count) AS median_view_count,
    AVG(view_count) AS avg_view_count,
    MAX(view_count) AS max_view_count
  FROM eligible_videos
  GROUP BY category_title
),
global_total AS (
  SELECT
    COUNT(DISTINCT video_id) AS total_global_distinct_videos
  FROM eligible_videos
)
SELECT
  metrics.category_title,
  metrics.distinct_videos,
  total.total_global_distinct_videos,
  TRUNC(
    (metrics.distinct_videos / NULLIF(total.total_global_distinct_videos, 0)) * 100,
    2
  ) AS pct_of_global_distinct,
  metrics.video_days,
  metrics.median_view_count,
  metrics.avg_view_count,
  metrics.max_view_count
FROM global_category_metrics AS metrics
CROSS JOIN global_total AS total
ORDER BY
  metrics.distinct_videos DESC,
  metrics.video_days DESC,
  metrics.median_view_count DESC,
  metrics.category_title ASC;

-- -----------------------------------------------------------------------------
-- 2. Global top recommendation
-- -----------------------------------------------------------------------------
WITH eligible_videos AS (
  SELECT
    category_title,
    video_id
  FROM table_youtube_final
  WHERE category_title NOT IN ('Music', 'Entertainment')
),
ranked_categories AS (
  SELECT
    category_title,
    COUNT(DISTINCT video_id) AS distinct_videos,
    COUNT(*) AS video_days,
    ROW_NUMBER() OVER (
      ORDER BY
        COUNT(DISTINCT video_id) DESC,
        COUNT(*) DESC,
        category_title ASC
    ) AS category_rank
  FROM eligible_videos
  GROUP BY category_title
)
SELECT
  category_title AS global_recommended_category,
  distinct_videos,
  video_days
FROM ranked_categories
WHERE category_rank = 1;

-- -----------------------------------------------------------------------------
-- 3. Country-level validation of the global recommendation
-- -----------------------------------------------------------------------------
WITH eligible_videos AS (
  SELECT
    country,
    category_title,
    video_id
  FROM table_youtube_final
  WHERE category_title NOT IN ('Music', 'Entertainment')
),
country_category_metrics AS (
  SELECT
    country,
    category_title,
    COUNT(DISTINCT video_id) AS distinct_videos
  FROM eligible_videos
  GROUP BY country, category_title
),
ranked_country_categories AS (
  SELECT
    country,
    category_title,
    distinct_videos,
    ROW_NUMBER() OVER (
      PARTITION BY country
      ORDER BY distinct_videos DESC, category_title ASC
    ) AS category_rank
  FROM country_category_metrics
)
SELECT
  country,
  category_title AS country_top_category,
  distinct_videos AS distinct_videos_in_top_category
FROM ranked_country_categories
WHERE category_rank = 1
ORDER BY country;

-- -----------------------------------------------------------------------------
-- 4. Compact global-vs-local fit summary
-- -----------------------------------------------------------------------------
WITH eligible_videos AS (
  SELECT
    country,
    category_title,
    video_id
  FROM table_youtube_final
  WHERE category_title NOT IN ('Music', 'Entertainment')
),
global_pick AS (
  SELECT
    category_title AS global_recommended_category
  FROM eligible_videos
  GROUP BY category_title
  QUALIFY ROW_NUMBER() OVER (
    ORDER BY COUNT(DISTINCT video_id) DESC, COUNT(*) DESC, category_title ASC
  ) = 1
),
country_category_metrics AS (
  SELECT
    country,
    category_title,
    COUNT(DISTINCT video_id) AS distinct_videos
  FROM eligible_videos
  GROUP BY country, category_title
),
country_picks AS (
  SELECT
    country,
    category_title AS country_top_category
  FROM country_category_metrics
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY country
    ORDER BY distinct_videos DESC, category_title ASC
  ) = 1
)
SELECT
  global_pick.global_recommended_category,
  SUM(IFF(country_picks.country_top_category = global_pick.global_recommended_category, 1, 0))
    AS countries_matching_global,
  COUNT(*) AS total_countries,
  TRUNC(
    (
      SUM(IFF(country_picks.country_top_category = global_pick.global_recommended_category, 1, 0))
      / NULLIF(COUNT(*), 0)
    ) * 100,
    2
  ) AS global_fit_pct
FROM country_picks
CROSS JOIN global_pick
GROUP BY global_pick.global_recommended_category;
