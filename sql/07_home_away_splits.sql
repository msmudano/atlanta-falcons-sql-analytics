-- =====================================================================
-- Q7. Home vs. away splits: Falcons vs. the rest of the NFL
--
-- Question: Did the Falcons play better at home than on the road, and was
--           their home-field edge bigger or smaller than the league's?
-- Venue:    from games.location. Neutral-site games (London, Germany, etc.;
--           3 Falcons games, 26 overall) are their own 'Neutral' row and are
--           left out of the Home - Away edge.
-- Metrics:  win % (tie = half a win), points for/against per game,
--           offensive EPA/play and success rate, defensive EPA/play allowed
--           (lower is better for a defense).
-- Weighting: per-play rates are SUM(epa) / SUM(plays), so every play counts
--           equally rather than every game.
-- Scope:    2021-2025 regular season.
-- Skills:   unpivot with UNION ALL, multi-table JOIN on a composite key
--           (game_id, team), CASE WHEN, conditional aggregation,
--           difference-in-differences comparison.
-- =====================================================================

WITH team_games AS (
    -- Step 1: unpivot. One row per TEAM per game instead of one per game.
    SELECT game_id,
           home_team AS team,
           CASE WHEN location = 'Neutral' THEN 'Neutral' ELSE 'Home' END AS venue,
           home_score AS pts_for,
           away_score AS pts_against
    FROM games
    UNION ALL
    SELECT game_id,
           away_team,
           CASE WHEN location = 'Neutral' THEN 'Neutral' ELSE 'Away' END,
           away_score,
           home_score
    FROM games
),

offense AS (
    -- Step 2a: each team's offense per game. Keep SUMS so rates can be
    -- play-weighted later.
    SELECT game_id, posteam AS team,
           COUNT(*)        AS plays,
           SUM(epa)        AS epa,
           SUM(is_success) AS successes
    FROM scrimmage_plays
    GROUP BY game_id, posteam
),

defense AS (
    -- Step 2b: each team's defense per game (the opponent's plays).
    SELECT game_id, defteam AS team,
           COUNT(*) AS plays,
           SUM(epa) AS epa
    FROM scrimmage_plays
    GROUP BY game_id, defteam
),

game_level AS (
    -- Step 3: all three are one row per (game_id, team), so the joins are
    -- one-to-one: no fan-out.
    SELECT
        CASE WHEN tg.team = 'ATL' THEN 'ATL' ELSE 'Rest of NFL' END AS grp,
        tg.venue,
        tg.pts_for,
        tg.pts_against,
        o.plays AS off_plays, o.epa AS off_epa, o.successes AS off_successes,
        d.plays AS def_plays, d.epa AS def_epa
    FROM team_games AS tg
    JOIN offense AS o ON o.game_id = tg.game_id AND o.team = tg.team
    JOIN defense AS d ON d.game_id = tg.game_id AND d.team = tg.team
),

by_venue AS (
    -- Step 4: one row per group per venue.
    SELECT
        grp,
        venue,
        COUNT(*) AS games,
        AVG(CASE WHEN pts_for > pts_against THEN 1.0
                 WHEN pts_for = pts_against THEN 0.5
                 ELSE 0.0 END)            AS win_pct,
        AVG(pts_for)                      AS pts_for_pg,
        AVG(pts_against)                  AS pts_against_pg,
        SUM(off_epa) / SUM(off_plays)     AS off_epa_pp,
        1.0 * SUM(off_successes) / SUM(off_plays) AS off_success,
        SUM(def_epa) / SUM(def_plays)     AS def_epa_pp
    FROM game_level
    GROUP BY grp, venue
),

home_edge AS (
    -- Step 5: Home minus Away for each metric (Neutral excluded).
    -- MAX(CASE ...) picks the one Home or Away value out of each group.
    SELECT
        grp,
        'Home - Away' AS venue,
        NULL          AS games,
        MAX(CASE WHEN venue = 'Home' THEN win_pct        END) - MAX(CASE WHEN venue = 'Away' THEN win_pct        END),
        MAX(CASE WHEN venue = 'Home' THEN pts_for_pg     END) - MAX(CASE WHEN venue = 'Away' THEN pts_for_pg     END),
        MAX(CASE WHEN venue = 'Home' THEN pts_against_pg END) - MAX(CASE WHEN venue = 'Away' THEN pts_against_pg END),
        MAX(CASE WHEN venue = 'Home' THEN off_epa_pp     END) - MAX(CASE WHEN venue = 'Away' THEN off_epa_pp     END),
        MAX(CASE WHEN venue = 'Home' THEN off_success    END) - MAX(CASE WHEN venue = 'Away' THEN off_success    END),
        MAX(CASE WHEN venue = 'Home' THEN def_epa_pp     END) - MAX(CASE WHEN venue = 'Away' THEN def_epa_pp     END)
    FROM by_venue
    GROUP BY grp
)

-- Step 6: venue rows and edge rows together. Compare the two 'Home - Away'
-- rows: that difference-in-differences says whether ATL's home edge is unusual.
SELECT
    grp,
    venue,
    games,
    ROUND(100 * win_pct, 1)        AS win_pct,
    ROUND(pts_for_pg, 1)           AS pts_for_pg,
    ROUND(pts_against_pg, 1)       AS pts_against_pg,
    ROUND(off_epa_pp, 3)           AS off_epa_play,
    ROUND(100 * off_success, 1)    AS off_success_pct,
    ROUND(def_epa_pp, 3)           AS def_epa_play_allowed
FROM (SELECT * FROM by_venue UNION ALL SELECT * FROM home_edge)
ORDER BY grp,
         CASE venue WHEN 'Home' THEN 1 WHEN 'Away' THEN 2 WHEN 'Neutral' THEN 3 ELSE 4 END;
