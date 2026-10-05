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

**SQL techniques used:** multi-table joins, CTEs, window functions (`RANK`,
`PERCENT_RANK`, `LAG`, rolling averages with `ROWS BETWEEN`), `CASE WHEN`
bucketing, `GROUP BY` with `HAVING`, pivots and unpivots, `CROSS JOIN` grids,
and a view that defines what counts as a play.

## Repository layout

```
load_data.py      downloads nflverse files, keeps 35 of 372 columns, builds the database
requirements.txt  pandas
sql/00_schema.sql tables, keys, indexes, and the scrimmage_plays view
sql/01-10_*.sql   one file per question, each with a header explaining its definitions
prompt.rtf        the original prompt given to Claude Code (see "How I built this")
data/             created by the loader; gitignored
```

## How to reproduce

Requires Python 3 and the `sqlite3` command-line tool (tested with Python 3.12
and SQLite 3.45).

```bash
pip install -r requirements.txt
python load_data.py          # downloads ~100 MB to data/raw/, builds data/falcons.db
sqlite3 -header -column data/falcons.db < sql/01_success_rate_by_down_distance.sql

# or run every query:
for f in sql/0[1-9]_*.sql sql/1[0-9]_*.sql; do echo "== $f"; sqlite3 -header -column data/falcons.db < "$f"; done
```

`data/` is gitignored; the loader rebuilds it from the nflverse releases. If the
download fails with an SSL certificate error (common with python.org Python on
macOS), either run `Install Certificates.command` from your Python folder once,
or point Python at certifi's bundle (`pip install certifi` if needed):

```bash
SSL_CERT_FILE=$(python -c "import certifi; print(certifi.where())") python load_data.py
```

The data in this README was downloaded on October 5, 2026. nflverse
occasionally revises past seasons, so a later download may differ slightly.

## Schema

| Object | One row per | Key |
|---|---|---|
| `games` | game (with `location` = Home/Neutral for international games) | `game_id` |
| `plays` | play-by-play event (including timeouts, kickoffs, penalties) | `(game_id, play_id)` |
| `players` | player | `player_id` (NFL GSIS id) |
| `scrimmage_plays` (view) | real pass/run play | — |

Full definitions with comments: [`sql/00_schema.sql`](sql/00_schema.sql).

**Key definitions**, set once in the `scrimmage_plays` view:

- **Play:** `play_type` is `pass` or `run`, excluding two-point tries. Sacks and
  scrambles count as passes.
- **Success:** gain at least 40% of the yards to go on 1st down, 60% on 2nd,
  100% on 3rd/4th. A turnover is never a success.

## Data validation

Before analyzing anything, I checked that the data loaded correctly:

| Check | Result |
|---|---|
| Games per season | 272 each season, except 271 in 2022 (the cancelled Bills–Bengals game); Falcons 17 every season |
| Final play-by-play score vs. schedule score | Match for all 1,359 games |
| Plays with no matching game | 0 |
| Player IDs in plays with no matching player | 0 |
| NULL down / offense / EPA / yards on scrimmage plays | 0 (two-point tries correctly excluded) |
| Falcons points scored and allowed, 2025 | 353 / 401, matching an outside source |

Each query also has its own checks, such as buckets adding back up to totals,
or join row counts matching the number of games, so no rows were lost or duplicated.

Two data issues found and handled:

- nflverse labels QB scrambles `play_type = 'run'` but flags them as dropbacks.
  Pass rates use the dropback flag, so scrambles count as the pass calls they were.
- The 2025 Falcons–Colts game is flagged as a neutral-site game, but its stadium
  field says Indianapolis. An outside source confirmed it was played in Berlin,
  so the `location` flag is used and the stadium field is not.

## Questions and findings

