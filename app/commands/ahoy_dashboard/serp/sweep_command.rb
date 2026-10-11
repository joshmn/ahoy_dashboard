module AhoyDashboard
  module Serp
    # Every tracked search checked now rather than when its cadence comes round.
    # The scheduled job asks who is due; this one does not ask, because the whole
    # reason for pressing it is wanting a reading that will not wait. It does not
    # move anybody's schedule either: last_checked_at is written by the check, so
    # the next one lands a cadence after this rather than after the one before.
    class SweepCommand < AhoyDashboard::Command
      OFF = "Rank tracking is switched off.".freeze
      NOTHING = "Nothing is being tracked yet.".freeze
      CAPPED = "The monthly ceiling is spent, so nothing was sent.".freeze
      PAUSED = "This keyword is paused. Turn it back on to check it.".freeze
      NO_SITES = "This keyword has no site to look for. Pick one first.".freeze
      QUEUED = "This keyword was just sent for checking. Give it a minute, then reload.".freeze
      QUEUED_ALL = "Every keyword was just sent for checking. Give it a minute, then reload.".freeze

      QUEUED_FOR = 2.minutes
      QUEUED_KEY = "ahoy_dashboard/serp/queued".freeze

      def self.queued?(keyword)
        Rails.cache.exist?(queued_key(keyword))
      end

      def self.queued_key(keyword)
        "#{QUEUED_KEY}/#{keyword.id}"
      end

      def initialize(keyword: nil, now: Time.current)
        @keyword = keyword
        @now = now
      end

      def call
        blocker = refusal
        return broadcast(:refused, message_for(blocker)) if blocker

        broadcast(:ok, enqueue(keywords))
      end

      def refusal
        return :off unless Serp.enabled?
        return :credentials unless adapter_class.configured?
        return single_refusal if keyword
        return (SerpKeyword.trackable.exists? ? :queued : :nothing) if keywords.empty?

        :capped unless room?
      end

      def adapter_label
        adapter_class.label
      end

      def searches
        keywords.sum { |each| each.locations.size }
      end

      def units
        keywords.sum { |each| each.cost_units(adapter_class) }
      end

      private

      attr_reader :keyword, :now

      def keywords
        @keywords ||= keyword ? [ keyword ] : SerpKeyword.trackable.reject { |each| self.class.queued?(each) }
      end

      def single_refusal
        return :paused unless keyword.enabled?
        return :no_sites unless keyword.keyword_targets.merge(SerpKeywordTarget.tracked).exists?
        return :queued if self.class.queued?(keyword)

        :capped unless room?
      end

      def message_for(blocker)
        return no_credentials if blocker == :credentials

        {
          off: OFF, nothing: NOTHING, capped: CAPPED, paused: PAUSED,
          no_sites: NO_SITES, queued: keyword ? QUEUED : QUEUED_ALL
        }.fetch(blocker)
      end

      def provider
        @provider ||= SerpProvider.current
      end

      def adapter_class
        @adapter_class ||= provider&.adapter_class || Serp.adapter_class
      end

      def no_credentials
        "#{adapter_class.label} has no credentials set."
      end

      # One unit, not the whole sweep. A ceiling with room for half of it should
      # spend that half rather than refuse the lot, and each check re-reads the
      # ceiling for itself before it sends anything.
      def room?
        provider.nil? || provider.room_for?(1, now: now)
      end

      def enqueue(keywords)
        keywords.sum do |each|
          each.locations.each { |location| Keywords::CheckJob.perform_later(each.id, location) }
          Rails.cache.write(self.class.queued_key(each), now.to_i, expires_in: QUEUED_FOR)

          each.locations.size
        end
      end
    end
  end
end
