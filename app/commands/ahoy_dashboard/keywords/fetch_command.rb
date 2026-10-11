module AhoyDashboard
  module Keywords
    class FetchCommand < AhoyDashboard::Command
      Outcome = Data.define(:seed, :location, :language, :written, :units)

      def initialize(seed:, location: nil, language: nil, limit: 100, refresh: false, now: Time.current)
        @seed = seed.to_s.strip.downcase
        @location = location.presence || Keywords.location
        @language = language.to_s.strip.downcase.presence || Keywords.language
        @limit = limit
        @refresh = refresh
        @now = now
      end

      def call
        return broadcast(:invalid, "no seed given") if seed.blank?
        return broadcast(:disabled) unless Keywords.enabled?

        @adapter = Keywords.adapter
        return broadcast(:unsupported, adapter.provider_name) unless adapter.keywords?
        return broadcast(:refused, Keywords.refusal_message(:unconfigured)) unless Keywords.configured?
        return broadcast(:saved, saved.maximum(:fetched_at)) if !refresh && saved.exists?
        return broadcast(:capped, record) unless spend.reserve

        ideas = adapter.keywords(seed: seed, location: location, language: language, limit: limit)
        written = store(rows(ideas))
        spend.settle(adapter.units_used, used: true)

        broadcast(:ok, Outcome.new(seed: seed, location: location, language: language, written: written, units: adapter.units_used))
      rescue Serp::AuthError, Serp::QuotaError => e
        broken(e)
        broadcast(:rate_limited, e.message)
      rescue Serp::Error => e
        broken(e)
        broadcast(:failed, e.message)
      ensure
        @spend&.settle(adapter&.units_used)
      end

      private

      attr_reader :seed, :location, :language, :limit, :refresh, :now, :adapter

      def record
        @record ||= Keywords.record
      end

      def spend
        @spend ||= Serp::Spend.new(provider: record, units: adapter.class.keyword_cost_units,
                                   kind: :keywords, name: adapter.class.adapter_name, now: now)
      end

      def saved
        AhoyDashboard::KeywordIdea.saved(seed, location: location, language: language)
      end

      def broken(error)
        @spend&.settle(adapter&.units_used)
        record&.record_error!(error.message)
      end

      def store(rows)
        AhoyDashboard::KeywordIdea.transaction do
          saved.where.not(query: rows.pluck(:query)).delete_all if rows.any?
          AhoyDashboard::KeywordIdea.absorb(rows)
        end
      end

      def rows(ideas)
        ideas.uniq(&:query).map do |idea|
          {
            seed: seed, query: idea.query, location: location, language: language,
            volume: idea.volume, difficulty: idea.difficulty, cpc: idea.cpc,
            competition: idea.competition, intent: idea.intent, trend: idea.trend,
            provider: adapter.provider_name.to_s, fetched_at: now,
            created_at: now, updated_at: now
          }
        end
      end
    end
  end
end
