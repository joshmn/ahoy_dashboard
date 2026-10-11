module AhoyDashboard
  module LLM
    module Compatible
      # The transport. One POST to an OpenAI shaped /chat/completions, read as
      # server sent events. Net::HTTP because the rest of the gem already uses it
      # and an analytics dashboard has no business dragging in an HTTP stack.
      class Client
        def initialize(api_base:, api_key:, open_timeout: 10, read_timeout: 180, transport: nil)
          @api_base = api_base.to_s.chomp("/")
          @api_key = api_key.to_s
          @transport = transport || Transport.new(open_timeout: open_timeout, read_timeout: read_timeout)
        end

        # Yields each decoded event hash. Returns nothing; the caller assembles.
        def stream(payload)
          headers = { "Authorization" => (@api_key.present? ? "Bearer #{@api_key}" : nil) }

          @transport.stream("#{@api_base}/chat/completions", headers: headers, body: payload) do |event|
            yield event.data
          end
        end
      end
    end
  end
end
