module AhoyDashboard
  # Who is on the site right now. Not scoped to the dashboard's range or filters,
  # because "who is on the site right now" is the same answer whatever the page
  # below it is showing.
  #
  # DEFAULT_WINDOW is the only window there is. The pill in the header, the poll
  # that refreshes it and the realtime page all read it, so the number cannot
  # change meaning between the load and the next refresh.
  class RealtimeQuery
    DEFAULT_WINDOW = 5.minutes
    LOOKBACK = 30.minutes
    ROWS = 8
    ALIAS = "dash_now".freeze

    Row = Data.define(:label, :visitors, :share)
    Snapshot = Data.define(:window, :visitors, :pages, :sources)

    def self.call(**options)
      new(**options).call
    end

    def self.snapshot(**options)
      new(**options).snapshot
    end

    def initialize(window: DEFAULT_WINDOW, rows: ROWS)
      @window = window
      @rows = rows
    end

    def call
      current_page_views.distinct.count("ahoy_visits.visitor_token")
    end

    # What the realtime page reads: the same count, plus where those people are
    # and how they got here.
    def snapshot
      counted = AhoyDashboard.event.connection.select_rows(<<~SQL)
        with #{ALIAS} as materialized (#{latest_per_visitor.to_sql})
        select 0 as kind, null::text as label, count(*) as visitors from #{ALIAS}
        union all (#{grouped_rows("page", 1).to_sql})
        union all (#{grouped_rows("source", 2).to_sql})
        order by kind, visitors desc, label
      SQL

      Snapshot.new(
        window: window,
        visitors: counted.first.last,
        pages: build(counted.map { |kind, label, count| [ label, count ] if kind == 1 }.select { |value| value }),
        sources: build(counted.map { |kind, label, count| [ label, count ] if kind == 2 }.select { |value| value })
      )
    end

    private

    attr_reader :window, :rows

    def current_events
      AhoyDashboard::Sql::ExcludedTraffic.exclude(
        AhoyDashboard.event
          .joins(:visit)
          .where(AhoyDashboard.event.arel_table[:time].gteq(window.ago))
          .where(ScopeQuery::HUMAN_EVENT)
      )
    end

    def current_page_views
      AhoyDashboard::Sql::ExcludedTraffic.exclude(AhoyDashboard.event.joins(:visit))
        .where(AhoyDashboard.event.arel_table[:time].gteq([window, LOOKBACK].max.ago))
        .where(ScopeQuery::HUMAN_EVENT)
        .where(name: AhoyDashboard::PAGE_VIEW)
        .where(Arel.sql("ahoy_visits.visitor_token in (#{current_events.select("ahoy_visits.visitor_token").to_sql})"))
    end

    # A person is on one page, not on all four they opened in the last five
    # minutes, so both lists count people by their latest page view. Counting
    # page views instead would report more people than are here, and the two
    # lists would describe different populations.
    def latest_per_visitor
      current_page_views
        .reorder(Arel.sql("ahoy_visits.visitor_token, ahoy_events.time desc, ahoy_events.id desc"))
        .select(Arel.sql(
          "distinct on (ahoy_visits.visitor_token) ahoy_visits.visitor_token as visitor_token, " \
          "(#{Sql::EVENT_PATH}) as page, (#{Sql::SOURCE}) as source"
        ))
    end

    # Ahoy::Event is only the carrier: the FROM is replaced by the derived table
    # and none of its own columns are read.
    def grouped_rows(column, kind)
      AhoyDashboard.event
        .unscoped
        .from(Arel.sql(ALIAS))
        .select(Arel.sql("#{kind} as kind, #{column} as label, count(*) as visitors"))
        .group(Arel.sql(column))
        .order(Arel.sql("count(*) desc, label"))
        .limit(rows)
    end

    # Scaled against the biggest row rather than the total, the same way the
    # breakdown cards are, so the top row fills its bar and the rest are read
    # against it.
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
