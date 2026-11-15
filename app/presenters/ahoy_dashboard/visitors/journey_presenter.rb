module AhoyDashboard
  module Visitors
    class JourneyPresenter
      TIME = "%-l:%M:%S %p".freeze
      CLOCK = "%-l:%M %p".freeze
      DAY = "%a, %b %-d, %Y".freeze
      MOMENT = "%b %-d, %Y %-l:%M %p".freeze
      MAX_VALUE = 160
      MAX_PROPERTIES = 12
      HIDDEN_PROPERTIES = %w[path].freeze

      Fact = Data.define(:label, :value, :path, :mono)

      class EventView
        delegate :id, :name, :page_view?, :path, to: :event

        attr_reader :gap

        def self.anchor(id)
          "event-#{id}"
        end

        def initialize(event:, gap:, presenter:)
          @event = event
          @gap = gap
          @presenter = presenter
        end

        def anchor
          self.class.anchor(id)
        end

        def time_label
          presenter.zoned(event.time)&.strftime(TIME)
        end

        def gap_label
          gap && "+#{JourneyPresenter.duration(gap)}"
        end

        def title
          page_view? ? (path || "(no path)") : name
        end

        def details
          shown = event.properties.reject { |key, _value| page_view? && HIDDEN_PROPERTIES.include?(key.to_s) }
          parts = shown.first(MAX_PROPERTIES).map { |key, value| "#{key}: #{JourneyPresenter.value(value)}" }
          parts << "and #{shown.size - MAX_PROPERTIES} more" if shown.size > MAX_PROPERTIES

          parts.join(", ").presence
        end

        def identified?
          presenter.identified_event?(event)
        end

        private

        attr_reader :event, :presenter
      end

      class VisitView
        delegate :id, :started_at, :capped?, :event_count, :visitor_token, to: :visit

        def initialize(visit:, previous:, presenter:)
          @visit = visit
          @previous = previous
          @presenter = presenter
        end

        def anchor
          Destination.anchor(id)
        end

        def heading_id
          "#{anchor}-title"
        end

        def day_label
          presenter.zoned(started_at)&.strftime(DAY)
        end

        def time_label
          presenter.zoned(started_at)&.strftime(CLOCK)
        end

        def gap_label
          return nil if previous.nil?

          "#{JourneyPresenter.duration(started_at - previous.started_at)} after the last visit"
        end

        def identified?
          presenter.identified_visit?(visit)
        end

        def source
          visit.read("referring_domain") || (visit.read("utm_source") ? nil : "Direct")
        end

        def facts
          [
            fact("Source", source),
            fact("Referrer", visit.read("referrer"), mono: true),
            fact("Campaign", campaign),
            fact("Landed on", visit.read("landing_page"), mono: true),
            fact("Device", device),
            fact("Platform", visit.read("platform")),
            fact("Location", presenter.place(visit.read("city"), visit.read("region"), visit.read("country"))),
            user_fact,
            (fact("Visitor", presenter.short_token(visitor_token), path: presenter.visitor_path(visitor_token), mono: true) if presenter.user?),
            fact("Visit token", visit.read("visit_token"), mono: true)
          ].compact
        end

        def events
          @events ||= begin
            last = started_at
            visit.events.map do |event|
              gap = event.time && last ? event.time - last : nil
              last = event.time || last
              EventView.new(event: event, gap: gap, presenter: presenter)
            end
          end
        end

        def empty?
          visit.events.empty?
        end

        def cap_note
          return nil unless capped?

          "Showing the first #{presenter.number(visit.events.size)} of #{presenter.number(event_count)} events in this visit."
        end

        private

        attr_reader :visit, :previous, :presenter

        def campaign
          parts = %w[utm_source utm_medium utm_campaign utm_term utm_content].map { |column| visit.read(column) }
          parts.compact.join(" / ").presence
        end

        def device
          system = [ visit.read("os"), visit.read("os_version") ].compact.join(" ").presence
          browser = [ visit.read("browser"), (system && "on #{system}") ].compact.join(" ").presence
          [ browser, visit.read("device_type") ].compact.join(", ").presence
        end

        def user_fact
          user_id = visit.read(UserId::COLUMN)
          return nil if user_id.nil?

          fact("User", presenter.user_label(user_id), path: presenter.user_path(user_id))
        end

        def fact(label, value, path: nil, mono: false)
          Fact.new(label: label, value: value.to_s, path: path, mono: mono) if value.present?
        end
      end

      class << self
        def duration(seconds)
          total = seconds.to_f.round
          return "0s" if total <= 0

          days, rest = total.divmod(86_400)
          hours, rest = rest.divmod(3_600)
          minutes, secs = rest.divmod(60)
          parts =
            if days.positive? then [ [ days, "d" ], [ hours, "h" ] ]
            elsif hours.positive? then [ [ hours, "h" ], [ minutes, "m" ] ]
            elsif minutes.positive? then [ [ minutes, "m" ], [ secs, "s" ] ]
            else [ [ secs, "s" ] ]
            end

          parts.reject.with_index { |(amount, _unit), index| index.positive? && amount.zero? }
            .map { |amount, unit| "#{amount}#{unit}" }.join(" ")
        end

        def value(raw)
          text = raw.is_a?(Hash) || raw.is_a?(Array) ? raw.to_json : raw.to_s
          text.length > MAX_VALUE ? "#{text.first(MAX_VALUE)}..." : text
        end
      end

      attr_reader :query, :result

      delegate :person, :page, :pages, :total_visits, :hidden_visits, :total_events, :identified, to: :result
      delegate :user?, to: :person

      def initialize(query:, result:, routes:)
        @query = query
        @result = result
        @routes = routes
      end

      def title
        user? ? user_label(person.user_id) : "Visitor"
      end

      def lede
        user? ? nil : person.key
      end

      def back
        { url: routes.visitors_path(query.to_query), label: IndexPresenter::TITLE }
      end

      def visits
        @visits ||= result.visits.each_with_index.map do |visit, index|
          VisitView.new(visit: visit, previous: (result.visits[index - 1] if index.positive?), presenter: self)
        end
      end

      def empty?
        result.empty?
      end

      def first_seen
        moment(result.first_at)
      end

      def last_seen
        result.last_at && AhoyDashboard::DateFormat.ago(result.last_at)
      end

      def last_seen_title
        moment(result.last_at)
      end

      def identified_label
        identified ? moment(identified.at) : "Never"
      end

      def identified_path
        return nil if identified.nil?

        anchor = identified.event_id ? EventView.anchor(identified.event_id) : Destination.anchor(identified.visit_id)

        page_path(identified_page, anchor: anchor)
      end

      def identified_visit?(visit)
        identified && identified.visit_id == visit.id && identified.event_id.nil?
      end

      def identified_event?(event)
        identified && identified.event_id == event.id
      end

      def identities
        if user?
          person.visitor_tokens.map { |token| Fact.new(label: "Visitor", value: short_token(token), path: visitor_path(token), mono: true) }
        else
          result.user_ids.map { |user_id| Fact.new(label: "User", value: user_label(user_id), path: user_path(user_id), mono: false) }
        end
      end

      def hidden?
        hidden_visits.positive?
      end

      def showing_hidden?
        query.include_crawlers? && query.include_internal?
      end

      def hidden_label
        "#{AhoyDashboard::Counted.call(hidden_visits, noun: "visit")} hidden"
      end

      def toggle_hidden_path
        params = Destination.carried(query)
        params = showing_hidden? ? params.except(*Destination::TOGGLES) :
          params.merge(crawlers: QueryForm::CRAWLERS_ON, internal: QueryForm::INTERNAL_ON)

        own_path(params)
      end

      def page_label
        "Page #{page} of #{pages}"
      end

      def previous_page_path
        page_path(page - 1) if page > 1
      end

      def next_page_path
        page_path(page + 1) if page < pages
      end

      def number(value)
        ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
      end

      def zoned(time)
        time&.in_time_zone(AhoyDashboard.time_zone)
      end

      def place(*parts)
        IndexPresenter.place(*parts)
      end

      def short_token(token)
        IndexPresenter.short_token(token)
      end

      def visitor_path(token)
        routes.visitor_path(token, Destination.carried(query))
      end

      def user_path(user_id)
        routes.visitors_user_path(user_id, Destination.carried(query))
      end

      def user_label(user_id)
        labels.fetch(user_id.to_s) { "User #{user_id}" }
      end

      private

      attr_reader :routes

      def identified_page
        result.identified_page || 1
      end

      def moment(time)
        zoned(time)&.strftime(MOMENT)
      end

      def labels
        @labels ||= begin
          ids = result.user_ids + [ person.user_id ] + result.visits.map { |visit| visit.read(UserId::COLUMN) }
          UserId.labels(ids.compact)
        end
      end

      def page_path(number, anchor: nil)
        params = Destination.carried(query)
        params = params.merge(page: number) if number > 1
        params = params.merge(anchor: anchor) if anchor

        own_path(params)
      end

      def own_path(params)
        user? ? routes.visitors_user_path(person.key, params) : routes.visitor_path(person.key, params)
      end
    end
  end
end
