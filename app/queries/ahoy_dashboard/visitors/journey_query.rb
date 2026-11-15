module AhoyDashboard
  module Visitors
    class JourneyQuery < AhoyDashboard::Query
      VISITS_PER_PAGE = 20
      EVENTS_PER_VISIT = 200
      MAX_USERS = 20
      MAX_VISITS = 10_000

      ORDER = "ahoy_visits.started_at, ahoy_visits.id".freeze
      EVENT_ORDER = "ahoy_events.visit_id, ahoy_events.time, ahoy_events.id".freeze

      Event = Data.define(:id, :visit_id, :name, :time, :properties, :user_id) do
        def page_view?
          name == AhoyDashboard::PAGE_VIEW
        end

        def path
          properties["path"].to_s.presence if page_view?
        end
      end

      Visit = Data.define(:record, :events, :event_count) do
        delegate :id, :started_at, :visitor_token, to: :record

        def capped?
          event_count > events.size
        end

        def read(column)
          record.has_attribute?(column) ? record[column].presence : nil
        end
      end

      Identified = Data.define(:visit_id, :event_id, :at, :visit_started_at)

      Result = Data.define(:person, :visits, :page, :pages, :per_page, :total_visits, :hidden_visits, :total_events,
                           :first_at, :last_at, :user_ids, :identified, :identified_page) do
        def empty?
          visits.empty?
        end

        def paged?
          pages > 1
        end
      end

      def initialize(person:, page: 1, include_crawlers: false, include_internal: false,
                     per_page: VISITS_PER_PAGE, events_per_visit: EVENTS_PER_VISIT)
        @person = person
        @requested_page = page.to_s.to_i
        @include_crawlers = include_crawlers
        @include_internal = include_internal
        @per_page = per_page.to_i.clamp(1, 500)
        @events_per_visit = events_per_visit.to_i.clamp(1, 10_000)
      end

      def call
        first_at, last_at, shown_count = shown.pick(Arel.sql("min(ahoy_visits.started_at)"),
                                                    Arel.sql("max(ahoy_visits.started_at)"), Arel.sql("count(*)"))
        shown_count = shown_count.to_i
        pages = [ (shown_count.to_f / per_page).ceil, 1 ].max
        page = requested_page.clamp(1, pages)
        mark = identified

        Result.new(
          person: person,
          visits: visits_on(page),
          page: page,
          pages: pages,
          per_page: per_page,
          total_visits: shown_count,
          hidden_visits: [ person_ids.size - shown_count, 0 ].max,
          total_events: events.where(visit_id: shown.select(:id)).count,
          first_at: first_at,
          last_at: last_at,
          user_ids: user_ids,
          identified: mark,
          identified_page: mark && page_at(mark.visit_started_at, mark.visit_id)
        )
      end

      def page_of(visit)
        return nil unless shown.where(id: visit.id).exists?

        page_at(visit.started_at, visit.id)
      end

      private

      attr_reader :person, :requested_page, :include_crawlers, :include_internal, :per_page, :events_per_visit

      def person_ids
        @person_ids ||= person.visits.reorder(Arel.sql(ORDER)).limit(MAX_VISITS).pluck(:id)
      end

      def shown
        @shown ||= begin
          relation = AhoyDashboard.visit.where(id: person_ids)
          relation = Sql::ExcludedTraffic.exclude(relation) unless include_internal
          include_crawlers ? relation : relation.where(id: events.where(visit_id: person_ids).select(:visit_id))
        end
      end

      def events
        relation = AhoyDashboard.event.all
        include_crawlers ? relation : relation.where(Arel.sql(ScopeQuery::HUMAN_EVENT))
      end

      def page_at(started_at, id)
        before = shown.where(Arel.sql("(ahoy_visits.started_at, ahoy_visits.id) < (:at, :id)"), at: started_at, id: id).count

        (before / per_page) + 1
      end

      def visits_on(page)
        records = shown.reorder(Arel.sql(ORDER)).limit(per_page).offset((page - 1) * per_page).to_a
        grouped = events_of(records.map(&:id))

        records.map do |record|
          listed, count = grouped.fetch(record.id, [ [], 0 ])
          Visit.new(record: record, events: listed, event_count: count)
        end
      end

      def events_of(ids)
        return {} if ids.empty?

        ranked = events.where(visit_id: ids).select(Arel.sql(<<~SQL.squish))
          ahoy_events.id as tm_id,
          row_number() over (partition by ahoy_events.visit_id order by ahoy_events.time, ahoy_events.id) as tm_position,
          count(*) over (partition by ahoy_events.visit_id) as tm_total
        SQL

        rows = AhoyDashboard.event
          .joins(Arel.sql("inner join (#{ranked.to_sql}) tm_ranked on tm_ranked.tm_id = ahoy_events.id"))
          .where(Arel.sql("tm_ranked.tm_position <= :cap"), cap: events_per_visit)
          .reorder(Arel.sql(EVENT_ORDER))
          .select(Arel.sql("ahoy_events.*, tm_ranked.tm_total as tm_total"))

        rows.each_with_object({}) do |row, grouped|
          entry = (grouped[row.visit_id] ||= [ [], row[:tm_total].to_i ])
          entry.first << event_for(row)
        end
      end

      def event_for(row)
        Event.new(
          id: row.id,
          visit_id: row.visit_id,
          name: row.name.to_s,
          time: row.time,
          properties: properties(row.properties),
          user_id: (row[:user_id] if row.has_attribute?(:user_id))
        )
      end

      def properties(value)
        parsed = value.is_a?(String) ? JSON.parse(value) : value
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def user_ids
        return [] unless UserId.visits?

        shown.where.not(user_id: nil).distinct.limit(MAX_USERS).pluck(:user_id)
      end

      def identified
        return nil unless UserId.visits?

        visit_mark = marked_visits.reorder(Arel.sql(ORDER)).limit(1).pluck(:id, :started_at).first
        event_mark = first_marked_event(visit_mark)

        if event_mark && (visit_mark.nil? || event_mark[1] == visit_mark[0] || event_mark[3] < visit_mark[1])
          Identified.new(visit_id: event_mark[1], event_id: event_mark[0], at: event_mark[2], visit_started_at: event_mark[3])
        elsif visit_mark
          Identified.new(visit_id: visit_mark[0], event_id: nil, at: visit_mark[1], visit_started_at: visit_mark[1])
        end
      end

      def marked_visits
        person.user? ? shown.where(user_id: person.user_id) : shown.where.not(user_id: nil)
      end

      def first_marked_event(visit_mark)
        return nil unless UserId.events?

        relation =
          if person.user?
            events.where(user_id: person.user_id).where(visit_id: shown.select(:id))
          elsif visit_mark
            events.where(visit_id: visit_mark[0]).where.not(user_id: nil)
          end
        return nil if relation.nil?

        relation.joins(:visit).reorder(Arel.sql("ahoy_events.time, ahoy_events.id")).limit(1)
          .pluck(Arel.sql("ahoy_events.id"), Arel.sql("ahoy_events.visit_id"), Arel.sql("ahoy_events.time"),
                 Arel.sql("ahoy_visits.started_at")).first
      end
    end
  end
end
