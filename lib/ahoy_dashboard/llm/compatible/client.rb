module AhoyDashboard
  module LLM
    module Compatible
      class Client < LLM::Client
        def stream(payload)
          transport.stream("#{api_base}/chat/completions", headers: bearer, body: payload) do |event|
            yield event.data
          end
        end
      end
    end
  end
end
