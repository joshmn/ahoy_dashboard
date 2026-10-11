require "net/http"

module AhoyDashboard
  module Serp
    module Adapters
      class BaseAdapter
        Request = Data.define(:page, :start, :depth)

        # What a keyword endpoint answers with, whoever sells it.
        Idea = Data.define(:query, :volume, :difficulty, :cpc, :competition, :intent, :trend) do
          def initialize(query:, volume: nil, difficulty: nil, cpc: nil, competition: nil,
                         intent: nil, trend: [])
            super(query: query.to_s.strip.downcase, volume: volume&.to_i, difficulty: difficulty&.to_i,
                  cpc: cpc&.to_f, competition: competition&.to_f, intent: intent.presence,
                  trend: Array(trend).map(&:to_i).freeze)
          end
        end

        # And a backlink endpoint. One row per referring domain, not per link: a
        # site linking four hundred times out of a footer is one relationship.
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
        RETRYABLE = [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
                      SocketError ].freeze

        class << self
          def adapter_name
            name.demodulize.delete_suffix("Adapter").underscore
          end

          def label
            adapter_name
          end

          def results_per_request
            Serp::RESULTS_PER_PAGE
          end

          def max_pages
            Serp::MAX_PAGES
          end

          def requests_for(pages: 1)
            count = pages.to_i.clamp(1, max_pages)

            Array.new(count) do |index|
              Request.new(page: index + 1, start: index * results_per_request, depth: results_per_request)
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

          def credential_keys
            [].freeze
          end

          def countries
            nil
          end

          def configured?
            false
          end

          def trim(payload)
            return {} if payload.blank?

            payload.slice(*self::KEPT_KEYS)
          end
        end

        # What is worth keeping out of a response once the positions have been
        # read off it. The whole payload is tens of kilobytes of things nobody
        # asked for; these are the parts that answer a question later.
        #
        # Every key here has to leave the payload re-parseable, because
        # SerpRunPage#result hands what was stored back to parse_payload. A trim
        # that drops the path the parser reads turns a stored reading into a
        # blank one.
        #
        # On the class rather than inside class << self, or a subclass cannot
        # override it and self::KEPT_KEYS resolves to nothing at all.
        KEPT_KEYS = %w[
          organic_results ai_overview answer_box knowledge_graph related_questions
          related_searches search_metadata search_parameters results overview search_id
          local_results top_stories inline_videos inline_images discussions_and_forums
        ].freeze

        def search(query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                   language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          raise NotImplementedError
        end

        def parse_payload(payload, query:, location: nil, request: nil, device: Serp::DEFAULT_DEVICE,
                          language: Serp::DEFAULT_LANGUAGE, engine: Serp::DEFAULT_ENGINE)
          raise NotImplementedError
        end

        def search_pages(query:, pages: 1, **options)
          results = self.class.requests_for(pages: pages).map do |request|
            search(query: query, request: request, **options)
          end

          Result.combine(results)
        end

        def provider_name
          self.class.adapter_name.to_sym
        end

        def units_used
          @units_used.to_i
        end

        # Bought data that is not a results page. Both are optional: an adapter
        # that only fetches positions says so and the screens that want these say
        # the provider does not sell them, rather than rendering an empty table
        # that reads as "nobody links to you".
        def keywords?(*forwarded_arguments, **forwarded_keywords, &forwarded_block)
          false
        end

        def backlinks?(*forwarded_arguments, **forwarded_keywords, &forwarded_block)
          false
        end

        def keywords(seed:, location: nil, language: Serp::DEFAULT_LANGUAGE, limit: 100)
          raise Error, "#{provider_name} does not sell keyword data"
        end

        def backlinks(domain:, limit: 100)
          raise Error, "#{provider_name} does not sell backlink data"
        end

        private

        def first_request
          self.class.requests_for(pages: 1).first
        end

        def get_json(url, params: {}, headers: {})
          uri = URI(url)
          uri.query = URI.encode_www_form(params.compact) if params.present?
          request = Net::HTTP::Get.new(uri)
          headers.each { |key, value| request[key] = value }

          send_request(uri, request)
        end

        def post_json(url, body:, headers: {}, basic_auth: nil)
          uri = URI(url)
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          headers.each { |key, value| request[key] = value }
          request.basic_auth(*basic_auth) if basic_auth
          request.body = body.to_json

          send_request(uri, request)
        end

        def send_request(uri, request)
          response = perform(uri, request)
          payload = parse(response)
          raise error_for(response, payload) unless acceptable?(response, payload)

          @units_used = units_used + 1
          payload
        end

        def perform(uri, request, attempts_left: 1)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                              open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            http.request(request)
          end
        rescue *RETRYABLE => e
          raise Error, "#{provider_name} request failed: #{e.class}: #{e.message}" if attempts_left.zero?

          perform(uri, request, attempts_left: attempts_left - 1)
        end

        def parse(response)
          body = response.body.to_s
          return {} if body.blank?

          JSON.parse(body)
        rescue JSON::ParserError
          {}
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
