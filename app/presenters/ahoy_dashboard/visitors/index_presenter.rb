module AhoyDashboard
  module Visitors
    class IndexPresenter
      TITLE = "Visitors".freeze
      IDENTIFIED = "identified".freeze
      TOKEN_LENGTH = 12

      class RowView
        delegate :visitor_token, :visits, :last_at, :first_at, :source, :entry, :user_id, to: :row

        def initialize(row:, presenter:)
          @row = row
          @presenter = presenter
        end

        def label
          return presenter.user_label(user_id) if user_id

          presenter.short_token(visitor_token)
        end

        def identified?
          user_id.present?
        end

        def path
          presenter.visitor_path(visitor_token)
        end

        def location
          presenter.place(row.city, row.country)
        end

        def last_seen
          AhoyDashboard::DateFormat.ago(last_at)
        end

        def last_seen_title
          last_at&.in_time_zone(AhoyDashboard.time_zone)&.strftime("%b %-d, %Y %-l:%M %p")
        end

        private

        attr_reader :row, :presenter
      end

      class << self
        def place(*parts)
          country = parts.pop
          named = AhoyDashboard::Countries.name(country.to_s) if country.present?

          (parts + [ named ]).map(&:presence).compact.join(", ").presence
        end

        def short_token(token)
          text = token.to_s
          text.length > TOKEN_LENGTH ? "#{text.first(TOKEN_LENGTH)}..." : text
        end
      end

      attr_reader :query, :result

      def initialize(query:, result:, identified:, routes:)
        @query = query
        @result = result
        @identified = identified
        @routes = routes
      end

      def title
        TITLE
      end

      def identified?
        @identified
      end

      def identifiable?
        UserId.visits?
      end

      def rows
        @rows ||= result.rows.map { |row| RowView.new(row: row, presenter: self) }
      end

      def empty?
        result.empty?
      end

      def summary
        noun = identified? ? "signed in visitor" : "visitor"
        "#{AhoyDashboard::Counted.call(result.total, noun: noun)} · #{query.range_label}"
      end

      def empty_title
        return "Nothing on this page" if result.page > 1
        return "Nobody signed in during this range" if identified?

        "Nobody visited in this range"
      end

      def empty_hint
        return nil if result.page > 1

        AhoyDashboard::RangeHint.call(query.filters)
      end

      def who_items
        [
          { label: "Everyone", url: routes.visitors_path(query.to_query), current: !identified? },
          { label: "Signed in", url: routes.visitors_path(query.to_query.merge(who: IDENTIFIED)), current: identified? }
        ]
      end

      def paged?
        result.paged?
      end

      def page_label
        "Page #{result.page} of #{[ result.pages, result.page ].max}"
      end

      def previous_page_path
        page_path(result.page - 1) if result.page > 1
      end

      def next_page_path
        page_path(result.page + 1) if result.page < result.pages
      end

      def lookup_path
        routes.visitors_lookup_path
      end

      def dashboard_path
        routes.root_path(query.to_query)
      end

      def visitor_path(token)
        routes.visitor_path(token, Destination.carried(query))
      end

      def user_label(user_id)
        labels.fetch(user_id.to_s) { "User #{user_id}" }
      end

      def place(*parts)
        self.class.place(*parts)
      end

      def short_token(token)
        self.class.short_token(token)
      end

      private

      attr_reader :routes

      def labels
        @labels ||= UserId.labels(result.rows.map(&:user_id))
      end

      def page_path(page)
        params = query.to_query.merge(page: page)
        params = params.merge(who: IDENTIFIED) if identified?

        routes.visitors_path(params)
      end
    end
  end
end
