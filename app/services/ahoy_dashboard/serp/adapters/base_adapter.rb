module AhoyDashboard
  module Serp
    module Adapters
      class BaseAdapter
        Request = Data.define(:page, :start, :depth)

        Idea = Data.define(:query, :volume, :difficulty, :cpc, :competition, :intent, :trend) do
          def initialize(query:, volume: nil, difficulty: nil, cpc: nil, competition: nil,
                         intent: nil, trend: [])
            super(query: query.to_s.strip.downcase, volume: volume&.to_i, difficulty: difficulty&.to_i,
                  cpc: cpc&.to_f, competition: competition&.to_f, intent: intent.presence,
                  trend: Array(trend).map(&:to_i).freeze)
          end
        end

        Referrer = Data.define(:domain, :authority, :links, :follow, :kind, :top_page, :first_seen_on) do
          def initialize(domain:, authority: nil, links: 0, follow: true, kind: nil,
                         top_page: nil, first_seen_on: nil)
            super(domain: Serp::Domain.host(domain), authority: authority&.to_i, links: links.to_i,
                  follow: !!follow, kind: kind.presence, top_page: top_page.presence,
                  first_seen_on: first_seen_on)
          end
        end

        Anchor = Data.define(:text, :links, :domains)

        OPEN_TIMEOUT = 5
        READ_TIMEOUT = 30

        class << self
          def adapter_name
            name.demodulize.delete_suffix("Adapter").underscore
          end

          def label
            adapter_name
          end

          def requests_for(pages: 1)
            count = pages.to_i.clamp(1, Serp::MAX_PAGES)

            Array.new(count) do |index|
              Request.new(page: index + 1, start: index * Serp::RESULTS_PER_PAGE, depth: Serp::RESULTS_PER_PAGE)
            end
          end

          def cost_units(pages: 1)
            requests_for(pages: pages).size
          end

          def keyword_cost_units
            1
          end

          def backlink_cost_units
            1
          end

          def keywords?
            false
          end

          def backlinks?
            false
          end

          def credential_keys
            [].freeze
          end

          def countries
            nil
          end

          def configured?
            credential_keys.any? && credential_keys.all? { |key| Serp.credential(adapter_name.to_sym, key).present? }
          end

          def trim(payload)
            return {} if payload.blank?

            payload.slice(*self::KEPT_KEYS)
          end
        end

        KEPT_KEYS = %w[
          organic_results ai_overview answer_box knowledge_graph related_questions
          related_searches search_metadata search_parameters results overview search_id
          local_results top_stories inline_videos inline_images discussions_and_forums
        ].freeze

        def search(query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                   language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          require_credentials!

          request ||= first_request
          place = Location.parse(location)
          payload = fetch_payload(query: query, place: place, request: request, device: device,
                                  language: language, engine: engine)

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
            provider_search_id: search_id(payload),
            cost_units: self.class.cost_units(pages: 1),
            raw: payload
          )
        end

        def provider_name
          self.class.adapter_name.to_sym
        end

        def units_used
          @units_used.to_i
        end

        def keywords(seed:, location: nil, language: Serp::DEFAULT_LANGUAGE, limit: 100)
          raise Error, "#{provider_name} does not sell keyword data"
        end

        def backlinks(domain:, limit: 100)
          raise Error, "#{provider_name} does not sell backlink data"
        end

        private

        def require_credentials!
        end

        def fetch_payload(query:, place:, request:, device:, language:, engine:)
          raise NotImplementedError
        end

        def entries(_payload)
          raise NotImplementedError
        end

        def ai_overview(_payload)
          raise NotImplementedError
        end

        def search_id(_payload)
          raise NotImplementedError
        end

        def first_request
          self.class.requests_for(pages: 1).first
        end

        def http
          @http ||= HttpClient.new(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        end

        def get_json(url, params: {}, headers: {})
          send_request { http.get(url, params: params, headers: headers) }
        end

        def post_json(url, body:, headers: {}, basic_auth: nil)
          send_request { http.post_json(url, body: body, headers: headers, basic_auth: basic_auth) }
        end

        def send_request
          reply = yield
          raise error_for(reply.response, reply.payload) unless acceptable?(reply.response, reply.payload)

          @units_used = units_used + 1
          reply.payload
        rescue HttpClient::Unreachable => e
          raise Error, "#{provider_name} request failed: #{e.message}"
        end

        def acceptable?(response, _payload)
          response.is_a?(Net::HTTPSuccess)
        end

        def error_for(response, _payload)
          Error.new("#{provider_name} returned #{response.code}")
        end

        def organic_from(entries, request:)
          entries.each_with_index.map do |entry, index|
            position = Positions.absolute(reported: entry[:position], index: index, start: request.start)

            Organic.new(position: position, page: request.page, link: entry[:link],
                        title: entry[:title], snippet: entry[:snippet])
          end
        end
      end
    end
  end
end
