module AhoyDashboard
  module Serp
    module Adapters
      class DataForSeoAdapter < BaseAdapter
        ENDPOINT = "https://api.dataforseo.com/v3/serp/google/organic/live/advanced".freeze

        OK = 20_000
        AUTH_CODES = (40_100..40_199).freeze
        QUOTA_CODES = [ 40_200, 40_202, 40_203, 40_402 ].freeze

        MAX_DEPTH = 200
        MAX_LIMIT = 1_000
        ORGANIC = "organic".freeze
        AI_OVERVIEW = "ai_overview".freeze

        COUNTRIES = {
          "us" => "United States", "gb" => "United Kingdom", "ca" => "Canada",
          "au" => "Australia", "ie" => "Ireland", "nz" => "New Zealand",
          "de" => "Germany", "fr" => "France", "es" => "Spain", "it" => "Italy",
          "nl" => "Netherlands", "se" => "Sweden", "no" => "Norway", "dk" => "Denmark",
          "fi" => "Finland", "pl" => "Poland", "pt" => "Portugal", "br" => "Brazil",
          "mx" => "Mexico", "ar" => "Argentina", "in" => "India", "jp" => "Japan",
          "kr" => "South Korea", "sg" => "Singapore", "za" => "South Africa",
          "ph" => "Philippines"
        }.freeze

        class << self
          def adapter_name
            "dataforseo"
          end

          def label
            "DataForSEO"
          end

          def credential_keys
            [ :login, :password ].freeze
          end

          def countries
            COUNTRIES
          end

          def keyword_cost_units
            2
          end

          def backlink_cost_units
            2
          end

          def keywords?
            true
          end

          def backlinks?
            true
          end

          def requests_for(pages: 1)
            depth = pages.to_i.clamp(1, Serp::MAX_PAGES) * Serp::RESULTS_PER_PAGE

            [ BaseAdapter::Request.new(page: 1, start: 0, depth: depth.clamp(1, MAX_DEPTH)) ]
          end

          def trim(payload)
            return {} if payload.blank?

            task = payload.dig("tasks", 0)
            items = Array(task&.dig("result", 0, "items"))
            return {} if items.empty?

            {
              "tasks" => [ {
                "id" => task["id"],
                "result" => [ {
                  "keyword" => task.dig("result", 0, "keyword"),
                  "items" => items
                } ]
              } ]
            }
          end
        end

        KEYWORD_ENDPOINT = "https://api.dataforseo.com/v3/dataforseo_labs/google/keyword_ideas/live".freeze
        DIFFICULTY_ENDPOINT = "https://api.dataforseo.com/v3/dataforseo_labs/google/bulk_keyword_difficulty/live".freeze
        BACKLINK_ENDPOINT = "https://api.dataforseo.com/v3/backlinks/referring_domains/live".freeze
        ANCHOR_ENDPOINT = "https://api.dataforseo.com/v3/backlinks/anchors/live".freeze

        def initialize(login: nil, password: nil)
          super()
          @login = login.presence || Serp.credential(:dataforseo, :login)
          @password = password.presence || Serp.credential(:dataforseo, :password)
        end

        def keywords(seed:, location: nil, language: Serp::DEFAULT_LANGUAGE, limit: 100)
          require_credentials!
          place = Location.parse(location)
          payload = post_task(KEYWORD_ENDPOINT, keywords: [ seed.to_s ], location_name: location_name(place),
                                                language_code: language, limit: capped(limit),
                                                order_by: [ "keyword_info.search_volume,desc" ])

          ideas = items_in(payload).map do |item|
            query = item["keyword"]
            next if query.blank?

            info = item["keyword_info"] || {}

            BaseAdapter::Idea.new(
              query: query, volume: info["search_volume"], cpc: info["cpc"],
              competition: info["competition"],
              difficulty: item.dig("keyword_properties", "keyword_difficulty"),
              intent: item.dig("search_intent_info", "main_intent"),
              trend: Array(info["monthly_searches"]).map { |month| month["search_volume"] }
            )
          end.select { |value| value }

          difficulty_for(ideas, place, language)
        end

        def backlinks(domain:, limit: 100)
          require_credentials!
          domains, total = referring_domains(domain, limit)

          { domains: domains, anchors: anchors(domain, limit), total: total }
        end

        private

        attr_reader :login, :password

        def require_credentials!
          raise AuthError, "no dataforseo login is configured" if login.blank? || password.blank?
        end

        def fetch_payload(query:, place:, request:, device:, language:, engine:)
          post_task(ENDPOINT, keyword: query, location_name: location_name(place), language_code: language,
                              device: device, depth: request.depth)
        end

        def post_task(endpoint, task)
          post_json(endpoint, basic_auth: [ login, password ], body: [ task ])
        end

        def difficulty_for(ideas, place, language)
          missing = ideas.reject(&:difficulty).first(1_000).map(&:query)
          return ideas if missing.empty?

          payload = post_task(DIFFICULTY_ENDPOINT, keywords: missing, location_name: location_name(place),
                                                   language_code: language)

          scores = items_in(payload).map { |item| [ item["keyword"], item["keyword_difficulty"] ] }.to_h

          ideas.map { |idea| idea.difficulty ? idea : idea.with(difficulty: scores[idea.query]&.to_i) }
        rescue Error
          ideas
        end

        def referring_domains(domain, limit)
          payload = post_task(BACKLINK_ENDPOINT, target: domain, limit: capped(limit), order_by: [ "rank,desc" ],
                                                 backlinks_status_type: "live")

          referrers = items_in(payload).map do |item|
            host = item["domain"]
            next if host.blank?

            BaseAdapter::Referrer.new(
              domain: host, authority: item["rank"], links: item["backlinks"],
              follow: item["backlinks"].to_i > item["nofollow_backlinks"].to_i,
              kind: item["is_broken"] ? "broken" : nil,
              first_seen_on: parse_date(item["first_seen"])
            )
          end.select { |value| value }

          [ referrers, result_in(payload)["total_count"]&.to_i ]
        end

        def anchors(domain, limit)
          payload = post_task(ANCHOR_ENDPOINT, target: domain, limit: capped(limit), order_by: [ "backlinks,desc" ])

          items_in(payload).map do |item|
            text = item["anchor"]
            next if text.blank?

            BaseAdapter::Anchor.new(text: text, links: item["backlinks"].to_i,
                                    domains: item["referring_domains"].to_i)
          end.select { |value| value }
        rescue Error
          nil
        end

        def capped(limit)
          limit.to_i.clamp(1, MAX_LIMIT)
        end

        def parse_date(value)
          value.present? ? Date.parse(value.to_s) : nil
        rescue ArgumentError
          nil
        end

        def location_name(place)
          return place.canonical_name if place.city?

          COUNTRIES.fetch(place.country_code) do
            raise Error, "dataforseo needs a location name for #{place.country_code.inspect}, " \
                         "and nothing here maps it"
          end
        end

        def result_in(payload)
          payload.dig("tasks", 0, "result", 0) || {}
        end

        def items_in(payload)
          Array(result_in(payload)["items"])
        end

        def search_id(payload)
          payload.dig("tasks", 0, "id")
        end

        def entries(payload)
          items_in(payload).select { |item| item["type"] == ORGANIC }.map do |item|
            {
              position: item["rank_absolute"] || item["rank_group"],
              link: item["url"],
              title: item["title"],
              snippet: item["description"]
            }
          end
        end

        def ai_overview(payload)
          overview = items_in(payload).find { |item| item["type"] == AI_OVERVIEW }
          return AiOverview.absent if overview.blank?

          sources = sources_from(overview)

          AiOverview.new(
            shown: true,
            text: text_from(overview),
            sources: sources,
            deferred: sources.empty? && overview["asynchronous_ai_overview"].present?
          )
        end

        def sources_from(overview)
          references = Array(overview["references"]).presence || nested_references(overview)

          references.each_with_index.map do |reference, index|
            link = reference["url"] || reference["link"]
            next if link.blank?

            Source.new(index: index + 1, link: link, domain: reference["domain"],
                       title: reference["title"] || reference["source"])
          end.select { |value| value }
        end

        def nested_references(overview)
          Array(overview["items"]).flat_map { |element| Array(element["references"]) }
        end

        def text_from(overview)
          Array(overview["items"]).map { |element| element["text"].presence }.select { |value| value }.join("\n\n").presence
        end

        def acceptable?(response, payload)
          super && payload["status_code"] == OK && task_code(payload) == OK
        end

        def error_for(response, payload)
          code = task_code(payload) || payload["status_code"] || response.code.to_i
          message = task_message(payload) || payload["status_message"] ||
            "dataforseo returned #{response.code}"

          return AuthError.new(message) if response.code.to_i == 401 || AUTH_CODES.cover?(code)
          return QuotaError.new(message) if QUOTA_CODES.include?(code) || response.code.to_i == 429

          Error.new(message)
        end

        def task_code(payload)
          payload.dig("tasks", 0, "status_code")
        end

        def task_message(payload)
          payload.dig("tasks", 0, "status_message")
        end
      end
    end
  end
end
