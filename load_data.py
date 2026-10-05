"""Build data/falcons.db from nflverse play-by-play, schedule, and roster files.

Usage:  python load_data.py

Raw files are cached in data/raw/, so re-running only rebuilds the database.
"""

import sqlite3
import urllib.request
from pathlib import Path

import pandas as pd

SEASONS = range(2021, 2026)  # 2021-2025
BASE_URL = "https://github.com/nflverse/nflverse-data/releases/download"
DATA_DIR = Path("data")
RAW_DIR = DATA_DIR / "raw"
DB_PATH = DATA_DIR / "falcons.db"
SCHEMA_PATH = Path("sql/00_schema.sql")

# Only the columns our questions need (pbp files have 372). Each maps to a use:
PBP_COLUMNS = [
    # keys and context
    "game_id", "play_id", "season", "week", "season_type",
    "posteam", "defteam",
    # game situation: down/distance, field position, clock, score
    "qtr", "down", "ydstogo", "yardline_100", "game_seconds_remaining",
    "score_differential", "total_home_score", "total_away_score",
    # what kind of play it was (used to filter out non-plays)
    "play_type", "pass", "rush", "qb_scramble", "sack", "two_point_attempt", "penalty",
    # outcome
    "yards_gained", "epa", "first_down", "third_down_converted", "third_down_failed",
    "touchdown", "interception", "fumble_lost",
    # who was involved
    "passer_player_id", "rusher_player_id", "receiver_player_id",
    # drive-level results
    "fixed_drive", "fixed_drive_result", "desc",
]

GAME_COLUMNS = [
    "game_id", "season", "week", "game_type", "gameday", "home_team", "away_team",
    "home_score", "away_score", "overtime", "div_game", "roof",
]

# pbp stores 0/1 flags as floats (1.0, 0.0, NaN); store them as whole numbers.
INT_COLUMNS = [
    "play_id", "season", "week", "qtr", "down", "ydstogo", "yardline_100",
    "game_seconds_remaining", "score_differential", "total_home_score", "total_away_score",
    "pass", "rush", "qb_scramble", "sack", "two_point_attempt", "penalty", "yards_gained",
    "first_down", "third_down_converted", "third_down_failed", "touchdown",
    "interception", "fumble_lost", "fixed_drive",
]


def download(filename: str, release: str) -> Path:
    """Download a release file into data/raw/ unless it's already there."""
    path = RAW_DIR / filename
    if not path.exists():
        url = f"{BASE_URL}/{release}/{filename}"
        print(f"  downloading {url}")
        urllib.request.urlretrieve(url, path)
    return path


def load_games() -> pd.DataFrame:
    games = pd.read_csv(download("games.csv", "schedules"), usecols=GAME_COLUMNS)
    games = games[games["season"].isin(SEASONS) & (games["game_type"] == "REG")]
    return games.astype({"home_score": "Int64", "away_score": "Int64",
                         "overtime": "Int64", "div_game": "Int64"})


def load_plays() -> pd.DataFrame:
    frames = []
    for season in SEASONS:
        path = download(f"play_by_play_{season}.csv.gz", "pbp")
        df = pd.read_csv(path, usecols=PBP_COLUMNS, low_memory=False)
        frames.append(df[df["season_type"] == "REG"])
    plays = pd.concat(frames, ignore_index=True)
    plays = plays.drop(columns="season_type").rename(columns={"desc": "play_desc"})
    plays[INT_COLUMNS] = plays[INT_COLUMNS].astype("Int64")  # Int64 allows NULLs
    return plays


def load_players() -> pd.DataFrame:
    frames = [pd.read_csv(download(f"roster_{s}.csv", "rosters"),
                          usecols=["season", "gsis_id", "full_name", "position"])
              for s in SEASONS]
    rosters = pd.concat(frames).dropna(subset=["gsis_id"])
    # A player appears once per season; keep their most recent season's row.
    players = (rosters.sort_values("season")
                      .drop_duplicates("gsis_id", keep="last")
                      .rename(columns={"gsis_id": "player_id"}))
    return players[["player_id", "full_name", "position"]]


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    print("Reading source files...")
    games, plays, players = load_games(), load_plays(), load_players()

    print(f"Building {DB_PATH}...")
    with sqlite3.connect(DB_PATH) as conn:
        conn.executescript(SCHEMA_PATH.read_text())
        # if_exists="append" inserts into the tables the schema created,
        # instead of letting pandas create its own (untyped, keyless) tables.
        games.to_sql("games", conn, if_exists="append", index=False)
        players.to_sql("players", conn, if_exists="append", index=False)
        plays.to_sql("plays", conn, if_exists="append", index=False, chunksize=10_000)

        print("\nRow counts:")
        for table in ["games", "plays", "players", "scrimmage_plays"]:
            n = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            print(f"  {table:<16}{n:>9,}")
        seasons = conn.execute(
            "SELECT COUNT(DISTINCT season), MIN(season), MAX(season) FROM plays").fetchone()
        print(f"  seasons: {seasons[0]} ({seasons[1]}-{seasons[2]})")


if __name__ == "__main__":
    main()
