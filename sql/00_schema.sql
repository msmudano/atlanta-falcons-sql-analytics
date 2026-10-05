-- =====================================================================
-- Atlanta Falcons Play-by-Play Analytics Database: schema
-- Source: nflverse (github.com/nflverse/nflverse-data), 2021-2025 REG season
--
-- Three tables:
--   games   - one row per game (from schedules/games.csv)
--   plays   - one row per play-by-play event (from pbp/play_by_play_YYYY.csv.gz)
--   players - one row per player (from rosters/roster_YYYY.csv)
-- Plus one view:
--   scrimmage_plays - the single, shared definition of a "play" and of "success"
-- =====================================================================

DROP VIEW  IF EXISTS scrimmage_plays;
DROP TABLE IF EXISTS plays;
DROP TABLE IF EXISTS games;
DROP TABLE IF EXISTS players;

-- ---------------------------------------------------------------------
-- games: game-level facts stored once, not repeated on every play.
-- ---------------------------------------------------------------------
CREATE TABLE games (
    game_id      TEXT PRIMARY KEY,   -- e.g. '2025_01_TB_ATL' (season_week_away_home)
    season       INTEGER NOT NULL,
    week         INTEGER NOT NULL,
    game_type    TEXT    NOT NULL,   -- 'REG' only in this project
    gameday      TEXT,               -- 'YYYY-MM-DD'
    home_team    TEXT    NOT NULL,
    away_team    TEXT    NOT NULL,
    home_score   INTEGER,
    away_score   INTEGER,
    overtime     INTEGER,            -- 1 if the game went to OT
    div_game     INTEGER,            -- 1 if a division matchup
    roof         TEXT,               -- 'outdoors', 'dome', 'closed', 'open'
    location     TEXT                -- 'Home' or 'Neutral' (London, Germany, etc.).
                                     -- For 'Neutral', home_team is only the designated home side.
);

-- ---------------------------------------------------------------------
-- plays: every play-by-play row, INCLUDING non-plays (timeouts, kickoffs,
-- penalties, etc.). We keep them so the raw data is complete and so the
-- filtering logic lives visibly in SQL (see scrimmage_plays below).
-- ---------------------------------------------------------------------
CREATE TABLE plays (
    game_id                TEXT    NOT NULL REFERENCES games(game_id),
    play_id                INTEGER NOT NULL,   -- unique only WITHIN a game
    season                 INTEGER NOT NULL,   -- duplicated from games on purpose: almost every query filters on it
    week                   INTEGER NOT NULL,
    posteam                TEXT,               -- team on offense (NULL on timeouts etc.)
    defteam                TEXT,               -- team on defense
    qtr                    INTEGER,            -- 5 = overtime
    down                   INTEGER,            -- NULL on kickoffs, PATs, 2-pt tries
    ydstogo                INTEGER,            -- yards needed for a first down
    yardline_100           INTEGER,            -- yards from opponent's end zone (red zone = <= 20)
    game_seconds_remaining INTEGER,
    score_differential     INTEGER,            -- posteam score minus defteam score, before the snap
    total_home_score       INTEGER,            -- running score after the play (used for validation)
    total_away_score       INTEGER,
    play_type              TEXT,               -- pass, run, punt, kickoff, field_goal, extra_point,
                                               -- qb_kneel, qb_spike, no_play, or NULL
    pass                   INTEGER,            -- 1 if a dropback (includes sacks and scrambles)
    rush                   INTEGER,            -- 1 if a designed run
    qb_scramble            INTEGER,
    sack                   INTEGER,
    two_point_attempt      INTEGER,
    penalty                INTEGER,
    yards_gained           INTEGER,            -- excludes penalty yards
    epa                    REAL,               -- expected points added (nflverse model)
    first_down             INTEGER,
    third_down_converted   INTEGER,
    third_down_failed      INTEGER,
    touchdown              INTEGER,
    interception           INTEGER,
    fumble_lost            INTEGER,
    passer_player_id       TEXT REFERENCES players(player_id),
    rusher_player_id       TEXT REFERENCES players(player_id),
    receiver_player_id     TEXT REFERENCES players(player_id),
    fixed_drive            INTEGER,            -- drive number within the game
    fixed_drive_result     TEXT,               -- 'Touchdown', 'Field goal', 'Punt', ...
    play_desc              TEXT,               -- renamed from 'desc' (a reserved SQL keyword)
    PRIMARY KEY (game_id, play_id)             -- composite key: play_id repeats across games
);

-- Indexes on the columns we filter and join on most.
CREATE INDEX idx_plays_posteam ON plays(posteam, season);
CREATE INDEX idx_plays_defteam ON plays(defteam, season);

-- ---------------------------------------------------------------------
-- players: one row per player, keyed by the NFL's GSIS id, the same id
-- used in plays.*_player_id.
-- ---------------------------------------------------------------------
CREATE TABLE players (
    player_id  TEXT PRIMARY KEY,   -- gsis_id, e.g. '00-0033553'
    full_name  TEXT NOT NULL,
    position   TEXT                -- position from the player's most recent season in range
);

-- ---------------------------------------------------------------------
-- scrimmage_plays: what counts as a "play" in this project, defined ONCE.
--   * play_type IN ('pass','run')  -> drops kickoffs, punts, FGs, PATs, kneels,
--                                     spikes, timeouts (NULL), and penalty-
--                                     nullified plays ('no_play')
--   * two_point_attempt = 0        -> 2-pt tries are pass/run plays with no down
-- Sacks and scrambles stay in as pass plays: the play call was a pass.
--
-- is_success uses the classic yardage-based definition:
--   1st down: gain >= 40% of yards to go
--   2nd down: gain >= 60% of yards to go
--   3rd/4th : gain >= 100% (i.e. convert)
--   A turnover is never a success, even if it gained yards.
-- ---------------------------------------------------------------------
CREATE VIEW scrimmage_plays AS
SELECT
    p.*,
    CASE
        WHEN p.interception = 1 OR p.fumble_lost = 1          THEN 0
        WHEN p.down = 1      AND p.yards_gained >= 0.4 * p.ydstogo THEN 1
        WHEN p.down = 2      AND p.yards_gained >= 0.6 * p.ydstogo THEN 1
        WHEN p.down IN (3,4) AND p.yards_gained >= p.ydstogo       THEN 1
        ELSE 0
    END AS is_success
FROM plays AS p
WHERE p.play_type IN ('pass', 'run')
  AND p.two_point_attempt = 0;
