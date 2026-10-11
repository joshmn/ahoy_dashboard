module AhoyDashboard
  module AiVisibility
    module Clients
      class BaseClient
        OPEN_TIMEOUT = 5
        READ_TIMEOUT = 120
        RETRYABLE = [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
                      EOFError, SocketError, OpenSSL::SSL::SSLError ].freeze
        MESSAGE_LENGTH = 200

        def initialize(api_key:, model:)
          @api_key = api_key
          @model = model
        end

        def ask(_text)
          raise NotImplementedError
        end

        private

        attr_reader :api_key, :model

        def assistant_name
          raise(NotImplementedError)
        end

        def require_key!
          raise AuthError, "#{assistant_name} has no key" if api_key.blank?
        end

        def post_json(url, body:, headers: {})
          uri = URI(url)
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          headers.each { |key, value| request[key] = value }
          request.body = body.to_json

          response = perform(uri, request)
          payload = parse(response)
          return payload if response.is_a?(Net::HTTPSuccess)

          raise error_for(response, payload)
        end

        def perform(uri, request, attempts_left: 1)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                              open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            http.request(request)
          end
        rescue *RETRYABLE => e
          raise Error, "#{assistant_name} request failed: #{e.class}: #{e.message}" if attempts_left.zero?

          perform(uri, request, attempts_left: attempts_left - 1)
        end

        def parse(response)
          body = response.body.to_s
          return {} if body.blank?

          parsed = JSON.parse(body)
          parsed.is_a?(Hash) ? parsed : { "data" => parsed }
        rescue JSON::ParserError
          {}
        end

        def error_for(response, payload)
          detail = provider_message(payload)
          message = [ "#{assistant_name} returned #{response.code}", detail ].compact.join(": ")

          case response.code.to_i
          when 401, 403 then AuthError.new(message)
          when 429 then QuotaError.new(message)
          else Error.new(message)
          end
        end

        def failure(error)
          return Error.new("#{assistant_name} request failed: #{error.message}") if error.status.nil?

          message = [ "#{assistant_name} returned #{error.status}", error.detail.to_s.squish.truncate(MESSAGE_LENGTH).presence ]
                    .compact.join(": ")

          case error.status
          when 401, 403 then AuthError.new(message)
          when 429 then QuotaError.new(message)
          else Error.new(message)
          end
        end

        def provider_message(payload)
          error = payload["error"]
          text = error.is_a?(Hash) ? error["message"] : error
          text = payload["message"] if text.blank?

          text.to_s.squish.truncate(MESSAGE_LENGTH).presence
        end

        def source(url, title)
          ReplySource.new(url: url.to_s, title: title.to_s.squish.presence)
        end

        def unique(sources)
          sources.select { |entry| entry.url.present? }.uniq(&:url)
        end
      end
    end
  end
end
