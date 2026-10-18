module AhoyDashboard
  module LLM
    module OpenAI
      module Output
        module_function

        def parts(response, type)
          Array(response["output"]).select { |item| item["type"] == "message" }
            .flat_map { |item| Array(item["content"]) }
            .select { |part| part["type"] == type }
        end

        def stop(response)
          return :refusal if parts(response, "refusal").any?

          case response.dig("incomplete_details", "reason")
          when "max_output_tokens" then :max_tokens
          when "content_filter" then :refusal
          end
        end
      end
    end
  end
end
