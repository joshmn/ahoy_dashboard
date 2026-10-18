module AhoyDashboard
  module LLM
    module OpenAI
      class Client < LLM::Client
        def stream(body, &on_text)
          assembler = Assembler.new

          transport.stream("#{api_base}/responses", headers: bearer, body: body.merge("stream" => true)) do |event|
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
            raise Error, LLM::Client::UNFINISHED if @response.nil?

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
