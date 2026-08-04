# The Association — League Website

A GitHub Pages site for a 12-franchise league. You edit plain YAML files;
the site computes standings, season stats, career highs, double/triple-doubles,
MVP counts, and the full record book automatically from game box scores.

## 1. One-time setup

1. Create a new GitHub repository and push everything in this folder to it
   (the whole folder, including the hidden `.github` folder).
2. In the repo, go to **Settings → Pages**, and under "Build and deployment,"
   set **Source** to **GitHub Actions** (not "Deploy from a branch" — this
   site uses a custom plugin that requires a real build).
3. Push to `main`. Check the **Actions** tab — a "Build and deploy site"
   workflow should run. When it's green, your site is live at the URL shown
   in Settings → Pages.
4. Open `_config.yml` and set `url:` to that address (e.g.
   `https://yourusername.github.io`) and `baseurl:` to `/your-repo-name`
   — leave `baseurl` blank if your repo is named `yourusername.github.io`.
   Commit and push again.

That's the only setup. Everything below is stuff you and your
co-commissioners will do regularly, entirely through the GitHub website —
no local install needed, no command line.

## 2. Recording a game (the main thing you'll do)

Open `_data/games.yml` on github.com and click the pencil icon to edit.

**Before the game**, add an upcoming entry near the top:
```yaml
- id: 2026-08-16-comets-wolves
  date: 2026-08-16
  home: comets
  away: wolves
  played: false
```

**After the game**, change `played` to `true` and fill in the rest:
```yaml
- id: 2026-08-16-comets-wolves
  date: 2026-08-16
  home: comets
  away: wolves
  played: true
  home_score: 104
  away_score: 97
  mvp: deshawn-riley       # player id, best performer overall
  lmvp: kian-ashford       # player id, best performer on the losing team
  box:
    comets:
      - player: deshawn-riley
        min: 34
        pts: 28
        oreb: 1            # offensive rebounds
        dreb: 4            # defensive rebounds
        ast: 11
        blk: 1
        tov: 3             # turnovers
        fouls: 2
      - player: miles-okafor
        min: 30
        pts: 14
        oreb: 3
        dreb: 9
        ast: 1
        blk: 2
        tov: 1
        fouls: 3
    wolves:
      - player: kian-ashford
        min: 33
        pts: 22
        oreb: 0
        dreb: 3
        ast: 9
        blk: 0
        tov: 4
        fouls: 2
```

Commit the change. Within about a minute the site rebuilds and:
- Standings update (wins/losses/streaks are computed from every game, not
  typed in anywhere)
- Both players' season averages, career highs, and double/triple-double
  counts update
- A box-score page appears automatically at `/games/2026-08-16-comets-wolves/`
- The MVP/LMVP leaderboards and full record book update

**Player IDs** are lowercase-with-hyphens versions of the name — find them
by opening `_data/players.yml`. `id` is what you type into `box:` and
`mvp`/`lmvp`.

You don't have to list every player who played — only the ones you have a
box score for. Missing a stat category for someone is fine too; just
omit that field and it counts as 0.

## 3. Managing rosters

Open `_data/players.yml`. Each player is:
```yaml
- id: deshawn-riley
  name: Deshawn Riley
  team: comets
  pos: PG
  num: 3
```
- To add a player: add an entry with a new, unique `id`.
- To cut/retire a player: delete their entry. Their historical stats stay
  intact in `games.yml` and still count toward season totals and records —
  only their current roster listing and team page entry disappear.
- `team` must match a `slug` in `teams.yml`, and `pos` should be one of
  `PG`, `SG`, `SF`, `PF`, `C` (used by the position filter on the Players page).

## 4. Managing franchises

Open `_data/teams.yml`. Each team's `primary`/`secondary` hex colors drive
that team's crest badge (generated automatically — no logo file to upload),
team page header, and the color dot next to their name everywhere on the
site. Change the colors any time and the crest updates on its own.

To add a 13th franchise: add a team entry here, add roster entries for them
in `players.yml`, and create `_teams/<slug>.md` containing just:
```
---
title: <slug>
slug: <slug>
---
```

## 5. Posting news

Duplicate any file in `_posts/`, rename it to
`YYYY-MM-DD-your-headline.md`, and edit the `title` and body. It appears on
the News page automatically, newest first.

## 6. Pages that build themselves

You never create these — the site generates them from `games.yml` and
`players.yml`:
- `/games/<id>/` — full box score for every played game
- `/players/<id>/` — season averages, career highs, game log for every player
- Standings, the MVP leaderboard, and the full records book

## 7. If something looks wrong

Check the **Actions** tab on GitHub — if a build fails, click into it for
the error. The most common cause is a typo in `games.yml` YAML formatting
(an extra/missing space) or a `player:`/`mvp:`/`lmvp:` id that doesn't
match anything in `players.yml`.

## Local preview (optional)

If you ever want to preview changes on your own computer before pushing
(requires Ruby):
```
bundle install
bundle exec jekyll serve
```
Then visit `http://localhost:4000`.
