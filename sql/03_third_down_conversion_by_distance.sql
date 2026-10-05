-- =====================================================================
-- Q3. Third-down conversion rate by distance, with the Falcons' rank
--
-- Question: How often do the Falcons convert on 3rd down at each distance,
--           and where does that rank among all 32 teams?
-- Converted: nflverse's third_down_converted / third_down_failed flags.
--           A play counts only if one of them is set (drops 41 ambiguous
--           offensive-penalty plays). A first down from a defensive penalty
--           AFTER a failed play counts as a failure: the play didn't convert.
-- Scope:    2021-2025 regular season, 5 seasons pooled.
-- Skills:   multiple CTEs, CASE WHEN bucketing, UNION ALL,
--           window functions: RANK() and AVG() OVER (PARTITION BY ...).
-- =====================================================================

WITH third_downs AS (
    -- Step 1: every 3rd-down play, labeled with a distance bucket...
    SELECT
        posteam,
        CASE
            WHEN ydstogo = 1   THEN '1) 3rd & 1'
            WHEN ydstogo <= 3  THEN '2) 3rd & 2-3'
            WHEN ydstogo <= 6  THEN '3) 3rd & 4-6'
            WHEN ydstogo <= 10 THEN '4) 3rd & 7-10'
            ELSE                    '5) 3rd & 11+'
        END AS distance,
        third_down_converted AS converted
    FROM scrimmage_plays
    WHERE down = 3
      AND (third_down_converted = 1 OR third_down_failed = 1)

    UNION ALL

    -- ...plus a second copy of every play labeled 'All', so the overall
    -- rate gets ranked by the same steps below.
    SELECT posteam, '6) All 3rd downs', third_down_converted
    FROM scrimmage_plays
    WHERE down = 3
      AND (third_down_converted = 1 OR third_down_failed = 1)
),

team_rates AS (
    -- Step 2: one row per team per bucket.
    SELECT
        posteam,
        distance,
        COUNT(*)       AS attempts,
        SUM(converted) AS conversions,
        AVG(converted) AS conv_rate
    FROM third_downs
    GROUP BY posteam, distance
),

ranked AS (
    -- Step 3: window functions. PARTITION BY restarts the calculation for
    -- each bucket; unlike GROUP BY, every team's row is kept.
    SELECT
        *,
        RANK()         OVER (PARTITION BY distance ORDER BY conv_rate DESC) AS nfl_rank,
        COUNT(*)       OVER (PARTITION BY distance)                         AS teams,
        AVG(conv_rate) OVER (PARTITION BY distance)                         AS avg_team_rate
    FROM team_rates
)

-- Step 4: filter to the Falcons only AFTER ranking against everyone.
SELECT
    distance,
    attempts,
    conversions,
    ROUND(100.0 * conv_rate, 1)                        AS atl_conv_pct,
    ROUND(100.0 * avg_team_rate, 1)                    AS nfl_avg_pct,  -- average of the 32 team rates
    ROUND(100.0 * (conv_rate - avg_team_rate), 1)      AS diff_pct_pts,
    nfl_rank || ' of ' || teams                        AS atl_rank      -- 1 = best
FROM ranked
WHERE posteam = 'ATL'
ORDER BY distance;
