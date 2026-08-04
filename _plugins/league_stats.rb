##
# League Stats Generator
#
# Reads _data/players.yml and _data/games.yml and computes, at build time:
#   site.data['stats']            -> per-player season totals/averages/highs
#   site.data['records']['league'] -> league-wide record book
#   site.data['records']['teams']  -> per-team record book
#
# Nobody edits these by hand. Commissioners only ever edit games.yml
# (enter the box score) and players.yml (roster). Everything else here
# is derived.
##
module LeagueStats
  STAT_KEYS = %w[pts reb oreb dreb ast blk tov fouls].freeze

  class Generator < Jekyll::Generator
    priority :high

    def generate(site)
      players = site.data['players'] || []
      games   = site.data['games'] || []

      players_by_id = {}
      players.each { |p| players_by_id[p['id']] = p }

      stats = {}
      players.each do |p|
        stats[p['id']] = blank_stat_line(p)
      end

      played_games = games.select { |g| g['played'] }

      played_games.each do |game|
        box = game['box'] || {}
        box.each do |team_slug, entries|
          (entries || []).each do |entry|
            pid = entry['player']
            line = stats[pid]
            next unless line # skip unknown player ids rather than crashing the build

            line['games'] += 1

            reb = entry['oreb'].to_i + entry['dreb'].to_i
            values = {
              'pts' => entry['pts'].to_i,
              'oreb' => entry['oreb'].to_i,
              'dreb' => entry['dreb'].to_i,
              'reb' => reb,
              'ast' => entry['ast'].to_i,
              'blk' => entry['blk'].to_i,
              'tov' => entry['tov'].to_i,
              'fouls' => entry['fouls'].to_i
            }

            values.each do |k, v|
              line['totals'][k] += v
              if v > line['highs'][k]['value']
                opp = (team_slug == game['home']) ? game['away'] : game['home']
                line['highs'][k] = {
                  'value' => v,
                  'date' => game['date'],
                  'opponent' => opp,
                  'game_id' => game['id']
                }
              end
            end

            double_count = [values['pts'], values['reb'], values['ast'], values['blk']].count { |v| v >= 10 }
            line['double_doubles'] += 1 if double_count >= 2
            line['triple_doubles'] += 1 if double_count >= 3

            line['mvp_count'] += 1 if game['mvp'] == pid
            line['lmvp_count'] += 1 if game['lmvp'] == pid
          end
        end
      end

      stats.each_value { |line| finalize_averages(line) }

      site.data['stats'] = stats
      # Liquid's `sort` / `where_exp` filters expect an Array (they mangle a
      # Hash into [key, value] pairs). Keep `stats` as a Hash for id lookups
      # like site.data.stats[game.mvp], and use `stats_list` for anything
      # that needs to be sorted or filtered.
      site.data['stats_list'] = stats.values
      site.data['leaderboard'] = stats.values.sort_by { |l| [-l['mvp_count'], -l['avgs']['pts']] }
      site.data['records'] = {
        'league' => build_record_book(stats.values, players_by_id, games),
        'teams' => build_team_record_books(stats.values, players_by_id, games)
      }

      site.data['computed_standings'] = build_standings(site.data['teams'] || [], played_games)

      generate_game_pages(site, games, players_by_id)
      generate_player_pages(site, players, stats, played_games)
      build_bracket(site)
    end

    private

    ##
    # Resolves _data/bracket.yml into site.data['bracket_resolved'].
    #
    # bracket.yml lists matches with home_seed/away_seed (a team slug, or
    # null if that slot is filled by a feeder match's winner/loser),
    # winner_to / loser_to (the id of the match the winner/loser advances
    # to, or null if there's nowhere to advance -- eliminated, or it's the
    # last match), and an optional game_id linking to the real result in
    # games.yml.
    #
    # A match with a home_seed, no away_seed, and no game_id is a bye:
    # the home team auto-advances, no game needed.
    ##
    def build_bracket(site)
      data = site.data['bracket']
      return unless data

      teams_by_slug = {}
      (site.data['teams'] || []).each { |t| teams_by_slug[t['slug']] = t }

      games_by_id = {}
      (site.data['games'] || []).each { |g| games_by_id[g['id']] = g }

      matches = {}
      %w[winners losers].each do |section|
        (data[section] || []).each do |m|
          matches[m['id']] = m.merge(
            'bracket' => section,
            'home_resolved' => m['home_seed'],
            'away_resolved' => m['away_seed']
          )
        end
      end
      if data['grand_final']
        gf = data['grand_final']
        matches[gf['id']] = gf.merge(
          'bracket' => 'grand_final',
          'home_resolved' => gf['home_seed'],
          'away_resolved' => gf['away_seed']
        )
      end

      place = lambda do |match_id, team_slug|
        return if match_id.nil? || team_slug.nil?
        m = matches[match_id]
        return unless m
        return if m['home_resolved'] == team_slug || m['away_resolved'] == team_slug
        if m['home_resolved'].nil?
          m['home_resolved'] = team_slug
        elsif m['away_resolved'].nil?
          m['away_resolved'] = team_slug
        end
      end

      # Repeated sweeps let results propagate through the bracket
      # regardless of the order matches happen to appear in the yaml.
      # 20 sweeps comfortably covers any realistic bracket depth.
      20.times do
        matches.each_value do |m|
          home = m['home_resolved']
          away = m['away_resolved']
          winner = nil
          loser = nil

          if home && away.nil? && m['game_id'].nil?
            winner = home # bye
          elsif m['game_id'] && (g = games_by_id[m['game_id']]) && g['played']
            if g['home_score'].to_i > g['away_score'].to_i
              winner, loser = g['home'], g['away']
            else
              winner, loser = g['away'], g['home']
            end
          end

          m['winner'] = winner
          m['loser'] = loser
          place.call(m['winner_to'], winner) if winner
          place.call(m['loser_to'], loser) if loser
        end
      end

      matches.each_value do |m|
        m['home_team'] = m['home_resolved'] ? teams_by_slug[m['home_resolved']] : nil
        m['away_team'] = m['away_resolved'] ? teams_by_slug[m['away_resolved']] : nil
        m['game'] = m['game_id'] ? games_by_id[m['game_id']] : nil
        m['status'] =
          if m['winner']
            (m['away_resolved'].nil? && m['game_id'].nil?) ? 'bye' : 'final'
          elsif m['home_resolved'] && m['away_resolved']
            'ready'
          else
            'tbd'
          end
      end

      site.data['bracket_resolved'] = {
        'winners' => (data['winners'] || []).map { |m| matches[m['id']] },
        'losers' => (data['losers'] || []).map { |m| matches[m['id']] },
        'grand_final' => data['grand_final'] ? matches[data['grand_final']['id']] : nil
      }
    end

    def blank_stat_line(player)
      {
        'id' => player['id'],
        'name' => player['name'],
        'team' => player['team'],
        'pos' => player['pos'],
        'num' => player['num'],
        'games' => 0,
        'totals' => STAT_KEYS.each_with_object({}) { |k, h| h[k] = 0 },
        'avgs' => STAT_KEYS.each_with_object({}) { |k, h| h[k] = 0.0 },
        'highs' => STAT_KEYS.each_with_object({}) { |k, h| h[k] = { 'value' => 0, 'date' => nil, 'opponent' => nil, 'game_id' => nil } },
        'double_doubles' => 0,
        'triple_doubles' => 0,
        'mvp_count' => 0,
        'lmvp_count' => 0
      }
    end

    def finalize_averages(line)
      g = line['games']
      STAT_KEYS.each do |k|
        line['avgs'][k] = g > 0 ? (line['totals'][k].to_f / g).round(1) : 0.0
      end
      # flat aliases for easy access in Liquid (avoids nested-key lookups)
      line['ppg'] = line['avgs']['pts']
      line['rpg'] = line['avgs']['reb']
      line['apg'] = line['avgs']['ast']
      line['bpg'] = line['avgs']['blk']
      line['topg'] = line['avgs']['tov']
      line['fpg'] = line['avgs']['fouls']
    end

    def build_standings(teams, played_games)
      sorted_games = played_games.sort_by { |g| g['date'] }
      records = {}
      teams.each { |t| records[t['slug']] = { 'slug' => t['slug'], 'wins' => 0, 'losses' => 0, 'results' => [] } }

      sorted_games.each do |g|
        home, away = g['home'], g['away']
        next unless records[home] && records[away]
        home_win = g['home_score'].to_i > g['away_score'].to_i
        if home_win
          records[home]['wins'] += 1
          records[away]['losses'] += 1
        else
          records[home]['losses'] += 1
          records[away]['wins'] += 1
        end
        records[home]['results'] << (home_win ? 'W' : 'L')
        records[away]['results'] << (home_win ? 'L' : 'W')
      end

      records.each_value do |r|
        last = r['results'].last
        streak_len = r['results'].reverse.take_while { |x| x == last }.length
        r['streak'] = last ? "#{last}#{streak_len}" : "—"
        r.delete('results')
      end

      records.values
    end

    # category => { career: [top N], game: [top N], avg: [top N] }
    def build_record_book(lines, players_by_id, games, min_games_for_avg: 1)
      book = {}
      STAT_KEYS.each do |k|
        career = lines.reject { |l| l['games'].zero? }
                       .sort_by { |l| -l['totals'][k] }
                       .first(5)
                       .map { |l| { 'player' => l['id'], 'name' => l['name'], 'team' => l['team'], 'value' => l['totals'][k] } }

        game_highs = lines.reject { |l| l['highs'][k]['value'].zero? }
                           .sort_by { |l| -l['highs'][k]['value'] }
                           .first(5)
                           .map { |l| { 'player' => l['id'], 'name' => l['name'], 'team' => l['team'], 'value' => l['highs'][k]['value'], 'date' => l['highs'][k]['date'], 'opponent' => l['highs'][k]['opponent'], 'game_id' => l['highs'][k]['game_id'] } }

        per_game = lines.select { |l| l['games'] >= min_games_for_avg }
                         .sort_by { |l| -l['avgs'][k] }
                         .first(5)
                         .map { |l| { 'player' => l['id'], 'name' => l['name'], 'team' => l['team'], 'value' => l['avgs'][k] } }

        book[k] = { 'career' => career, 'game' => game_highs, 'avg' => per_game }
      end

      book['mvp'] = lines.reject { |l| l['mvp_count'].zero? }
                          .sort_by { |l| -l['mvp_count'] }
                          .first(5)
                          .map { |l| { 'player' => l['id'], 'name' => l['name'], 'team' => l['team'], 'value' => l['mvp_count'] } }

      book['lmvp'] = lines.reject { |l| l['lmvp_count'].zero? }
                           .sort_by { |l| -l['lmvp_count'] }
                           .first(5)
                           .map { |l| { 'player' => l['id'], 'name' => l['name'], 'team' => l['team'], 'value' => l['lmvp_count'] } }

      book
    end

    def build_team_record_books(lines, players_by_id, games)
      by_team = {}
      lines.group_by { |l| l['team'] }.each do |team_slug, team_lines|
        by_team[team_slug] = build_record_book(team_lines, players_by_id, games)
      end
      by_team
    end

    # Auto-generate a static page for every played game at /games/<id>/
    def generate_game_pages(site, games, players_by_id)
      games.each do |game|
        next unless game['played']
        site.pages << GamePage.new(site, game, players_by_id)
      end
    end

    # Auto-generate a static page for every player at /players/<id>/
    def generate_player_pages(site, players, stats, played_games)
      players.each do |player|
        pid = player['id']
        game_log = played_games.select { |g| (g['box'] || {}).values.flatten.any? { |e| e['player'] == pid } }
                                .sort_by { |g| g['date'] }
                                .reverse
        site.pages << PlayerPage.new(site, player, stats[pid], game_log)
      end
    end
  end

  class GamePage < Jekyll::Page
    def initialize(site, game, players_by_id)
      @site = site
      @base = site.source
      @dir = File.join('games', game['id'])
      @basename = 'index'
      @ext = '.html'
      @name = 'index.html'

      self.process(@name)
      self.content = ""
      self.data = {
        'layout' => 'game',
        'title' => "#{game['away']} @ #{game['home']}",
        'game' => game
      }
    end
  end

  class PlayerPage < Jekyll::Page
    def initialize(site, player, stat_line, game_log)
      @site = site
      @base = site.source
      @dir = File.join('players', player['id'])
      @basename = 'index'
      @ext = '.html'
      @name = 'index.html'

      self.process(@name)
      self.content = ""
      self.data = {
        'layout' => 'player',
        'title' => player['name'],
        'player' => player,
        'stat_line' => stat_line,
        'game_log' => game_log
      }
    end
  end
end
