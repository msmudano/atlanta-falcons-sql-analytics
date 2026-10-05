-- =====================================================================
-- Q10. Arthur Smith era (2021-23) vs. Raheem Morris era (2024-25)
--
-- Question: How did the Falcons change from the Smith years to the Morris
--           years, and does the change hold up once each era is compared
--           with the league over the SAME seasons?
-- Eras:     season <= 2023 = Smith, 2024-2025 = Morris. Verified from the
--           home_coach/away_coach columns of nflverse games.csv (not loaded
--           into this database).
-- Metrics:  reuse earlier definitions:
--             win % (tie = 0.5) and points per game     (Q7 unpivot)
--             offensive EPA/play and success rate      (scrimmage_plays view)
--             neutral early-down pass rate             (Q8)
--             3rd-down conversion rate                 (Q3)
--             red-zone TD rate per trip                (Q4)
--             defensive EPA/play allowed (lower=better)
-- Method:   sums per team-season -> sums per team-era -> rates. Rates are
--           built from era totals, so every play counts equally.
--           Each era is ranked against all 32 teams over the same seasons.
-- Skills:   many CTEs, unpivot (UNION ALL) -> one RANK() for all metrics
--           -> pivot back with conditional aggregation; JOINs on
--           (season, team); CASE inside ORDER BY to flip sort direction.
-- =====================================================================

