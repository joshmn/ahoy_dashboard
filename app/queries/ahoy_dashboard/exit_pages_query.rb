module AhoyDashboard
  # The exit page is the last page view of a session, which no column records,
  # so it is a distinct on over the visit ordered by time descending.
  class ExitPagesQuery
    ALIAS = "dash_exits".freeze

    def self.call(**options)
      new(**options).call
    end

    def self.join_sql(scope)
      "left join (#{call(scope: scope).to_sql}) #{ALIAS} on #{ALIAS}.visit_id = ahoy_visits.id"
    end

    # A relation whose FROM is the derived table, so a filter can be applied to
    # the exit path itself. AhoyDashboard.visit is only the carrier for the query: the
    # FROM is replaced and nothing reads its columns.
    def self.relation(source)
      AhoyDashboard.visit.unscoped.from(Arel.sql("(#{new(source: source).call.to_sql}) #{ALIAS}"))
    end

    def initialize(scope: nil, source: nil)
      @source = source || scope.exits_source
    end

    def call
      source
        .reorder(Arel.sql("ahoy_events.visit_id, ahoy_events.time desc, ahoy_events.id desc"))
        .select(Arel.sql(
          "distinct on (ahoy_events.visit_id) ahoy_events.visit_id as visit_id, " \
          "#{AhoyDashboard::Sql::EVENT_PATH} as path"
        ))
    end

    private

    attr_reader :source
  end
end
