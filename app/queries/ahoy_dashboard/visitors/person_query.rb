module AhoyDashboard
  module Visitors
    class PersonQuery < AhoyDashboard::Query
      MAX_TOKENS = 500
      MAX_LENGTH = 255

      Person = Data.define(:kind, :key, :user_id, :visitor_tokens, :visit_ids) do
        def user?
          kind == :user
        end

        def visits
          relation = AhoyDashboard.visit.where(visitor_token: visitor_tokens)
          relation = relation.or(AhoyDashboard.visit.where(user_id: user_id)) if user?
          relation = relation.or(AhoyDashboard.visit.where(id: visit_ids)) if visit_ids.any?
          relation
        end
      end

      def initialize(visitor_token: nil, user_id: nil)
        @visitor_token = visitor_token.to_s.strip
        @user_id = user_id
      end

      def call
        person = user_id.nil? ? visitor : user
        person if person && person.visits.exists?
      end

      private

      attr_reader :visitor_token, :user_id

      def visitor
        return nil if visitor_token.empty? || visitor_token.length > MAX_LENGTH

        Person.new(kind: :visitor, key: visitor_token, user_id: nil, visitor_tokens: [ visitor_token ], visit_ids: [])
      end

      def user
        id = UserId.cast(user_id)
        return nil if id.nil?

        seeds = [ AhoyDashboard.visit.where(user_id: id) ]
        seeds << AhoyDashboard.visit.where(id: event_visits(id)) if UserId.events?

        tokens = seeds.flat_map { |seed| seed.where.not(visitor_token: nil).distinct.limit(MAX_TOKENS).pluck(:visitor_token) }
        untokened = seeds.flat_map { |seed| seed.where(visitor_token: nil).limit(MAX_TOKENS).pluck(:id) }

        Person.new(kind: :user, key: id.to_s, user_id: id, visitor_tokens: tokens.uniq.first(MAX_TOKENS),
                   visit_ids: untokened.uniq)
      end

      def event_visits(id)
        AhoyDashboard.event.where(user_id: id).where.not(visit_id: nil).select(:visit_id)
      end
    end
  end
end
