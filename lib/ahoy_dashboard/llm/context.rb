module AhoyDashboard
  module LLM
    class Context
      PROVIDERS = { anthropic: Anthropic, openai: OpenAI, compatible: Compatible }.freeze

      attr_reader :api_base, :api_key, :provider

      def initialize(api_base:, api_key: nil, key_optional: false, max_tokens: nil, provider: :compatible,
                     thinking: false, replays_reasoning: false)
        @api_base = api_base.to_s
        @api_key = api_key.to_s
        @key_optional = key_optional
        @max_tokens = max_tokens
        @thinking = thinking
        @replays_reasoning = replays_reasoning
        @provider = PROVIDERS.key?(provider.to_s.to_sym) ? provider.to_s.to_sym : :compatible
      end

      def configured?
        api_base.present? && (api_key.present? || key_optional?)
      end

      def key_optional?
        @key_optional
      end

      def chat(model:)
        raise Error, "no model set" if model.blank?
        return compatible_chat(model) if provider == :compatible

        PROVIDERS.fetch(provider)::Chat.new(client: client, model: model, max_tokens: @max_tokens)
      end

      def client
        @client ||= PROVIDERS.fetch(provider)::Client.new(api_base: api_base, api_key: api_key.presence || "not-needed-locally")
      end

      private

      def compatible_chat(model)
        Compatible::Chat.new(client: client, model: model, max_tokens: @max_tokens, thinking: @thinking,
                             replays_reasoning: @replays_reasoning)
      end
    end
  end
end
