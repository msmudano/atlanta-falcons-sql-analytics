-- =====================================================================
-- Q1. Success rate by down and distance: Falcons vs. the rest of the NFL
--
-- Question: In each down-and-distance situation, how often does a Falcons
--           play succeed compared with the other 31 teams?
-- Success:  yardage-based, defined once in the scrimmage_plays view
--           (1st: >=40% of ydstogo, 2nd: >=60%, 3rd/4th: 100%).
-- Scope:    2021-2025 regular season, pass + run plays.
-- Skills:   CTE, CASE WHEN bucketing, conditional aggregation,
--           GROUP BY with HAVING.
-- =====================================================================

WITH bucketed AS (
    -- Step 1: label every play with a distance bucket.
    SELECT
        posteam,
        down,
        CASE
            WHEN ydstogo <= 3  THEN '1) Short (1-3)'
            WHEN ydstogo <= 6  THEN '2) Medium (4-6)'
            WHEN ydstogo <= 10 THEN '3) Long (7-10)'
            ELSE                    '4) Very long (11+)'
        END AS distance_bucket,    -- number prefix makes ORDER BY sort sensibly
        is_success
    FROM scrimmage_plays
)
-- Step 2: one row per down + bucket, with ATL and the rest of the NFL side by side.
SELECT
    down,
    distance_bucket,

    -- CASE returns NULL for non-ATL rows; COUNT and AVG skip NULLs,
    -- so these only "see" Falcons plays.
    COUNT(CASE WHEN posteam =  'ATL' THEN 1 END)                     AS atl_plays,
    ROUND(100.0 * AVG(CASE WHEN posteam =  'ATL' THEN is_success END), 1) AS atl_success_pct,

    COUNT(CASE WHEN posteam <> 'ATL' THEN 1 END)                     AS nfl_plays,
    ROUND(100.0 * AVG(CASE WHEN posteam <> 'ATL' THEN is_success END), 1) AS nfl_success_pct,

    -- Positive = Falcons better than the rest of the league.
    ROUND(100.0 * (AVG(CASE WHEN posteam =  'ATL' THEN is_success END)
                 - AVG(CASE WHEN posteam <> 'ATL' THEN is_success END)), 1) AS diff_pct_pts
FROM bucketed
GROUP BY down, distance_bucket
HAVING COUNT(CASE WHEN posteam = 'ATL' THEN 1 END) >= 30   -- drop tiny Falcons samples
ORDER BY down, distance_bucket;
