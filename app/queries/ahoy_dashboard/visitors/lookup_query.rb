module AhoyDashboard
  module Visitors
    class LookupQuery < AhoyDashboard::Query
      MAX_LENGTH = 255
      VISIT_TOKEN = "visit_token".freeze

      Found = Data.define(:kind, :key, :visit) do
        def visit?
          kind == :visit
        end

        def user?
          kind == :user
        end
      end

      def initialize(value)
        @value = value.to_s.strip
      end

      def call
        return nil if value.empty? || value.length > MAX_LENGTH

        by_visit || by_visitor || by_user
      end

      private

      attr_reader :value

      def by_visit
        return nil unless AhoyDashboard.visit.column_names.include?(VISIT_TOKEN)

        visit = AhoyDashboard.visit.find_by(VISIT_TOKEN => value)
        Found.new(kind: :visit, key: value, visit: visit) if visit
      end

      def by_visitor
        Found.new(kind: :visitor, key: value, visit: nil) if AhoyDashboard.visit.where(visitor_token: value).exists?
      end

      def by_user
        person = PersonQuery.call(user_id: value)
        Found.new(kind: :user, key: person.key, visit: nil) if person
      end
    end
  end
end
