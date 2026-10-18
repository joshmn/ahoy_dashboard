require "net/http"
require "openssl"
require "json"
require "uri"

module AhoyDashboard
  class HttpClient
    CONNECTION_ERRORS = [ Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
                          SocketError ].freeze
    NETWORK_ERRORS = (CONNECTION_ERRORS + [ Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE,
                                            Errno::ETIMEDOUT, EOFError, OpenSSL::SSL::SSLError ]).freeze
    RETRIES = 1

    class Unreachable < StandardError; end

    Reply = Data.define(:response, :payload) do
      def success?
        response.is_a?(Net::HTTPSuccess)
      end
    end

    def initialize(open_timeout:, read_timeout:)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def get(url, params: {}, headers: {})
      uri = URI(url)
      uri.query = URI.encode_www_form(params.compact) if params.present?

      deliver(uri, Net::HTTP::Get.new(uri), headers: headers, retry_on: NETWORK_ERRORS)
    end

    def post_json(url, body:, headers: {}, basic_auth: nil, idempotent: false)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.basic_auth(*basic_auth) if basic_auth
      request.body = body.to_json

      deliver(uri, request, headers: headers, retry_on: retried_on(idempotent))
    end

    def post_form(url, params:, headers: {}, idempotent: false)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(params)

      deliver(uri, request, headers: headers, retry_on: retried_on(idempotent))
    end

    private

    def retried_on(idempotent)
      idempotent ? NETWORK_ERRORS : CONNECTION_ERRORS
    end

    def deliver(uri, request, headers:, retry_on:)
      request["User-Agent"] = AhoyDashboard.user_agent
      headers.each { |key, value| request[key] = value }
      response = perform(uri, request, retry_on: retry_on, retries_left: RETRIES)

      Reply.new(response: response, payload: parse(response.body))
    end

    def perform(uri, request, retry_on:, retries_left:)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @open_timeout,
                                          read_timeout: @read_timeout, max_retries: 0) do |http|
        http.request(request)
      end
    rescue *NETWORK_ERRORS => e
      raise Unreachable, "#{e.class}: #{e.message}" unless retries_left.positive? && retry_on.any? { |error| e.is_a?(error) }

      perform(uri, request, retry_on: retry_on, retries_left: retries_left - 1)
    end

    def parse(body)
      return {} if body.blank?

      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end
