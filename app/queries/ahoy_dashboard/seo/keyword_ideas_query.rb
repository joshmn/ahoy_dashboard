module AhoyDashboard
  module Seo
    # One seed's cached ideas, with our own position joined on where we have one.
    #
    # That last column is the point. A bought list of searches is a list of
    # searches; the same list with "we are eleventh on this one and nowhere on
    # that one" beside it is a plan.
    class KeywordIdeasQuery
      Row = Data.define(:idea, :query, :volume, :difficulty, :cpc, :intent, :cluster,
                        :position, :impressions) do
        def tracked?
          position.present?
        end

        def seen?
          impressions.to_i.positive?
        end

        def band
          idea.band
        end

        def worth
          idea.worth
        end

        # Nowhere in the results and never even shown for it. The genuinely new
        # ones, as against the ones we are already in the running for.
        def untouched?
          !tracked? && !seen?
        end
      end

      Cluster = Data.define(:name, :terms, :volume)

      Result = Data.define(:seed, :location, :language, :lookups, :rows, :fetched_at, :provider) do
        def any?
          rows.any?
        end

        def sample?
          rows.any? { |row| row.idea.provider == "fake" }
        end

        def volume
          rows.sum { |row| row.volume.to_i }
        end

        def untracked
          rows.reject(&:tracked?)
        end

        def untouched
          rows.select(&:untouched?)
        end

        def easy_wins
          untracked.select { |row| row.difficulty.to_i.positive? && row.difficulty < KeywordIdea::EASY && row.volume.to_i >= 100 }
            .sort_by { |row| -row.worth }
        end

        def clusters
          rows.group_by(&:cluster).map { |name, group|
            Cluster.new(name: name, terms: group.size, volume: group.sum { |row| row.volume.to_i })
          }.sort_by { |cluster| -cluster.volume }
        end

        def questions
          rows.select { |row| row.query.match?(/\A(how|what|why|when|where|who|can|do|does|is|are|will)\b/) }
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(seed: nil, location: nil, language: nil)
        @lookups = AhoyDashboard::KeywordIdea.lookups
        picked = pick(seed.to_s.strip.downcase.presence, location.to_s.strip.presence,
                      language.to_s.strip.downcase.presence)
        @seed = picked.seed
        @location = picked.location
        @language = picked.language
      end

      def call
        ideas = seed ? AhoyDashboard::KeywordIdea.saved(seed, location: location, language: language).ordered.to_a : []
        return empty if ideas.empty?

        Result.new(seed: seed, location: location, language: language, lookups: lookups, rows: rows(ideas),
                   fetched_at: ideas.map(&:fetched_at).max, provider: ideas.first.provider)
      end

      private

      attr_reader :seed, :location, :language, :lookups

      def empty
        Result.new(seed: seed, location: location, language: language, lookups: lookups, rows: [],
                   fetched_at: nil, provider: nil)
      end

      def pick(seed, location, language)
        fallback = AhoyDashboard::KeywordIdea::Lookup.new(seed: seed, location: location || Keywords.location,
                                                          language: language || Keywords.language)
        return lookups.first || fallback if seed.nil?
        return fallback if location && language

        candidates = lookups.select do |lookup|
          lookup.seed == seed && [ nil, lookup.location ].include?(location) && [ nil, lookup.language ].include?(language)
        end

        candidates.find { |lookup| lookup == fallback } || candidates.first || fallback
      end

      def rows(ideas)
        ranks = positions(ideas.map(&:query))
        seen = impressions(ideas.map(&:query))

        ideas.map do |idea|
          Row.new(idea: idea, query: idea.query, volume: idea.volume, difficulty: idea.difficulty,
                  cpc: idea.cpc, intent: idea.intent, cluster: cluster_of(idea.query),
                  position: ranks[idea.query], impressions: seen[idea.query])
        end
      end

      # Where we come for it, if it is being tracked at all. Our own site only:
      # a rival's position is the gap report's question, not this one's.
      def positions(queries)
        return {} unless AhoyDashboard::Serp.installed?

        site = AhoyDashboard::SerpSite.ours
        return {} if site.nil?

        AhoyDashboard::SerpCheck
          .joins(:keyword)
          .where(site_id: site.id, status: AhoyDashboard::SerpCheck.statuses[:success])
          .where(ahoy_dashboard_serp_keywords: { query: queries })
          .select("distinct on (ahoy_dashboard_serp_keywords.query) ahoy_dashboard_serp_keywords.query as term, position")
          .order(Arel.sql("ahoy_dashboard_serp_keywords.query, checked_at desc"))
          .map { |row| [ row.term, row.position ] }.to_h
      end

      # Whether Google has ever put us in front of anybody for it, which is a
      # softer signal than a position and covers far more of the list.
      def impressions(queries)
        return {} unless AhoyDashboard::SearchConsole.installed?

        AhoyDashboard::SearchConsoleKeyword.where(query: queries).group(:query).sum(:impressions)
      end

      # The seed word taken out, and what is left is the topic. Crude, and better
      # than nothing: the alternative is a bought clustering call per seed, which
      # is a second bill for a heading.
      def cluster_of(query)
        rest = query.sub(seed.to_s, "").squish

        rest.blank? ? "The seed itself" : rest.split.first(2).join(" ").upcase_first
      end
    end
  end
end
