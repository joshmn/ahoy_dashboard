module AhoyDashboard
  class RealtimeQuery < AhoyDashboard::Query
    DEFAULT_WINDOW = 5.minutes
    LOOKBACK = 30.minutes
    ROWS = 8
    ALIAS = "dash_now".freeze

    Row = Data.define(:label, :visitors, :share)
    Snapshot = Data.define(:window, :visitors, :pages, :sources)

    class << self
      def snapshot
        new.snapshot
      end
    end

    def call
      current_page_views.distinct.count(Sql::VISITOR_TOKEN)
    end

    def snapshot
      counted = AhoyDashboard.event.connection.select_rows(<<~SQL)
        with #{ALIAS} as materialized (#{latest_per_visitor.to_sql})
        select 0 as kind, null::text as label, count(*) as visitors from #{ALIAS}
        union all (#{grouped_rows("page", 1).to_sql})
        union all (#{grouped_rows("source", 2).to_sql})
        order by kind, visitors desc, label
      SQL

      Snapshot.new(
        window: DEFAULT_WINDOW,
        visitors: counted.first.last,
        pages: build(counted.map { |kind, label, count| [ label, count ] if kind == 1 }.select { |value| value }),
        sources: build(counted.map { |kind, label, count| [ label, count ] if kind == 2 }.select { |value| value })
      )
    end

    private

    def current_events
      AhoyDashboard::Sql::ExcludedTraffic.exclude(
        AhoyDashboard.event
          .joins(:visit)
          .where(AhoyDashboard.event.arel_table[:time].gteq(DEFAULT_WINDOW.ago))
          .where(ScopeQuery::HUMAN_EVENT)
      )
    end

    def current_page_views
      AhoyDashboard::Sql::ExcludedTraffic.exclude(AhoyDashboard.event.joins(:visit))
        .where(AhoyDashboard.event.arel_table[:time].gteq([ DEFAULT_WINDOW, LOOKBACK ].max.ago))
        .where(ScopeQuery::HUMAN_EVENT)
        .where(name: AhoyDashboard::PAGE_VIEW)
        .where(Arel.sql("ahoy_visits.visitor_token in (#{current_events.select("ahoy_visits.visitor_token").to_sql})"))
    end

    def latest_per_visitor
      current_page_views
        .reorder(Arel.sql("ahoy_visits.visitor_token, ahoy_events.time desc, ahoy_events.id desc"))
        .select(Arel.sql(
          "distinct on (ahoy_visits.visitor_token) ahoy_visits.visitor_token as visitor_token, " \
          "(#{Sql::EVENT_PATH}) as page, (#{Sql::SOURCE}) as source"
        ))
    end

    def grouped_rows(column, kind)
      AhoyDashboard.event
        .unscoped
        .from(Arel.sql(ALIAS))
        .select(Arel.sql("#{kind} as kind, #{column} as label, count(*) as visitors"))
        .group(Arel.sql(column))
        .order(Arel.sql("count(*) desc, label"))
        .limit(ROWS)
    end

    def build(counted)
      largest = counted.map(&:last).max.to_i

      counted.map do |label, visitors|
        Row.new(
          label: label.presence || Dimension::UNKNOWN_LABEL,
          visitors: visitors,
          share: largest.positive? ? visitors.to_f / largest : 0.0
        )
      end
    end
  end
end
