module AhoyDashboard
  module Serp
    class SweepCommand < AhoyDashboard::Command
      OFF = "Rank tracking is switched off.".freeze
      NOTHING = "Nothing is being tracked yet.".freeze
      CAPPED = "The monthly ceiling is spent, so nothing was sent.".freeze
      PAUSED = "This keyword is paused. Turn it back on to check it.".freeze
      NO_SITES = "This keyword has no site to look for. Pick one first.".freeze
      QUEUED = "This keyword was just sent for checking. Give it a minute, then reload.".freeze
      QUEUED_ALL = "Every keyword was just sent for checking. Give it a minute, then reload.".freeze

      def initialize(keyword: nil, now: Time.current)
        @keyword = keyword
        @now = now
      end

      def call
        blocker = plan.refusal
        return broadcast(:refused, message_for(blocker)) if blocker

        broadcast(:ok, enqueue(plan.keywords))
      end

      private

      attr_reader :keyword, :now

      def plan
        @plan ||= SweepPlanQuery.new(keyword: keyword, now: now)
      end

      def message_for(blocker)
        return "#{plan.adapter_label} has no credentials set." if blocker == :credentials

        {
          off: OFF, nothing: NOTHING, capped: CAPPED, paused: PAUSED,
          no_sites: NO_SITES, queued: keyword ? QUEUED : QUEUED_ALL
        }.fetch(blocker)
      end

      def enqueue(keywords)
        keywords.sum do |each|
          each.locations.each { |location| Keywords::CheckJob.perform_later(each.id, location) }
          AhoyDashboard.cache.write(SweepPlanQuery.queued_key(each), now.to_i, expires_in: SweepPlanQuery::QUEUED_FOR)

          each.locations.size
        end
      end
    end
  end
end
