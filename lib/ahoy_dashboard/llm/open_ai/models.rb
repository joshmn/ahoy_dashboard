module AhoyDashboard
  module LLM
    module OpenAI
      module Models
        REASONING = /\A(gpt-5|gpt-6|gpt-[7-9]|o\d)/
        MAX_TOKENS = 32_000

        module_function

        def reasoning?(model)
          model.to_s.match?(REASONING)
        end

        def sampling?(model)
          !reasoning?(model)
        end
      end
    end
  end
end
