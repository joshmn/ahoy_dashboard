module AhoyDashboard
  module Serp
    module Adapters
      class FakeAdapter < BaseAdapter
        SAMPLE_DOMAINS = %w[
          wikipedia.org reddit.com github.com stackoverflow.com medium.com
          nytimes.com theverge.com wired.com quora.com arstechnica.com
          techcrunch.com dev.to
        ].freeze

        MISSING_EVERY = 4
        NO_OVERVIEW_EVERY = 3
        SOURCE_COUNT = 3
        DRIFT_SWAPS = 3
        NO_SNIPPET_EVERY = 2
        NO_PANEL_EVERY = 5

        class << self
          def configured?
            true
          end

          def label
            "fake"
          end

          def cost_units(pages: 1)
            0
          end

          def keyword_cost_units
            0
          end

          def backlink_cost_units
            0
          end
        end

        def initialize(**_options)
          super()
        end

        # So both of the bought screens can be worked on without an account. The
        # figures are derived from the phrase rather than drawn at random, so the
        # same seed answers the same way twice and a layout can be judged without
        # the numbers moving underneath it.
        def keywords?(*forwarded_arguments, **forwarded_keywords, &forwarded_block)
          true
        end

        def backlinks?(*forwarded_arguments, **forwarded_keywords, &forwarded_block)
          true
        end

        MODIFIERS = [
          nil, "cost", "rules", "how long", "requirements", "vs", "near me", "calculator",
          "list", "for beginners", "checklist", "explained", "reviews", "time", "process"
        ].freeze

        INTENTS = %w[informational commercial transactional navigational].freeze

        def keywords(seed:, location: nil, language: Serp::DEFAULT_LANGUAGE, limit: 100)
          base = seed.to_s.strip.downcase
          prng = Random.new(base.sum)

          MODIFIERS.first(limit.to_i.clamp(1, MODIFIERS.size)).map do |modifier|
            query = [ base, modifier ].compact.join(" ")
            volume = (12_000 / (1 + prng.rand(0..24))).round(-1)

            BaseAdapter::Idea.new(
              query: query, volume: volume, difficulty: prng.rand(12..72),
              cpc: (prng.rand(20..900) / 100.0).round(2),
              competition: (prng.rand(0..100) / 100.0).round(2),
              intent: INTENTS[prng.rand(INTENTS.size)],
              trend: Array.new(12) { prng.rand(40..100) }
            )
          end
        end

        FAKE_LINKERS = %w[
          reddit.com quora.com wikipedia.org github.com dev.to medium.com
          substack.com news.ycombinator.com theverge.com arstechnica.com
          lobste.rs
        ].freeze

        FAKE_ANCHORS = [
          "this guide", "here", "read more", "the calculator", "a good explainer"
        ].freeze

        def backlinks(domain:, limit: 100)
          prng = Random.new(domain.to_s.sum)

          domains = FAKE_LINKERS.first(limit.to_i.clamp(1, FAKE_LINKERS.size)).map do |host|
            BaseAdapter::Referrer.new(
              domain: host, authority: prng.rand(35..92), links: prng.rand(1..40),
              follow: prng.rand(100) < 65, kind: nil,
              first_seen_on: Date.current - prng.rand(10..600)
            )
          end

          anchors = ([ domain.to_s ] + FAKE_ANCHORS).map do |text|
            BaseAdapter::Anchor.new(text: text, links: prng.rand(10..400), domains: prng.rand(1..30))
          end

          { domains: domains, anchors: anchors, total: domains.size }
        end

        def search(query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                   language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          request ||= first_request
          place = Location.parse(location)
          payload = payload_for(query, place, request, device, language)

          parse_payload(payload, query: query, location: place, request: request, device: device,
                                 language: language, engine: engine)
        end

        def parse_payload(payload, query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                          language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          request ||= first_request

          Result.new(
            provider: provider_name, engine: engine, query: query, location: Location.parse(location),
            device: device, language: language, page: request.page, start: request.start,
            organic: organic_from(entries(payload), request: request),
            ai_overview: ai_overview(payload),
            provider_search_id: payload["search_id"],
            cost_units: 0,
            raw: payload
          )
        end

        private

        def payload_for(query, place, request, device, language)
          seed = seed_for(query, place, request, device, language)
          ordered = ranking(seed)

          {
            "fake" => true,
            "search_id" => "fake-#{seed.to_s(16).first(12)}",
            "results" => results_for(ordered, query, request),
            "overview" => overview_for(ordered, seed, request)
          }.merge(features_for(ordered, seed, query, request)).compact
        end

        def seed_for(query, place, request, device, language)
          key = [ query, place.to_s, request.page, device, language ].join("|")

          Digest::SHA256.hexdigest(key).to_i(16)
        end

        def ranking(seed)
          pool = SAMPLE_DOMAINS.rotate(seed % SAMPLE_DOMAINS.size)
          own = Serp.own_domain

          return drift(pool, seed) if own.blank? || (seed % MISSING_EVERY).zero?

          remaining = pool - [ own ]

          drift(remaining.insert(seed % remaining.size, own), seed)
        end

        def drift(ordered, seed)
          prng = Random.new(seed ^ Date.current.jd)

          ordered.dup.tap do |list|
            DRIFT_SWAPS.times do
              index = prng.rand(list.size - 1)
              list[index], list[index + 1] = list[index + 1], list[index]
            end
          end
        end

        def features_for(ordered, seed, query, request)
          return {} unless request.page == 1

          {
            "answer_box" => snippet_for(ordered, seed, query),
            "knowledge_graph" => panel_for(ordered, seed, query),
            "related_questions" => questions_for(ordered, query),
            "related_searches" => MODIFIERS.compact.rotate(seed % MODIFIERS.compact.size).first(6)
              .map { |modifier| { "query" => "#{query} #{modifier}" } }
          }.compact
        end

        def snippet_for(ordered, seed, query)
          return nil if (seed % NO_SNIPPET_EVERY).zero?

          holder = ordered[seed % 3]
          { "title" => "#{query.truncate(60)} at #{holder}", "link" => "https://#{holder}/#{query.parameterize}",
            "snippet" => "A fake answer for #{query.truncate(80)}." }
        end

        def panel_for(ordered, seed, query)
          return nil unless (seed % NO_PANEL_EVERY).zero?

          { "title" => query.titleize, "website" => "https://#{ordered.last}/" }
        end

        def questions_for(ordered, query)
          [ "What is #{query}?", "How does #{query} work?", "Is #{query} still going on?" ]
            .each_with_index.map do |question, index|
              holder = ordered[(index * 2) % ordered.size]
              { "question" => question, "link" => "https://#{holder}/#{query.parameterize}",
                "snippet" => "A fake answer to this question." }
            end
        end

        def results_for(ordered, query, request)
          Array.new(request.depth) do |index|
            domain = ordered[(request.start + index) % ordered.size]

            {
              "rank" => index + 1,
              "url" => "https://#{domain}/#{query.parameterize.presence || 'result'}",
              "heading" => "#{query.truncate(60)} at #{domain}",
              "summary" => "A fake result for #{query.truncate(80)}."
            }
          end
        end

        def overview_for(ordered, seed, request)
          return nil unless request.page == 1
          return nil if (seed % NO_OVERVIEW_EVERY).zero?

          {
            "body" => "A fake overview.",
            "cited" => ordered.first(SOURCE_COUNT).each_with_index.map do |domain, index|
              { "slot" => index + 1, "url" => "https://#{domain}/", "name" => domain }
            end
          }
        end

        def entries(payload)
          Array(payload["results"]).map do |entry|
            { position: entry["rank"], link: entry["url"], title: entry["heading"],
              snippet: entry["summary"] }
          end
        end

        def ai_overview(payload)
          overview = payload["overview"]
          return AiOverview.absent if overview.blank?

          sources = Array(overview["cited"]).map do |cited|
            Source.new(index: cited["slot"], link: cited["url"], title: cited["name"])
          end

          AiOverview.new(shown: true, text: overview["body"], sources: sources)
        end
      end
    end
  end
end
