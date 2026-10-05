-- =====================================================================
-- Q6. Falcons rushers and receivers by EPA per play, with league percentile
--
-- Question: Which Falcons rushers and receivers produced the most value per
--           play, and how do they compare with every qualifying NFL player
--           at the same position?
-- Rushing:  designed runs only (rush = 1). QB scrambles are excluded: they
--           were called passes (see Q2). Measured as EPA per carry.
-- Receiving: every pass with an intended receiver (completions, incompletions,
--           interceptions). Measured as EPA per target. Sacks have no target.
-- Grain:    one row per player PER TEAM, 2021-2025 pooled. A player's
--           Falcons numbers include only his Falcons plays.
-- Cutoffs:  at least 100 carries (rushing) or 50 targets (receiving).
-- Compare:  within role AND position. Baselines differ a lot:
--             designed runs  QB +0.11, RB -0.06 per carry (qualified players)
--             targets        WR +0.22, TE +0.20, RB +0.00 per target (all plays)
--           so a running back is ranked only against running backs, etc.
--           Position = the player's most recent roster position, 2021-2025.
-- Skills:   UNION ALL, multiple CTEs, JOINs to players and to a per-group
--           baseline, CASE WHEN for role-specific cutoffs, window functions
--           RANK(), PERCENT_RANK(), COUNT() OVER (PARTITION BY role, position).
-- =====================================================================

WITH touches AS (
    -- Step 1: one row per player-play, rushing and receiving stacked,
    -- with the player's position attached for grouping.
    SELECT 'Rushing' AS role, s.posteam, s.rusher_player_id AS player_id, p.position, s.epa
    FROM scrimmage_plays AS s
    JOIN players AS p ON p.player_id = s.rusher_player_id
    WHERE s.rush = 1

    UNION ALL

    SELECT 'Receiving', s.posteam, s.receiver_player_id, p.position, s.epa
    FROM scrimmage_plays AS s
    JOIN players AS p ON p.player_id = s.receiver_player_id
),

group_avg AS (
    -- Step 2: league baseline per role + position (every play weighted equally).
    SELECT role, position, AVG(epa) AS league_epa
    FROM touches
    GROUP BY role, position
),

player_team AS (
    -- Step 3: one row per role + position + team + player.
    SELECT
        role,
        position,
        posteam,
        player_id,
        COUNT(*)  AS plays,
        AVG(epa)  AS epa_per_play,
        SUM(epa)  AS total_epa
    FROM touches
    GROUP BY role, position, posteam, player_id
),

qualified AS (
    -- Step 4: role-specific minimum sample.
    SELECT *
    FROM player_team
    WHERE plays >= CASE role WHEN 'Rushing' THEN 100 ELSE 50 END
),

ranked AS (
    -- Step 5: rank every qualifying NFL player within his role AND position.
    -- PERCENT_RANK = share of the group ranked below him (0 to 1).
    SELECT
        *,
        RANK()         OVER (PARTITION BY role, position ORDER BY epa_per_play DESC) AS grp_rank,
        COUNT(*)       OVER (PARTITION BY role, position)                            AS grp_size,
        PERCENT_RANK() OVER (PARTITION BY role, position ORDER BY epa_per_play)      AS pct_rank
    FROM qualified
)

-- Step 6: names, baseline, then keep only Falcons.
SELECT
    r.role,
    p.full_name,
    r.position,
    r.plays,
    ROUND(r.epa_per_play, 3)                         AS epa_per_play,
    ROUND(r.epa_per_play - g.league_epa, 3)          AS vs_position_avg,
    ROUND(r.total_epa, 1)                            AS total_epa,
    r.grp_rank || ' of ' || r.grp_size || ' ' || r.position || 's' AS rank_at_position,
    CAST(ROUND(100 * r.pct_rank) AS INTEGER) || '%'  AS percentile
FROM ranked    AS r
JOIN players   AS p ON p.player_id = r.player_id
JOIN group_avg AS g ON g.role = r.role AND g.position = r.position
WHERE r.posteam = 'ATL'
ORDER BY r.role DESC, r.epa_per_play DESC;     -- 'Rushing' first, best first
