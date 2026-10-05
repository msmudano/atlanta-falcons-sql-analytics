-- =====================================================================
-- Q2. Pass rate by score margin and quarter: Falcons vs. the rest of the NFL
--
-- Question: How does the Falcons' run/pass mix change with the score and
--           the clock, compared with the other 31 teams?
-- Pass:     the `pass` flag (QB dropback), NOT play_type = 'pass'.
--           nflverse labels scrambles play_type = 'run' but pass = 1;
--           a scramble was a called pass, so it counts as a pass here.
-- Margin:   score_differential before the snap. 8 points = one possession
--           (TD + 2-pt), so 1-8 is "one score", 9+ is "multiple scores".
-- Scope:    2021-2025 regular season, quarters 1-4 (overtime excluded).
-- Skills:   CTE, CASE WHEN bucketing, pivot via conditional aggregation,
--           per-cell minimum sample size.
-- Output:   one row per margin bucket per team group; one column per quarter.
-- =====================================================================

WITH situational AS (
    -- Step 1: label each play with a team group and a score-margin bucket.
    SELECT
        CASE WHEN posteam = 'ATL' THEN 'ATL' ELSE 'Rest of NFL' END AS team,
        CASE
            WHEN score_differential <= -9 THEN '1) Down 9+'
            WHEN score_differential <= -1 THEN '2) Down 1-8'
            WHEN score_differential =   0 THEN '3) Tied'
            WHEN score_differential <=  8 THEN '4) Up 1-8'
            ELSE                               '5) Up 9+'
        END AS score_margin,
        qtr,
        pass                                  -- 1 = dropback, 0 = designed run
    FROM scrimmage_plays
    WHERE qtr <= 4                            -- drop overtime
)
-- Step 2: pivot quarters into columns. Each column averages `pass` over only
-- that quarter's plays (CASE returns NULL otherwise, and AVG skips NULLs).
-- A cell with fewer than 20 plays is left NULL instead of showing a noisy rate.
SELECT
    score_margin,
    team,
    COUNT(*) AS plays,
    CASE WHEN SUM(qtr = 1) >= 20 THEN ROUND(100.0 * AVG(CASE WHEN qtr = 1 THEN pass END), 1) END AS q1_pass_pct,
    CASE WHEN SUM(qtr = 2) >= 20 THEN ROUND(100.0 * AVG(CASE WHEN qtr = 2 THEN pass END), 1) END AS q2_pass_pct,
    CASE WHEN SUM(qtr = 3) >= 20 THEN ROUND(100.0 * AVG(CASE WHEN qtr = 3 THEN pass END), 1) END AS q3_pass_pct,
    CASE WHEN SUM(qtr = 4) >= 20 THEN ROUND(100.0 * AVG(CASE WHEN qtr = 4 THEN pass END), 1) END AS q4_pass_pct,
    ROUND(100.0 * AVG(pass), 1) AS all_qtrs_pass_pct
FROM situational
GROUP BY score_margin, team
ORDER BY score_margin, team;                  -- 'ATL' sorts before 'Rest of NFL'
