module AhoyDashboard
  module SearchConsole
    class BaseService
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 30
      DEFAULT_LIFETIME = 3600

      QUOTA_REASONS = %w[quotaExceeded rateLimitExceeded userRateLimitExceeded].freeze

      def self.call(**options)
        new(**options).call
      end

      private

      def require_configured!
        raise AuthError, "search console is not configured" unless SearchConsole.enabled?
      end

      def expires_at(payload)
        Time.current + (payload["expires_in"].presence&.to_i || DEFAULT_LIFETIME).seconds
      end

      def http
        @http ||= HttpClient.new(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      end

      def get_json(url, token)
        send_request { http.get(url, headers: bearer(token)) }
      end

      def post_json(url, token, body)
        send_request { http.post_json(url, body: body, headers: bearer(token), idempotent: true) }
      end

      def post_form(url, params)
        send_request { http.post_form(url, params: params, idempotent: true) }
      end

      def bearer(token)
        { "Authorization" => "Bearer #{token}" }
      end

      def send_request
        reply = yield
        return reply.payload if reply.success?

        raise error_for(reply.response, reply.payload)
      rescue HttpClient::Unreachable => e
        raise Error, "search console request failed: #{e.message}"
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
