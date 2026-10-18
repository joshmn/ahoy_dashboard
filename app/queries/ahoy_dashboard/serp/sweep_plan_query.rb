module AhoyDashboard
  module Serp
    class SweepPlanQuery
      QUEUED_FOR = 2.minutes
      QUEUED_KEY = "ahoy_dashboard/serp/queued".freeze

      class << self
        def queued?(keyword)
          AhoyDashboard.cache.exist?(queued_key(keyword))
        end

        def queued_ids(keywords)
          return Set.new if keywords.empty?

          found = AhoyDashboard.cache.read_multi(*keywords.map { |each| queued_key(each) })
          keywords.select { |each| found.key?(queued_key(each)) }.map(&:id).to_set
        end

        def queued_key(keyword)
          "#{QUEUED_KEY}/#{keyword.id}"
        end
      end

      def initialize(keyword: nil, now: Time.current)
        @keyword = keyword
        @now = now
      end

      def refusal
        return @refusal if defined?(@refusal)

        @refusal = find_refusal
      end

      def keywords
        @keywords ||= keyword ? [ keyword ] : unqueued(SerpKeyword.trackable.to_a)
      end

      def searches
        keywords.sum { |each| each.locations.size }
      end

      def units
        keywords.sum { |each| each.cost_units(adapter_class) }
      end

      def adapter_class
        @adapter_class ||= provider&.adapter_class || Serp.adapter_class
      end

      def adapter_label
        adapter_class.label
      end

      private

      attr_reader :keyword, :now

      def find_refusal
        return :off unless Serp.enabled?
        return :credentials unless adapter_class.configured?
        return single_refusal if keyword
        return (SerpKeyword.trackable.exists? ? :queued : :nothing) if keywords.empty?

        :capped unless room?
      end

      def single_refusal
        return :paused unless keyword.enabled?
        return :no_sites unless keyword.keyword_targets.merge(SerpKeywordTarget.tracked).exists?
        return :queued if self.class.queued?(keyword)

        :capped unless room?
      end

      def unqueued(trackable)
        queued = self.class.queued_ids(trackable)
        trackable.reject { |each| queued.include?(each.id) }
      end

      def provider
        @provider ||= SerpProvider.current
      end

      def room?
        provider.nil? || provider.room_for?(1, now: now)
      end
    end
  end
end
