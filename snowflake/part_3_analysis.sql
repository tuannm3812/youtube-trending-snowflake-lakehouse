-- =============================================================================
-- YouTube Trending Snowflake Lakehouse
-- Part 3: Reproducible analytical queries
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE ASSIGNMENT_1;
USE SCHEMA PUBLIC;

ALTER SESSION SET QUERY_TAG = 'YOUTUBE_SNOWFLAKE_PART_3_ANALYSIS';

-- -----------------------------------------------------------------------------
-- Q1. Top 3 most-viewed Gaming videos per country on 2024-04-01
-- -----------------------------------------------------------------------------
WITH gaming_videos AS (
  SELECT
    country,
    title,
    channel_title,
    view_count,
    likes,
    comment_count,
    published_at,
    video_id
  FROM table_youtube_final
  WHERE trending_date = '2024-04-01'
    AND LOWER(TRIM(category_title)) = 'gaming'
),
ranked_videos AS (
  SELECT
    country,
    title,
    channel_title,
    view_count,
    ROW_NUMBER() OVER (
      PARTITION BY country
      ORDER BY
        view_count DESC NULLS LAST,
        likes DESC NULLS LAST,
        comment_count DESC NULLS LAST,
        published_at DESC NULLS LAST,
        video_id ASC
    ) AS rank_in_country
  FROM gaming_videos
)
SELECT
  country,
  title,
  channel_title,
  view_count,
  rank_in_country
FROM ranked_videos
WHERE rank_in_country <= 3
ORDER BY country, rank_in_country;

-- -----------------------------------------------------------------------------
-- Q2. Distinct videos with "BTS" in the title, by country
-- -----------------------------------------------------------------------------
SELECT
  country,
  COUNT(DISTINCT video_id) AS distinct_video_count
FROM table_youtube_final
WHERE title ILIKE '%BTS%'
GROUP BY country
ORDER BY distinct_video_count DESC, country;

-- -----------------------------------------------------------------------------
-- Q3. Monthly most-viewed videos in 2024 with likes ratio
-- -----------------------------------------------------------------------------
WITH videos_2024 AS (
  SELECT
    country,
    TO_VARCHAR(DATE_TRUNC('month', trending_date), 'YYYY-MM') AS year_month,
    title,
    channel_title,
    category_title,
    video_id,
    view_count,
    likes
  FROM table_youtube_final
  WHERE trending_date >= '2024-01-01'
    AND trending_date < '2025-01-01'
),
ranked_monthly_videos AS (
  SELECT
    country,
    year_month,
    title,
    channel_title,
    category_title,
    view_count,
    TRUNC((COALESCE(likes, 0) / NULLIF(view_count, 0)) * 100, 2) AS likes_ratio_pct,
    ROW_NUMBER() OVER (
      PARTITION BY country, year_month
      ORDER BY view_count DESC NULLS LAST, video_id ASC
    ) AS month_rank
  FROM videos_2024
)
SELECT
  country,
  year_month,
  title,
  channel_title,
  category_title,
  view_count,
  likes_ratio_pct
FROM ranked_monthly_videos
WHERE month_rank = 1
ORDER BY year_month, country;

-- -----------------------------------------------------------------------------
-- Q4. Dominant category by country from 2022 onward
-- -----------------------------------------------------------------------------
WITH videos_from_2022 AS (
  SELECT
    country,
    category_title,
    video_id
  FROM table_youtube_final
  WHERE trending_date >= '2022-01-01'
),
country_totals AS (
  SELECT
    country,
    COUNT(DISTINCT video_id) AS total_country_videos
  FROM videos_from_2022
  GROUP BY country
),
category_totals AS (
  SELECT
    country,
    category_title,
    COUNT(DISTINCT video_id) AS total_category_videos
  FROM videos_from_2022
  GROUP BY country, category_title
),
ranked_categories AS (
  SELECT
    category_totals.country,
    category_totals.category_title,
    category_totals.total_category_videos,
    country_totals.total_country_videos,
    TRUNC(
      (category_totals.total_category_videos / NULLIF(country_totals.total_country_videos, 0)) * 100,
      2
    ) AS category_share_pct,
    ROW_NUMBER() OVER (
      PARTITION BY category_totals.country
      ORDER BY category_totals.total_category_videos DESC, category_totals.category_title ASC
    ) AS category_rank
  FROM category_totals
  INNER JOIN country_totals
    ON category_totals.country = country_totals.country
)
SELECT
  country,
  category_title,
  total_category_videos,
  total_country_videos,
  category_share_pct
FROM ranked_categories
WHERE category_rank = 1
ORDER BY category_title, country;

-- -----------------------------------------------------------------------------
-- Q5. Channel with the most distinct videos globally
-- -----------------------------------------------------------------------------
WITH channel_counts AS (
  SELECT
    channel_title,
    COUNT(DISTINCT video_id) AS distinct_videos
  FROM table_youtube_final
  WHERE channel_title IS NOT NULL
    AND TRIM(channel_title) <> ''
  GROUP BY channel_title
)
SELECT
  channel_title,
  distinct_videos
FROM channel_counts
QUALIFY ROW_NUMBER() OVER (
  ORDER BY distinct_videos DESC, channel_title ASC
) = 1;

