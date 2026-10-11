module AhoyDashboard
  module LLM
    module Anthropic
      module Models
        ADAPTIVE_THINKING = /\Aclaude-(opus-4-[6-9]|opus-[5-9]|sonnet-4-[6-9]|sonnet-[5-9]|fable|mythos)/
        NO_SAMPLING = /\Aclaude-(opus-4-[7-9]|opus-[5-9]|sonnet-[5-9]|fable|mythos)/
        DEFAULT_FALLBACKS = /\Aclaude-(opus-5(\z|-\d{8}\z)|fable-5)/
        SHORT_OUTPUT = /\Aclaude-(3|opus-4-0|opus-4-1|opus-4-2025|sonnet-4-0|sonnet-4-2025)/

        FALLBACK_BETA = "server-side-fallback-2026-07-01".freeze
        MAX_TOKENS = 64_000
        SHORT_MAX_TOKENS = 8_192

        module_function

        def adaptive_thinking?(model)
          model.to_s.match?(ADAPTIVE_THINKING)
        end

        def sampling?(model)
          !model.to_s.match?(NO_SAMPLING)
        end

        def default_fallbacks?(model)
          model.to_s.match?(DEFAULT_FALLBACKS)
        end

        def max_tokens(model)
          model.to_s.match?(SHORT_OUTPUT) ? SHORT_MAX_TOKENS : MAX_TOKENS
        end
      end
    end
  end
end