WITH team_games AS (
    -- Wins and points per team-game (Q7's unpivot).
    SELECT season, home_team AS team, home_score AS pts_for, away_score AS pts_against FROM games
    UNION ALL
    SELECT season, away_team,         away_score,             home_score                FROM games
),

results AS (
    SELECT season, team,
           COUNT(*)                                                         AS games,
           SUM(CASE WHEN pts_for > pts_against THEN 1.0
                    WHEN pts_for = pts_against THEN 0.5 ELSE 0 END)         AS wins,
           SUM(pts_for)                                                     AS points
    FROM team_games
    GROUP BY season, team
),

offense AS (
    -- Offensive sums per team-season, including Q8's neutral early downs
    -- and Q3's 3rd-down attempts, via conditional aggregation.
    SELECT season, posteam AS team,
           COUNT(*)        AS plays,
           SUM(epa)        AS epa,
           SUM(is_success) AS successes,
           SUM(CASE WHEN down IN (1, 2) AND score_differential BETWEEN -8 AND 8 AND qtr <= 4
                     AND NOT (qtr = 2 AND game_seconds_remaining <= 1920)
                     AND NOT (qtr = 4 AND game_seconds_remaining <= 120)
                    THEN 1 ELSE 0 END)                                      AS neutral_plays,
           SUM(CASE WHEN down IN (1, 2) AND score_differential BETWEEN -8 AND 8 AND qtr <= 4
                     AND NOT (qtr = 2 AND game_seconds_remaining <= 1920)
                     AND NOT (qtr = 4 AND game_seconds_remaining <= 120)
                    THEN pass ELSE 0 END)                                   AS neutral_passes,
           SUM(CASE WHEN down = 3 AND (third_down_converted = 1 OR third_down_failed = 1)
                    THEN 1 ELSE 0 END)                                      AS third_att,
           SUM(CASE WHEN down = 3 THEN third_down_converted ELSE 0 END)     AS third_conv
    FROM scrimmage_plays
    GROUP BY season, posteam
),

defense AS (
    SELECT season, defteam AS team, COUNT(*) AS plays, SUM(epa) AS epa
    FROM scrimmage_plays
    GROUP BY season, defteam
),

rz_trips AS (
    -- Q4's red-zone trips, now kept by season.
    SELECT season, posteam AS team, MAX(fixed_drive_result) = 'Touchdown' AS td
    FROM plays
    WHERE yardline_100 <= 20
      AND two_point_attempt = 0
      AND play_type IN ('pass', 'run', 'field_goal', 'qb_kneel', 'qb_spike')
    GROUP BY season, game_id, fixed_drive, posteam
    HAVING SUM(play_type <> 'qb_kneel') > 0
),

redzone AS (
    SELECT season, team, COUNT(*) AS trips, SUM(td) AS tds
    FROM rz_trips
    GROUP BY season, team
),

team_era AS (
    -- Add up the season sums into era sums, THEN compute rates.
    SELECT
        CASE WHEN r.season <= 2023 THEN 'Smith 2021-23' ELSE 'Morris 2024-25' END AS era,
        r.team,
        SUM(r.wins) / SUM(r.games)                     AS win_pct,
        1.0 * SUM(r.points) / SUM(r.games)             AS ppg,
        SUM(o.epa) / SUM(o.plays)                      AS off_epa,
        1.0 * SUM(o.successes) / SUM(o.plays)          AS off_success,
        1.0 * SUM(o.neutral_passes) / SUM(o.neutral_plays) AS neutral_pass,
        1.0 * SUM(o.third_conv) / SUM(o.third_att)     AS third_down,
        1.0 * SUM(z.tds) / SUM(z.trips)                AS rz_td,
        SUM(d.epa) / SUM(d.plays)                      AS def_epa
    FROM results AS r
    JOIN offense AS o ON o.season = r.season AND o.team = r.team
    JOIN defense AS d ON d.season = r.season AND d.team = r.team
    JOIN redzone AS z ON z.season = r.season AND z.team = r.team
    GROUP BY era, r.team
),

long AS (
    -- Unpivot: one row per era + team + metric. sort_key fixes display order.
    SELECT era, team, 1 AS sort_key, 'Win %'                      AS metric, 100 * win_pct      AS value FROM team_era UNION ALL
    SELECT era, team, 2, 'Points per game',                                  ppg                         FROM team_era UNION ALL
    SELECT era, team, 3, 'Offensive EPA/play',                               off_epa                     FROM team_era UNION ALL
    SELECT era, team, 4, 'Offensive success %',                              100 * off_success           FROM team_era UNION ALL
    SELECT era, team, 5, 'Neutral early-down pass %',                        100 * neutral_pass          FROM team_era UNION ALL
    SELECT era, team, 6, '3rd-down conversion %',                            100 * third_down            FROM team_era UNION ALL
    SELECT era, team, 7, 'Red-zone TD %',                                    100 * rz_td                 FROM team_era UNION ALL
    SELECT era, team, 8, 'Defensive EPA/play allowed',                       def_epa                     FROM team_era
),

ranked AS (
    -- One RANK() covers every metric thanks to the long format. For the
    -- defense, lower is better, so its sort value is negated.
    SELECT
        *,
        RANK() OVER (PARTITION BY era, metric
                     ORDER BY CASE WHEN metric LIKE 'Defensive%' THEN -value ELSE value END DESC) AS rnk,
        AVG(value) OVER (PARTITION BY era, metric) AS league_avg
    FROM long
)

-- Pivot back: one row per metric, the two eras side by side, Falcons only.
-- 'Neutral early-down pass %' rank 1 = most pass-heavy (a style, not "better").
SELECT
    metric,
    ROUND(MAX(CASE WHEN era = 'Smith 2021-23'  THEN value      END), digits) AS smith_atl,
    ROUND(MAX(CASE WHEN era = 'Smith 2021-23'  THEN league_avg END), digits) AS smith_nfl_avg,
    MAX(CASE WHEN era = 'Smith 2021-23'  THEN rnk END)                  AS smith_rank,
    ROUND(MAX(CASE WHEN era = 'Morris 2024-25' THEN value      END), digits) AS morris_atl,
    ROUND(MAX(CASE WHEN era = 'Morris 2024-25' THEN league_avg END), digits) AS morris_nfl_avg,
    MAX(CASE WHEN era = 'Morris 2024-25' THEN rnk END)                  AS morris_rank
FROM (SELECT *, CASE WHEN metric LIKE '%EPA%' THEN 3 ELSE 1 END AS digits   -- EPA: 3 decimals
      FROM ranked)
WHERE team = 'ATL'
GROUP BY sort_key, metric
ORDER BY sort_key;
