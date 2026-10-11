module AhoyDashboard
  module Serp
    module Adapters
      class DataForSeoAdapter < BaseAdapter
        ENDPOINT = "https://api.dataforseo.com/v3/serp/google/organic/live/advanced".freeze

        OK = 20_000
        AUTH_CODES = (40_100..40_199).freeze
        QUOTA_CODES = [ 40_200, 40_202, 40_203, 40_402 ].freeze

        MAX_DEPTH = 200
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

          def configured?
            credential_keys.all? { |key| Serp.credential(:dataforseo, key).present? }
          end

          # One request takes the whole depth, so five pages is one call rather
          # than five. The cap counts requests, which is what a page of results
          # costs everywhere, so a deep read here is cheaper than the same read
          # through a provider that pages.
          def paginates?
            false
          end

          def keyword_cost_units
            2
          end

          def backlink_cost_units
            2
          end

          def requests_for(pages: 1)
            depth = pages.to_i.clamp(1, Serp::MAX_PAGES) * Serp::RESULTS_PER_PAGE

            [ BaseAdapter::Request.new(page: 1, start: 0, depth: depth.clamp(1, MAX_DEPTH)) ]
          end

          # Nothing this one returns is at the top level. The inherited trim
          # slices keys like organic_results off the root, and this payload's
          # root is version, status_code, tasks, so that slice matched nothing
          # and every reading stored an empty response while raw_bytes went on
          # recording the real size. Everything worth keeping is one array of
          # typed items three levels down, and the parser reads it from exactly
          # that path, so the path is what gets kept.
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

        # The one provider in this list that sells all three. Positions come off
        # the serp endpoint above, and these two are separate products on the
        # same account, which is the whole reason they are worth having here:
        # another method rather than another vendor, another bill and another set
        # of credentials.
        KEYWORD_ENDPOINT = "https://api.dataforseo.com/v3/dataforseo_labs/google/keyword_ideas/live".freeze
        DIFFICULTY_ENDPOINT = "https://api.dataforseo.com/v3/dataforseo_labs/google/bulk_keyword_difficulty/live".freeze
        BACKLINK_ENDPOINT = "https://api.dataforseo.com/v3/backlinks/referring_domains/live".freeze
        ANCHOR_ENDPOINT = "https://api.dataforseo.com/v3/backlinks/anchors/live".freeze

        def keywords?(*forwarded_arguments, **forwarded_keywords, &forwarded_block)
          true
        end

        def backlinks?(*forwarded_arguments, **forwarded_keywords, &forwarded_block)
          true
        end

        def keywords(seed:, location: nil, language: Serp::DEFAULT_LANGUAGE, limit: 100)
          require_login!
          place = Location.parse(location)
          payload = post_json(KEYWORD_ENDPOINT, basic_auth: [ login, password ], body: [ {
            keywords: [ seed.to_s ],
            location_name: location_name(place),
            language_code: language,
            limit: limit.to_i.clamp(1, 1_000),
            order_by: [ "keyword_info.search_volume,desc" ]
          } ])

          ideas = Array(payload.dig("tasks", 0, "result", 0, "items")).map do |item|
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
          require_login!
          domains, total = referring_domains(domain, limit)

          { domains: domains, anchors: anchors(domain, limit), total: total }
        end

        def initialize(login: nil, password: nil)
          super()
          @login = login.presence || Serp.credential(:dataforseo, :login)
          @password = password.presence || Serp.credential(:dataforseo, :password)
        end

        def search(query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                   language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          require_login!

          request ||= first_request
          place = Location.parse(location)
          body = [ task(query, place, request, device, language) ]
          payload = post_json(ENDPOINT, body: body, basic_auth: [ login, password ])

          parse_payload(payload, query: query, location: place, request: request, device: device,
                                 language: language, engine: engine)
        end

        def parse_payload(payload, query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                          language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          request ||= first_request
          items = items_in(payload)

          Result.new(
            provider: provider_name, engine: engine, query: query, location: Location.parse(location),
            device: device, language: language, page: request.page, start: request.start,
            organic: organic_from(entries(items), request: request),
            ai_overview: ai_overview(items),
            provider_search_id: payload.dig("tasks", 0, "id"),
            cost_units: 1,
            raw: payload
          )
        end

        private

        attr_reader :login, :password

        def require_login!
          raise AuthError, "no dataforseo login is configured" if login.blank? || password.blank?
        end

        # The ideas endpoint does not always carry a difficulty, and the bulk one
        # answers a hundred at a time for a fraction of a request. Asked for in
        # one go rather than per keyword, and a failure here leaves the volumes
        # intact rather than losing the whole lookup over a column.
        def difficulty_for(ideas, place, language)
          missing = ideas.reject(&:difficulty).first(1_000).map(&:query)
          return ideas if missing.empty?

          payload = post_json(DIFFICULTY_ENDPOINT, basic_auth: [ login, password ], body: [ {
            keywords: missing, location_name: location_name(place), language_code: language
          } ])

          scores = Array(payload.dig("tasks", 0, "result", 0, "items")).map { |item|
            [ item["keyword"], item["keyword_difficulty"] ]
          }.to_h

          ideas.map { |idea| idea.difficulty ? idea : idea.with(difficulty: scores[idea.query]&.to_i) }
        rescue Error
          ideas
        end

        def referring_domains(domain, limit)
          payload = post_json(BACKLINK_ENDPOINT, basic_auth: [ login, password ], body: [ {
            target: domain, limit: limit.to_i.clamp(1, 1_000), order_by: [ "rank,desc" ],
            backlinks_status_type: "live"
          } ])

          referrers = Array(payload.dig("tasks", 0, "result", 0, "items")).map do |item|
            host = item["domain"]
            next if host.blank?

            BaseAdapter::Referrer.new(
              domain: host, authority: item["rank"], links: item["backlinks"],
              follow: item["backlinks"].to_i > item["nofollow_backlinks"].to_i,
              kind: item["is_broken"] ? "broken" : nil,
              first_seen_on: parse_date(item["first_seen"])
            )
          end.select { |value| value }

          [ referrers, payload.dig("tasks", 0, "result", 0, "total_count")&.to_i ]
        end

        def anchors(domain, limit)
          payload = post_json(ANCHOR_ENDPOINT, basic_auth: [ login, password ], body: [ {
            target: domain, limit: limit.to_i.clamp(1, 1_000), order_by: [ "backlinks,desc" ]
          } ])

          Array(payload.dig("tasks", 0, "result", 0, "items")).map do |item|
            text = item["anchor"]
            next if text.blank?

            BaseAdapter::Anchor.new(text: text, links: item["backlinks"].to_i,
                                    domains: item["referring_domains"].to_i)
          end.select { |value| value }
        rescue Error
          nil
        end

        def parse_date(value)
          value.present? ? Date.parse(value.to_s) : nil
        rescue Date::Error
          nil
        end

        def task(query, place, request, device, language)
          {
            keyword: query,
            location_name: location_name(place),
            language_code: language,
            device: device,
            depth: request.depth
          }
        end

        # A city is written the same way here as everywhere else. A country is
        # not: this one wants the name rather than the code, and a code nobody
        # mapped is refused rather than quietly searched from the wrong country.
        def location_name(place)
          return place.canonical_name if place.city?

          COUNTRIES.fetch(place.country_code) do
            raise Error, "dataforseo needs a location name for #{place.country_code.inspect}, " \
                         "and nothing here maps it"
          end
        end

        def items_in(payload)
          Array(payload.dig("tasks", 0, "result", 0, "items"))
        end

        def entries(items)
          items.select { |item| item["type"] == ORGANIC }.map do |item|
            {
              position: item["rank_absolute"] || item["rank_group"],
              link: item["url"],
              title: item["title"],
              snippet: item["description"]
            }
          end
        end

        def ai_overview(items)
          overview = items.find { |item| item["type"] == AI_OVERVIEW }
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
