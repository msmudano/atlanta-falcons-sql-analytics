-- =====================================================================
-- Q9. How drives ended: Falcons vs. the league, with rank for each outcome
--
-- Question: How did Falcons drives end (touchdown, field goal, punt,
--           turnover, ...), and how does each outcome's frequency rank
--           among the 32 teams?
-- Drive:    same rules as Q4: one row per (game_id, fixed_drive, posteam)
--           with at least one non-kneel offensive snap; two-point tries
--           excluded. Kneel-only drives are dropped.
-- Outcome:  nflverse fixed_drive_result, with 'Opp touchdown' (a turnover
--           returned for a TD) folded into 'Turnover'.
-- Scope:    2021-2025 regular season, 5 seasons pooled.
-- Skills:   CTEs, HAVING, CASE WHEN, CROSS JOIN + LEFT JOIN + COALESCE to
--           fill in zero counts, window functions RANK() and AVG() OVER
--           (PARTITION BY outcome).
-- =====================================================================

WITH drives AS (
    -- Step 1: one row per offensive drive.
    SELECT game_id, fixed_drive, posteam,
           MAX(fixed_drive_result) AS result        -- constant within a drive
    FROM plays
    WHERE posteam IS NOT NULL
      AND two_point_attempt = 0
      AND play_type IN ('pass', 'run', 'field_goal', 'punt', 'qb_kneel', 'qb_spike')
    GROUP BY game_id, fixed_drive, posteam
    HAVING SUM(play_type <> 'qb_kneel') > 0         -- drop kneel-only drives
),

bucketed AS (
    -- Step 2: simplify the result labels.
    SELECT posteam,
           CASE WHEN result IN ('Turnover', 'Opp touchdown') THEN 'Turnover'
                ELSE result END AS outcome
    FROM drives
),

grid AS (
    -- Step 3: every team x every outcome, so a team with zero safeties
    -- still gets a row (with 0) instead of being missing.
    SELECT t.posteam, o.outcome
    FROM (SELECT DISTINCT posteam FROM bucketed) AS t
    CROSS JOIN (SELECT DISTINCT outcome FROM bucketed) AS o
),

team_outcome AS (
    -- Step 4: count each outcome per team (0 where none), as a share of
    -- that team's drives.
    SELECT
        g.posteam,
        g.outcome,
        COALESCE(c.n, 0)                     AS n,
        tot.drives,
        1.0 * COALESCE(c.n, 0) / tot.drives  AS rate
    FROM grid AS g
    LEFT JOIN (SELECT posteam, outcome, COUNT(*) AS n
               FROM bucketed GROUP BY posteam, outcome) AS c
           ON c.posteam = g.posteam AND c.outcome = g.outcome
    JOIN (SELECT posteam, COUNT(*) AS drives
          FROM bucketed GROUP BY posteam) AS tot
           ON tot.posteam = g.posteam
),

ranked AS (
    -- Step 5: compare teams within each outcome.
    SELECT
        *,
        RANK()    OVER (PARTITION BY outcome ORDER BY rate DESC) AS rank_most_often,
        AVG(rate) OVER (PARTITION BY outcome)                    AS avg_team_rate
    FROM team_outcome
)

-- Step 6: Falcons only.
SELECT
    outcome,
    n                                          AS atl_drives,
    ROUND(100 * rate, 1)                       AS atl_pct,
    ROUND(100 * avg_team_rate, 1)              AS nfl_avg_pct,
    ROUND(100 * (rate - avg_team_rate), 1)     AS diff_pct_pts,
    rank_most_often || ' of 32'                AS rank_most_often   -- 1 = happens most often
FROM ranked
WHERE posteam = 'ATL'
ORDER BY n DESC;
