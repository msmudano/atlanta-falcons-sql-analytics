-- =====================================================================
-- Q8. Early-down pass rate in neutral situations, ranked by season
--
-- Question: When the game situation doesn't force the decision, how often
--           did the Falcons choose to pass on early downs, and how did that
--           rank among the 32 teams each season?
-- Neutral:  1st or 2nd down, score within 8 points (one possession), not in
--           the final 2 minutes of either half, no overtime. Score-based
--           rather than win-probability-based, so it needs no model.
-- Pass:     the `pass` (dropback) flag, so scrambles count as passes (Q2).
-- Why:      overall pass rate is driven by game state (trailing teams must
--           pass). This isolates play-calling TENDENCY.
-- Scope:    2021-2025 regular season, one row per Falcons season.
-- Skills:   CTEs, compound WHERE with NOT (...), window functions
--           RANK() and AVG() OVER (PARTITION BY season).
-- =====================================================================

WITH neutral AS (
    -- Step 1: early-down plays where the coach had a real choice.
    SELECT season, posteam, pass
    FROM scrimmage_plays
    WHERE down IN (1, 2)
      AND score_differential BETWEEN -8 AND 8
      AND qtr <= 4                                              -- no overtime
      AND NOT (qtr = 2 AND game_seconds_remaining <= 1920)      -- last 2 min of 1st half
      AND NOT (qtr = 4 AND game_seconds_remaining <= 120)       -- last 2 min of game
),

team_season AS (
    -- Step 2: neutral early-down pass rate per team per season, plus the
    -- all-situations pass rate for comparison.
    SELECT
        n.season,
        n.posteam,
        COUNT(*)    AS neutral_plays,
        AVG(n.pass) AS neutral_pass_rate,
        (SELECT AVG(s.pass)                         -- correlated subquery:
         FROM scrimmage_plays AS s                  -- runs once per team-season
         WHERE s.season = n.season AND s.posteam = n.posteam) AS overall_pass_rate
    FROM neutral AS n
    GROUP BY n.season, n.posteam
),

ranked AS (
    -- Step 3: rank within each season (league passing levels move year to year).
    SELECT
        *,
        RANK()                 OVER (PARTITION BY season ORDER BY neutral_pass_rate DESC) AS neutral_rank,
        RANK()                 OVER (PARTITION BY season ORDER BY overall_pass_rate DESC) AS overall_rank,
        AVG(neutral_pass_rate) OVER (PARTITION BY season)                                  AS league_neutral_rate
    FROM team_season
)

-- Step 4: Falcons only, after ranking.
SELECT
    season,
    neutral_plays,
    ROUND(100 * neutral_pass_rate, 1)                         AS atl_neutral_pass_pct,
    ROUND(100 * league_neutral_rate, 1)                       AS nfl_neutral_pass_pct,
    ROUND(100 * (neutral_pass_rate - league_neutral_rate), 1) AS diff_pct_pts,
    neutral_rank || ' of 32'                                  AS neutral_rank,   -- 1 = most pass-heavy
    ROUND(100 * overall_pass_rate, 1)                         AS atl_overall_pass_pct,
    overall_rank || ' of 32'                                  AS overall_rank
FROM ranked
WHERE posteam = 'ATL'
ORDER BY season;
