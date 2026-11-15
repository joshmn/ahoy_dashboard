module AhoyDashboard
  module Visitors
    class Destination
      TOGGLES = %i[crawlers internal].freeze

      def self.carried(query)
        query.to_query.slice(*TOGGLES)
      end

      def self.anchor(visit_id)
        "visit-#{visit_id}"
      end

      def initialize(found:, query:, routes:)
        @found = found
        @query = query
        @routes = routes
      end

      def path
        return routes.visitors_user_path(found.key, self.class.carried(query)) if found.user?
        return routes.visitor_path(found.key, self.class.carried(query)) unless found.visit?

        visit_path
      end

      private

      attr_reader :found, :query, :routes

      def visit_path
        visit = found.visit
        person = visit_person(visit)
        return nil if person.nil?

        params = self.class.carried(query)
        page = page_of(person, visit, params)
        if page.nil?
          params = params.merge(crawlers: QueryForm::CRAWLERS_ON, internal: QueryForm::INTERNAL_ON)
          page = page_of(person, visit, params)
        end
        params = params.merge(page: page) if page && page > 1
        anchor = self.class.anchor(visit.id)

        if person.user?
          routes.visitors_user_path(person.key, params.merge(anchor: anchor))
        else
          routes.visitor_path(person.key, params.merge(anchor: anchor))
        end
      end

      def visit_person(visit)
        if visit.visitor_token.present?
          PersonQuery.call(visitor_token: visit.visitor_token)
        elsif visit.has_attribute?(UserId::COLUMN) && visit[UserId::COLUMN].present?
          PersonQuery.call(user_id: visit[UserId::COLUMN])
        end
      end

      def page_of(person, visit, params)
        JourneyQuery.new(
          person: person,
          include_crawlers: params[:crawlers] == QueryForm::CRAWLERS_ON,
          include_internal: params[:internal] == QueryForm::INTERNAL_ON
        ).page_of(visit)
      end
    end
  end
end
