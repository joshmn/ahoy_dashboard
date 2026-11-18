module AhoyDashboard
  module AiVisibility
    class ConversionEvidenceQuery < AhoyDashboard::Query
      DEFAULT_LIMIT = 10
      MAX_LIMIT = 25
      LOOKBACK_DAYS = 90
      THIN = 20
      MIN_VIEWERS = 3
      SEARCH_TERMS_PER_PAGE = 3

      GOAL = :goal
      SIGN_IN = :sign_in
      NONE = :none

      Count = Data.define(:label, :converters)

      EntryPage = Data.define(:path, :first_touch, :any_touch, :searches)

      Viewed = Data.define(:path, :converters, :others, :converter_share, :other_share) do
        def lift
          return nil if other_share.zero?

          converter_share / other_share
        end
      end

      AiLanding = Data.define(:path, :visitors, :converters, :assistants)

      Search = Data.define(:query, :clicks, :impressions)

      Result = Data.define(:anchor, :goal, :range, :lookback_days, :converters, :others, :channels, :entry_pages,
                           :paid_terms, :before_conversion, :ai_landings, :search_console) do
        def anchored?
          anchor != NONE
        end

        def thin?
          converters < THIN
        end
      end

      def initialize(scope:, goal: nil, limit: DEFAULT_LIMIT, lookback_days: LOOKBACK_DAYS)
        @scope = scope
        @goal = goal
        @limit = limit.to_i.clamp(1, MAX_LIMIT)
        @lookback_days = lookback_days.to_i.clamp(1, 365)
      end

      def call
        return empty if anchor == NONE

        rows = connection.select_rows(sql)
        entries = entry_pages(rows)

        Result.new(
          anchor: anchor, goal: goal, range: range, lookback_days: lookback_days,
          converters: total(rows, "converters"), others: total(rows, "others"),
          channels: counts(rows, "channel"), entry_pages: entries, paid_terms: counts(rows, "term"),
          before_conversion: before_conversion(rows), ai_landings: ai_landings(rows),
          search_console: search_console?
        )
      end

      private

      attr_reader :scope, :goal, :limit, :lookback_days

      def range
        scope.range
      end

      def connection
        AhoyDashboard.visit.connection
      end

      def anchor
        @anchor ||= if goal || AhoyDashboard::Goal.exists?
          GOAL
        elsif AhoyDashboard::Visitors::UserId.visits?
          SIGN_IN
        else
          NONE
        end
      end

      def empty
        Result.new(anchor: NONE, goal: goal, range: range, lookback_days: lookback_days, converters: 0, others: 0,
                   channels: [], entry_pages: [], paid_terms: [], before_conversion: [], ai_landings: [],
                   search_console: false)
      end

      def sql
        <<~SQL.squish
          with dash_ev_conversions as materialized (#{conversions_sql}),
               dash_ev_touches as materialized (#{touches_sql}),
               dash_ev_viewed as materialized (#{viewed_sql}),
               dash_ev_population as materialized (#{population_sql})
          #{[ totals_sql, channels_sql, entries_sql, terms_sql, viewed_rows_sql, baseline_sql,
              ai_sql ].join(" union all ")}
        SQL
      end

      def conversions_sql
        anchor == GOAL ? goal_conversions_sql : sign_in_conversions_sql
      end

      def goal_conversions_sql
        scope.session_events
          .unscope(:select, :order)
          .where(time: range)
          .where(Arel.sql(goal_predicate))
          .group(Arel.sql("ahoy_visits.visitor_token"))
          .select(Arel.sql("ahoy_visits.visitor_token as token, min(ahoy_events.time) as converted_at"))
          .to_sql
      end

      def goal_predicate
        goals = goal ? [ goal ] : AhoyDashboard::Goal.ordered.to_a

        "(#{goals.map { |one| "(#{Sql::GoalCompiler.new(goal: one).predicate})" }.join(" or ")})"
      end

      def sign_in_conversions_sql
        users = scope.visits.unscope(:select, :order).where("ahoy_visits.user_id is not null")
          .select(Arel.sql("ahoy_visits.user_id"))
        firsts = AhoyDashboard.visit.unscoped
          .where(Arel.sql("ahoy_visits.user_id in (#{users.to_sql})"))
          .order(Arel.sql("ahoy_visits.user_id, ahoy_visits.started_at, ahoy_visits.id"))
          .select(Arel.sql("distinct on (ahoy_visits.user_id) ahoy_visits.visitor_token as token, " \
                           "ahoy_visits.started_at as converted_at"))

        "select token, min(converted_at) as converted_at from (#{firsts.to_sql}) dash_ev_firsts " \
          "where converted_at >= #{Sql.timestamp(range.begin)} and converted_at <= #{Sql.timestamp(range.end)} " \
          "group by token"
      end

      def touches_sql
        relation = AhoyDashboard.visit.unscoped
          .joins("inner join dash_ev_conversions on dash_ev_conversions.token = ahoy_visits.visitor_token")
          .where(Arel.sql("ahoy_visits.started_at <= dash_ev_conversions.converted_at"))
          .where(Arel.sql("ahoy_visits.started_at >= dash_ev_conversions.converted_at - interval '#{lookback_days} days'"))
        unless scope.include_internal?
          relation = Sql::ExcludedTraffic.exclude(relation, floor: range.begin - lookback_days.days)
        end

        relation.select(Arel.sql(<<~SELECT.squish)).to_sql
          ahoy_visits.id, ahoy_visits.visitor_token, ahoy_visits.started_at, dash_ev_conversions.converted_at,
          row_number() over (partition by ahoy_visits.visitor_token
                             order by ahoy_visits.started_at, ahoy_visits.id) as touch,
          #{Sql::CHANNEL} as channel,
          #{entry_path} as path,
          nullif(btrim(lower(ahoy_visits.utm_term)), '') as term
        SELECT
      end

      def viewed_sql
        "select #{Sql::EVENT_PATH} as path, count(distinct dash_ev_touches.visitor_token) as converters " \
          "from ahoy_events inner join dash_ev_touches on dash_ev_touches.id = ahoy_events.visit_id " \
          "where #{Sql::PAGE_VIEW_EVENT} and #{ScopeQuery::HUMAN_EVENT} " \
          "and ahoy_events.time < dash_ev_touches.converted_at and nullif(#{Sql::EVENT_PATH}, '') is not null " \
          "group by 1 having count(distinct dash_ev_touches.visitor_token) >= #{MIN_VIEWERS}"
      end

      def population_sql
        scope.visits.unscope(:select, :order)
          .where(Arel.sql("not exists (select 1 from dash_ev_conversions where dash_ev_conversions.token = ahoy_visits.visitor_token)"))
          .select(Arel.sql("distinct ahoy_visits.visitor_token"))
          .to_sql
      end

      def totals_sql
        "select 'converters', null, count(*), 0, null from dash_ev_conversions " \
          "union all select 'others', null, count(*), 0, null from dash_ev_population"
      end

      def channels_sql
        "(select 'channel', channel, count(*), 0, null from dash_ev_touches where touch = 1 " \
          "group by channel order by count(*) desc, channel limit #{limit})"
      end

      def entries_sql
        "(select 'entry', path, count(distinct visitor_token) filter (where touch = 1), " \
          "count(distinct visitor_token), null from dash_ev_touches where path is not null " \
          "group by path order by 3 desc, 4 desc, path limit #{limit})"
      end

      def terms_sql
        "(select 'term', term, count(distinct visitor_token), 0, null from dash_ev_touches where term is not null " \
          "group by term order by 3 desc, term limit #{limit})"
      end

      def viewed_rows_sql
        "select 'viewed', path, converters, 0, null from dash_ev_viewed"
      end

      def baseline_sql
        others = scope.session_events.unscope(:select, :order)
          .where(time: range)
          .where(Arel.sql(Sql::PAGE_VIEW_EVENT))
          .where(Arel.sql("#{Sql::EVENT_PATH} in (select path from dash_ev_viewed)"))
          .where(Arel.sql("ahoy_visits.visitor_token in (select visitor_token from dash_ev_population)"))
          .group(Sql::EVENT_PATH)
          .select(Arel.sql("'baseline', #{Sql::EVENT_PATH}, count(distinct ahoy_visits.visitor_token), 0, null"))

        others.to_sql
      end

      def ai_sql
        landings = scope.visits.unscope(:select, :order)
          .where(Sql::AI_ASSISTANTS_PREDICATE)
          .where(Arel.sql("#{entry_path} is not null"))
          .group(Arel.sql(entry_path))
          .order(Arel.sql("count(distinct ahoy_visits.visitor_token) desc, #{entry_path}"))
          .limit(limit)
          .select(Arel.sql(<<~SELECT.squish))
            'ai', #{entry_path}, count(distinct ahoy_visits.visitor_token),
            count(distinct ahoy_visits.visitor_token) filter (where exists (
              select 1 from dash_ev_conversions where dash_ev_conversions.token = ahoy_visits.visitor_token)),
            string_agg(distinct #{Sql::DOMAIN}, ',')
          SELECT

        "(#{landings.to_sql})"
      end

      def entry_path
        @entry_path ||= Seo::PagePath.sql("ahoy_visits.landing_page")
      end

      def rows_of(rows, kind)
        rows.select { |row| row[0] == kind }
      end

      def total(rows, kind)
        rows_of(rows, kind).sum { |row| row[2].to_i }
      end

      def counts(rows, kind)
        rows_of(rows, kind).map { |row| Count.new(label: row[1].to_s, converters: row[2].to_i) }
      end

      def entry_pages(rows)
        pages = rows_of(rows, "entry")
        searches = searches_for(pages.map { |row| row[1] })

        pages.map do |row|
          EntryPage.new(path: row[1].to_s, first_touch: row[2].to_i, any_touch: row[3].to_i,
                        searches: searches.fetch(row[1], []))
        end
      end

      def before_conversion(rows)
        converters = total(rows, "converters")
        others = total(rows, "others")
        return [] if converters.zero?

        baseline = rows_of(rows, "baseline").to_h { |row| [ row[1], row[2].to_i ] }
        viewed = rows_of(rows, "viewed").map do |row|
          other = baseline.fetch(row[1], 0)
          Viewed.new(path: row[1].to_s, converters: row[2].to_i, others: other,
                     converter_share: row[2].to_f / converters, other_share: others.zero? ? 0.0 : other.to_f / others)
        end

        viewed.reject { |row| row.lift && row.lift < 1 }
          .sort_by { |row| [ -(row.lift || Float::INFINITY), -row.converters, row.path ] }
          .first(limit)
      end

      def ai_landings(rows)
        rows_of(rows, "ai").map do |row|
          AiLanding.new(path: row[1].to_s, visitors: row[2].to_i, converters: row[3].to_i,
                        assistants: row[4].to_s.split(",").reject(&:blank?).sort)
        end
      end

      def search_console?
        @search_console = AhoyDashboard::Installation.installed?(:search_console) if @search_console.nil?
        @search_console
      end

      def searches_for(paths)
        return {} if paths.empty? || !search_console?

        page = Seo::PagePath.sql("page")
        ranked = AhoyDashboard::SearchConsoleRow.in_range(range)
          .where(page.in(paths))
          .group(page, :query)
          .select(Arel.sql(<<~SELECT.squish))
            #{page} as path, query, sum(clicks) as clicks, sum(impressions) as impressions,
            row_number() over (partition by #{page} order by sum(clicks) desc, sum(impressions) desc, query) as rank
          SELECT

        AhoyDashboard::SearchConsoleRow.unscoped.from(ranked, :ranked)
          .where("ranked.rank <= ?", SEARCH_TERMS_PER_PAGE)
          .order(Arel.sql("ranked.path, ranked.rank"))
          .pluck(Arel.sql("ranked.path"), Arel.sql("ranked.query"), Arel.sql("ranked.clicks"),
                 Arel.sql("ranked.impressions"))
          .group_by(&:first)
          .transform_values do |found|
            found.map { |_path, query, clicks, impressions| Search.new(query: query, clicks: clicks.to_i, impressions: impressions.to_i) }
          end
      end
    end
  end
end
