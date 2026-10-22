require "openssl"
require "uri"

module AhoyDashboard
  module Assistant
    class ModelListService
      TTL = 10.minutes
      OPEN_TIMEOUT = 3
      READ_TIMEOUT = 5
      PAGE_SIZE = 1_000
      MAX_PAGES = 5
      CACHE_PREFIX = "ahoy_dashboard/assistant/models/v1".freeze
      ACTIVE = "active".freeze
      SCHEMES = %w[http https].freeze
      NOT_CHAT = /embed|tts|whisper|transcribe|dall-e|gpt-image|moderation|realtime|audio|search|computer-use|babbage|davinci|sora/i

      class Failed < StandardError; end

      class << self
        def call(name:, http: nil)
          new(name: name, http: http).call
        end
      end

      def initialize(name:, http: nil)
        @name = Assistant.reader_key(name)
        @reader = Assistant.reader_for(name)
        @record = AssistantProvider.for(name)
        @http = http || HttpClient.new(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      end

      def call
        return fallback unless listable?

        cached = AhoyDashboard.cache.read(cache_key)
        pairs = cached || fetched
        return fallback if pairs.empty?

        AhoyDashboard.cache.write(cache_key, pairs, expires_in: TTL) unless cached
        pairs.map { |id, label| ModelOption.new(id: id, label: label) }
      rescue HttpClient::Unreachable, Failed, SystemCallError => e
        Rails.logger.info("dashboard assistant model list fell back to the built in one: #{e.message}")
        fallback
      end

      private

      attr_reader :reader

      def fallback
        ModelOption.listed(reader.models)
      end

      def listable?
        uri = URI.parse(endpoint)

        SCHEMES.include?(uri.scheme) && uri.host.present? && (api_key.present? || reader.key_optional?)
      rescue URI::InvalidURIError
        false
      end

      def fetched
        reader.provider == :anthropic ? anthropic : listed
      end

      def anthropic
        pairs = []
        after = nil

        MAX_PAGES.times do
          page = models(params: { limit: PAGE_SIZE, after_id: after },
                        headers: { "x-api-key" => api_key, "anthropic-version" => LLM::Anthropic::Client::VERSION })
          pairs.concat(entries(page).select { |model| (model["lifecycle"] || ACTIVE) == ACTIVE }
            .map { |model| [ model["id"].to_s, model["display_name"].presence ] })
          after = page["last_id"].presence
          break unless page["has_more"] == true && after
        end

        pairs.reject { |id, _label| id.empty? }
      end

      def listed
        entries(models(headers: bearer)).each_with_index
          .reject { |model, _index| model["id"].blank? || model["id"].to_s.match?(NOT_CHAT) }
          .sort_by { |model, index| [ -model["created"].to_i, index ] }
          .map { |model, _index| [ model["id"].to_s, model["name"].presence ] }
      end

      def models(params: {}, headers: {})
        reply = @http.get("#{endpoint}/models", params: params, headers: headers)
        raise Failed, "#{reply.response.code} from #{URI.parse(endpoint).host}" unless reply.success?

        reply.payload
      end

      def entries(payload)
        Array(payload["data"]).select { |model| model.is_a?(Hash) }
      end

      def bearer
        api_key.present? ? { "Authorization" => "Bearer #{api_key}" } : {}
      end

      def endpoint
        @endpoint ||= (@record&.endpoint || reader.api_base).to_s.strip.chomp("/")
      end

      def api_key
        @api_key ||= @record&.api_key
      end

      def cache_key
        digest = OpenSSL::Digest::SHA256.hexdigest([ @name, endpoint, OpenSSL::Digest::SHA256.hexdigest(api_key.to_s) ].join("\n"))

        AnalyticsCache.key(key: [ CACHE_PREFIX, digest ], connection: AssistantProvider.connection)
      end
    end
  end
end
