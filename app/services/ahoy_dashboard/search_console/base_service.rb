require "net/http"

module AhoyDashboard
  module SearchConsole
    class BaseService
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 30

      # Google's OAuth endpoints answer with a bare error string; the API answers
      # with a nested object. Both shapes have to be read to tell an expired grant
      # from a used up quota.
      QUOTA_REASONS = %w[quotaExceeded rateLimitExceeded userRateLimitExceeded].freeze

      def self.call(**options)
        new(**options).call
      end

      private

      def get_json(url, token)
        uri = URI(url)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{token}"

        send_request(uri, request)
      end

      def post_json(url, token, body)
        uri = URI(url)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{token}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        send_request(uri, request)
      end

      def post_form(url, params)
        uri = URI(url)
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(params)

        send_request(uri, request)
      end

      def send_request(uri, request)
        response = perform(uri, request)
        payload = parse(response)
        return payload if response.is_a?(Net::HTTPSuccess)

        raise error_for(response, payload)
      end

      def perform(uri, request, attempts_left: 1)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                            open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(request)
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError => e
        raise Error, "search console request failed: #{e.class}: #{e.message}" if attempts_left.zero?

        perform(uri, request, attempts_left: attempts_left - 1)
      end

      def parse(response)
        body = response.body.to_s
        return {} if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError
        {}
      end

      def error_for(response, payload)
        code = response.code.to_i
        message = "search console returned #{code}: #{describe(payload)}"

        return QuotaError.new(message) if quota?(code, payload)
        return AuthError.new(message, code: oauth_error(payload)) if [ 400, 401 ].include?(code)
        return PermissionError.new(message) if code == 403

        Error.new(message)
      end

      def quota?(code, payload)
        return true if code == 429
        return false unless code == 403

        reasons(payload).any? { |reason| QUOTA_REASONS.include?(reason) }
      end

      def reasons(payload)
        api_error(payload).fetch("errors", []).map { |entry| entry["reason"] }.select { |value| value }
      end

      def oauth_error(payload)
        payload["error"] if payload["error"].is_a?(String)
      end

      def api_error(payload)
        payload["error"].is_a?(Hash) ? payload["error"] : {}
      end

      def describe(payload)
        api_error(payload)["message"].presence ||
          [ payload["error"], payload["error_description"] ].reject(&:blank?).join(", ").presence ||
          "no message"
      end
    end
  end
end
