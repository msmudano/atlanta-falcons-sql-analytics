# Atlanta Falcons Play-by-Play Analytics Database

A SQLite database built from five NFL regular seasons (2021–2025) of
[nflverse](https://github.com/nflverse/nflverse-data) play-by-play data, with
SQL queries analyzing team efficiency and play-calling, focused on the
Atlanta Falcons.

| | |
|---|---|
| Seasons | 5 (2021–2025, regular season) |
| Games | 1,359 |
| Play-by-play rows loaded | 235,933 |
| Scrimmage plays analyzed | 167,622 |
| Players | 5,854 |

**Stack:** Python (pandas) to download and load, SQLite for storage and queries.

## How to reproduce

```bash
pip install -r requirements.txt
python load_data.py          # downloads to data/raw/, builds data/falcons.db
sqlite3 -header -column data/falcons.db < sql/01_success_rate_by_down_distance.sql
```

`data/` is gitignored; the loader rebuilds it from the nflverse releases.
On macOS with python.org Python, run `Install Certificates.command` once if the
download fails with an SSL certificate error.

## Schema

| Object | One row per | Key |
|---|---|---|
| `games` | game | `game_id` |
| `plays` | play-by-play event (including timeouts, kickoffs, penalties) | `(game_id, play_id)` |
| `players` | player | `player_id` (NFL GSIS id) |
| `scrimmage_plays` (view) | real pass/run play | — |

Full definitions with comments: [`sql/00_schema.sql`](sql/00_schema.sql).

**Key definitions**, set once in the `scrimmage_plays` view:

- **Play:** `play_type` is `pass` or `run`, excluding two-point tries. Sacks and
  scrambles count as passes.
- **Success:** gain at least 40% of the yards to go on 1st down, 60% on 2nd,
  100% on 3rd/4th. A turnover is never a success.

## Questions and findings

| # | Question | Query | Finding |
|---|---|---|---|
| 1 | Success rate by down and distance, Falcons vs. the league | [`01`](sql/01_success_rate_by_down_distance.sql) | Essentially league average (47.8% vs. 47.6%): slightly better on every 2nd-down distance, slightly worse on most 3rd and 4th downs. |
| 2 | Run vs. pass rate by score margin and quarter | [`02`](sql/02_pass_rate_by_score_and_quarter.sql) | Passed less than the league in every score situation (55.9% vs. 60.7%); the 2022 team had the league's lowest pass rate (48.7%). |
| 3 | Third-down conversion rate by distance, ranked | [`03`](sql/03_third_down_conversion_by_distance.sql) | 15th of 32 overall (39.0%), but 28th of 32 on 3rd & 1. |
| 4 | Red-zone touchdown rate per trip, all 32 teams ranked | [`04`](sql/04_red_zone_td_rate_ranked.sql) | 22nd of 32 (55.2% of 259 trips vs. a 56.4% team average); fell to 28th in 2023, then rose to 11th–12th in 2024–25. |

*More queries in progress.*

## How I built this

I built this project with [Claude Code](https://claude.com/claude-code), Anthropic's AI
coding assistant, acting as a tutor and pair programmer. I chose the questions,
made the design decisions (what counts as a play, how success is defined, the
schema), checked the results, and own the analysis. Claude Code proposed
approaches, explained the tradeoffs, and drafted code that I reviewed.

For full transparency, the exact prompt I gave Claude Code at the start is
committed in this repository as [`prompt.rtf`](prompt.rtf).

## Data source

Play-by-play, schedule and roster data from the nflverse project
([nflverse-data releases](https://github.com/nflverse/nflverse-data/releases)).
