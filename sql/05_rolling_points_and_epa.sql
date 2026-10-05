-- =====================================================================
-- Q5. Falcons rolling 4-game averages: points scored and offensive EPA/play
--
-- Question: Game by game, how did the Falcons' scoring trend over a rolling
--           4-game window, and did the offense's underlying efficiency
--           (EPA per play) move with it?
-- Window:   resets each season (PARTITION BY season). In weeks 1-3 the
--           average covers only the games played so far; games_in_window
--           says how many (1-4). The window counts GAMES, so bye weeks
--           are skipped, not treated as zeros.
-- Points:   the Falcons' final score (offense, defense, special teams).
-- EPA/play: mean EPA of Falcons scrimmage plays in that game. The rolling
--           value averages the per-game numbers, so each game counts equally.
-- Scope:    2021-2025 regular season, 85 Falcons games.
-- Skills:   JOIN of two pre-aggregated CTEs, CASE WHEN, window functions
--           LAG(), AVG() and COUNT() over a ROWS frame, named WINDOW clause.
-- =====================================================================

WITH atl_games AS (
    -- Step 1: one row per Falcons game, from the Falcons' point of view.
    SELECT
        game_id,
        season,
        week,
        CASE WHEN home_team = 'ATL' THEN 'Home'     ELSE 'Away'     END AS venue,
        CASE WHEN home_team = 'ATL' THEN away_team  ELSE home_team  END AS opponent,
        CASE WHEN home_team = 'ATL' THEN home_score ELSE away_score END AS atl_pts,
        CASE WHEN home_team = 'ATL' THEN away_score ELSE home_score END AS opp_pts
    FROM games
    WHERE 'ATL' IN (home_team, away_team)
),

atl_offense AS (
    -- Step 2: one row per game of Falcons offensive efficiency.
    -- Aggregated BEFORE the join so both sides have the same grain (one row
    -- per game); joining games to raw plays would repeat each score ~65 times.
    SELECT
        game_id,
        COUNT(*)  AS off_plays,
        AVG(epa)  AS epa_per_play
    FROM scrimmage_plays
    WHERE posteam = 'ATL'
    GROUP BY game_id
)

-- Step 3: join, then compute the rolling and game-over-game columns.
SELECT
    g.season,
    g.week,
    g.venue,
    g.opponent,
    g.atl_pts || '-' || g.opp_pts                        AS score,
    CASE WHEN g.atl_pts > g.opp_pts THEN 'W'
         WHEN g.atl_pts < g.opp_pts THEN 'L'
         ELSE 'T' END                                    AS result,
    g.atl_pts - LAG(g.atl_pts) OVER (PARTITION BY g.season ORDER BY g.week)
                                                         AS pts_change,   -- NULL in each season's first game
    COUNT(*)                          OVER w             AS games_in_window,
    ROUND(AVG(g.atl_pts)              OVER w, 1)         AS rolling4_pts,
    ROUND(o.epa_per_play, 3)                             AS epa_per_play,
    ROUND(AVG(o.epa_per_play)         OVER w, 3)         AS rolling4_epa
FROM atl_games AS g
JOIN atl_offense AS o USING (game_id)
WINDOW w AS (
    PARTITION BY g.season           -- restart every season
    ORDER BY g.week                 -- in game order
    ROWS BETWEEN 3 PRECEDING AND CURRENT ROW   -- this game + up to 3 before it
)
ORDER BY g.season, g.week;
