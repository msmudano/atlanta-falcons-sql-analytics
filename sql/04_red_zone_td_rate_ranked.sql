-- =====================================================================
-- Q4. Red-zone touchdown rate, all 32 teams ranked
--
-- Question: When a team reaches the opponent's 20-yard line, how often
--           does the drive end in a touchdown? Where do the Falcons rank?
-- Trip:     a drive with at least one pass, run, field-goal attempt, or
--           spike snapped at/inside the 20 (two-point tries excluded).
--           Drives whose only red-zone snaps were kneels are dropped: the
--           team chose not to score. Drives that ran out of clock after
--           real plays still count as non-TD trips.
-- Note:     reads from `plays`, not the scrimmage_plays view, because a
--           trip is a drive-level idea that needs FG attempts and kneels.
-- Scope:    2021-2025 regular season, 5 seasons pooled.
-- Skills:   CTEs, GROUP BY with HAVING, RANK() and AVG() OVER () across
--           the whole result (no PARTITION BY).
-- =====================================================================

WITH rz_snaps AS (
    -- Step 1: every offensive snap at or inside the opponent's 20.
    SELECT game_id, fixed_drive, posteam, play_type, fixed_drive_result
    FROM plays
    WHERE yardline_100 <= 20
      AND two_point_attempt = 0
      AND play_type IN ('pass', 'run', 'field_goal', 'qb_kneel', 'qb_spike')
),

trips AS (
    -- Step 2: one row per drive that reached the red zone.
    SELECT
        game_id,
        fixed_drive,
        posteam,
        MAX(fixed_drive_result) AS result     -- one result per drive, so MAX just picks it
    FROM rz_snaps
    GROUP BY game_id, fixed_drive, posteam
    HAVING SUM(play_type <> 'qb_kneel') > 0  -- drop kneel-only drives
),

team_rz AS (
    -- Step 3: one row per team.
    SELECT
        posteam,
        COUNT(*)                                         AS trips,
        SUM(result = 'Touchdown')                        AS tds,
        SUM(result IN ('Touchdown', 'Field goal'))       AS scores,
        AVG(result = 'Touchdown')                        AS td_rate,
        AVG(result IN ('Touchdown', 'Field goal'))       AS score_rate
    FROM trips
    GROUP BY posteam
),

ranked AS (
    -- Step 4: OVER () with nothing inside = one window holding all 32 teams.
    SELECT
        *,
        RANK()       OVER (ORDER BY td_rate DESC) AS td_rank,
        AVG(td_rate) OVER ()                      AS avg_team_td_rate
    FROM team_rz
)

SELECT
    td_rank,
    posteam,
    trips,
    tds,
    ROUND(100.0 * td_rate, 1)                     AS td_pct,
    ROUND(100.0 * (td_rate - avg_team_td_rate), 1) AS vs_avg_pct_pts,
    ROUND(100.0 * score_rate, 1)                  AS score_pct,     -- TD or FG; shown, not ranked
    CASE WHEN posteam = 'ATL' THEN '<-- ATL' ELSE '' END AS note
FROM ranked
ORDER BY td_rank, posteam;
