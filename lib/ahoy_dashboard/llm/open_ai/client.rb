module AhoyDashboard
  module LLM
    module OpenAI
      class Client
        def initialize(api_base:, api_key:, open_timeout: 10, read_timeout: 180, transport: nil)
          @api_base = api_base.to_s.chomp("/")
          @api_key = api_key.to_s
          @transport = transport || Transport.new(open_timeout: open_timeout, read_timeout: read_timeout)
        end

        def stream(body, &on_text)
          assembler = Assembler.new
          headers = { "Authorization" => (@api_key.present? ? "Bearer #{@api_key}" : nil) }

          @transport.stream("#{@api_base}/responses", headers: headers, body: body.merge("stream" => true)) do |event|
            assembler.feed(event.data, &on_text)
          end

          assembler.response
        end

        class Assembler
          FINISHED = %w[response.completed response.incomplete].freeze

          def initialize
            @response = nil
            @items = {}
          end

          def feed(data)
            case data["type"]
            when "response.output_text.delta"
              yield data["delta"].to_s if block_given?
            when "response.output_item.done"
              @items[data["output_index"].to_i] = data["item"]
            when *FINISHED
              @response = data["response"] || {}
            when "response.failed"
              fail_with((data["response"] || {})["error"] || {})
            when "error"
              fail_with(data)
            end
          end

          def response
            raise Error, "the stream ended before the response finished" if @response.nil?

            finished = Array(@response["output"])
            @response.merge("output" => @items.any? ? @items.keys.sort.map { |index| @items[index] } : finished)
          end

          private

          def fail_with(error)
            raise Error.new("the model stopped partway: #{error["message"].presence || error["code"]}", type: error["code"])
          end
        end
      end
    end
  end
end