| # | Question | Query | Finding |
|---|---|---|---|
| 1 | Success rate by down and distance, Falcons vs. the league | [`01`](sql/01_success_rate_by_down_distance.sql) | Essentially league average (47.8% vs. 47.6%): slightly better on every 2nd-down distance, slightly worse on most 3rd and 4th downs. |
| 2 | Run vs. pass rate by score margin and quarter | [`02`](sql/02_pass_rate_by_score_and_quarter.sql) | Passed less than the league in every score situation (55.9% vs. 60.7%); the 2022 team had the league's lowest pass rate (48.7%). |
| 3 | Third-down conversion rate by distance, ranked | [`03`](sql/03_third_down_conversion_by_distance.sql) | 15th of 32 overall (39.0%), but 28th of 32 on 3rd & 1. |
| 4 | Red-zone touchdown rate per trip, all 32 teams ranked | [`04`](sql/04_red_zone_td_rate_ranked.sql) | 22nd of 32 (55.2% of 259 trips vs. a 56.4% team average); fell to 28th in 2023, then rose to 11th–12th in 2024–25. |
| 5 | Rolling 4-game average of Falcons points, with offensive EPA/play | [`05`](sql/05_rolling_points_and_epa.sql) | Points and EPA/play move together (r = 0.80 per game). In 2024 the rolling average fell from 29.8 (Week 8) to 13.8 (Week 15, Kirk Cousins' last start), then recovered to 27.8 over Michael Penix Jr.'s three starts. |
| 6 | Top rushers and receivers by EPA per play (100+ carries / 50+ targets), ranked within position | [`06`](sql/06_top_players_epa_per_play.sql) | Bijan Robinson and Tyler Allgeier were equally efficient runners (66th percentile of 149 RBs). Drake London produced the most total receiving value (84.9 EPA) but ranked in the 38th percentile per target among WRs. |
| 7 | Home vs. away splits, compared with the league's home-field edge | [`07`](sql/07_home_away_splits.sql) | 20–21 at home vs. 16–25 away (+9.8 win-% points), close to the league's +7.8. The Falcons' offense gained more at home than usual (+3.1 success-rate points vs. +1.0), but they allowed only 0.9 fewer points per game at home vs. the league's 2.1. Three neutral-site games (London ×2, Berlin) are excluded. |
| 8 | Early-down pass rate in neutral situations, ranked by season | [`08`](sql/08_neutral_early_down_pass_rate.sql) | The run-heavy approach was a choice, not game situation: in 2022 the Falcons had the NFL's lowest neutral early-down pass rate (40.7%, 32nd of 32). Under Raheem Morris the gap to the league narrowed to about 3.5 points, still 26th–27th. |
| 9 | How drives ended, with ATL's rank for each outcome | [`09`](sql/09_drive_outcomes.sql) | 19.8% of Falcons drives ended in a touchdown vs. a 22.8% team average (24th); they ranked 5th-most in turnovers, 7th in field goals and 3rd in missed field goals. |
| 10 | Arthur Smith era (2021–23) vs. Raheem Morris era (2024–25), each vs. the league over the same seasons | [`10`](sql/10_smith_vs_morris_eras.sql) | Offensive efficiency rose from 27th to 17th in EPA/play and from 24th to 12th in red-zone TD rate, and the defense from 30th to 22nd; but 3rd-down conversion fell from 11th to 26th, and points-per-game rank stayed 24th. |

## Limitations

- **Small samples.** One team over five seasons is 85 games, about 50 red-zone
  trips a season, and 41 games per home/away venue. Small rank differences
  (11th vs. 14th) are within noise; the findings above focus on large gaps.
- **Eras are not just coaches.** The Falcons' starting quarterback changed almost
  every season (Matt Ryan; Marcus Mariota and Desmond Ridder; Ridder and Taylor
  Heinicke; Kirk Cousins; Michael Penix Jr.), along with coordinators and roster.
  Query 10 compares eras; it does not isolate the head coach's effect.
- **EPA is a model.** EPA comes from nflverse's expected-points model. Success
  rate is defined by yardage instead, so the headline efficiency metric doesn't
  depend on a model.
- **Shared credit.** A receiver's EPA per target also reflects the quarterback
  and play design.
- **Positions** are each player's most recent roster listing, so a player who
  changed positions is grouped by the later one.
- **Correlation** in Query 5 (r = 0.80) was computed in Python, because SQLite
  has no `CORR()` function.

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
