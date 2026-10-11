require "net/http"
require "json"
require "uri"

module AhoyDashboard
  module LLM
    class Transport
      RETRYABLE_STATUSES = [ 408, 409, 429 ].freeze
      NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED,
                         Errno::EHOSTUNREACH, Errno::EPIPE, EOFError, SocketError, OpenSSL::SSL::SSLError ].freeze
      MAX_RETRIES = 2
      BASE_DELAY = 0.5
      MAX_DELAY = 8.0
      MAX_SERVER_DELAY = 60.0
      DONE = "[DONE]".freeze

      Event = Struct.new(:name, :data)

      class Retry < StandardError
        attr_reader :error, :delay

        def initialize(error, delay: nil)
          @error = error
          @delay = delay
          super(error.message)
        end
      end

      def initialize(open_timeout: 10, read_timeout: 180, max_retries: MAX_RETRIES, sleeper: nil)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @max_retries = max_retries
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      end

      def stream(url, headers:, body:, &block)
        uri = URI(url)
        attempt = 0

        begin
          deliver(uri, headers, body, &block)
        rescue Retry => e
          raise e.error if attempt >= @max_retries

          attempt += 1
          @sleeper.call(e.delay || backoff(attempt))
          retry
        end
      end

      private

      def deliver(uri, headers, body, &block)
        started = false

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
          http.request(build(uri, headers, body)) do |response|
            fail_with(response) unless response.code.to_i == 200

            started = true
            read(response, &block)
          end
        end
      rescue *NETWORK_ERRORS => e
        error = Error.new("could not reach the model: #{e.class}: #{e.message}")
        raise error if started

        raise Retry.new(error)
      end

      def build(uri, headers, body)
        Net::HTTP::Post.new(uri).tap do |request|
          request["Content-Type"] = "application/json"
          request["Accept"] = "text/event-stream"
          headers.each { |key, value| request[key] = value if value.present? }
          request.body = JSON.generate(body)
        end
      end

      def read(response)
        buffer = +""
        name = nil
        data = []

        response.read_body do |segment|
          buffer << segment
          while (break_at = buffer.index("\n"))
            line = buffer.slice!(0..break_at).chomp.delete_suffix("\r")

            if line.empty?
              event = decode(name, data)
              yield event if event
              name = nil
              data = []
            elsif line.start_with?("event:")
              name = line.delete_prefix("event:").strip
            elsif line.start_with?("data:")
              data << line.delete_prefix("data:").strip
            end
          end
        end

        event = decode(name, data)
        yield event if event
      end

      def decode(name, data)
        body = data.join("\n")
        return nil if body.empty? || body == DONE

        Event.new(name, JSON.parse(body))
      rescue JSON::ParserError
        nil
      end

      def fail_with(response)
        status = response.code.to_i
        body = response.read_body.to_s
        said = detail(body)
        error = Error.new([ "#{status} from the model", said ].compact.join(": "),
                          status: status, type: error_type(body), detail: said)

        raise Retry.new(error, delay: server_delay(response)) if retryable?(response, status)

        raise error
      end

      def retryable?(response, status)
        case response["x-should-retry"]
        when "true" then true
        when "false" then false
        else RETRYABLE_STATUSES.include?(status) || status >= 500
        end
      end

      def server_delay(response)
        milliseconds = response["retry-after-ms"].to_s
        return (milliseconds.to_f / 1000).clamp(0, MAX_SERVER_DELAY) if milliseconds.match?(/\A\d+(\.\d+)?\z/)

        seconds = response["retry-after"].to_s
        return seconds.to_f.clamp(0, MAX_SERVER_DELAY) if seconds.match?(/\A\d+(\.\d+)?\z/)

        nil
      end

      def backoff(attempt)
        delay = [ BASE_DELAY * (2**(attempt - 1)), MAX_DELAY ].min

        delay * (1 - (rand * 0.25))
      end

      def parsed(body)
        value = JSON.parse(body)
        value.is_a?(Hash) ? value : {}
      rescue JSON::ParserError
        {}
      end

      def detail(body)
        error = parsed(body)["error"]
        message = error.is_a?(Hash) ? error["message"] : error

        message.to_s.presence || (json?(body) ? nil : body.first(200).presence)
      end

      def json?(body)
        JSON.parse(body)
        true
      rescue JSON::ParserError
        false
      end

      def error_type(body)
        error = parsed(body)["error"]

        error.is_a?(Hash) ? error["type"].to_s.presence : nil
      end
    end
  end
end
