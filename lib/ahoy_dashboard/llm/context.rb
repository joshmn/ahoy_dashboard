module AhoyDashboard
  module LLM
    # One reader's settings, and the chats built from them. A context rather
    # than global state, so pointing the dashboard at a model on this machine
    # cannot reconfigure anything else in the host that talks to a provider.
    class Context
      PROVIDERS = { anthropic: Anthropic, openai: OpenAI, compatible: Compatible }.freeze

      attr_reader :api_base, :api_key, :provider

      def initialize(api_base:, api_key: nil, local: false, max_tokens: nil, provider: :compatible)
        @api_base = api_base.to_s
        @api_key = api_key.to_s
        @local = local
        @max_tokens = max_tokens
        @provider = PROVIDERS.key?(provider.to_s.to_sym) ? provider.to_s.to_sym : :compatible
      end

      # A local server still wants a key sent and does not care what it is, so a
      # base with no key is a working setup rather than a half configured one.
      def configured?
        api_base.present? && (api_key.present? || local?)
      end

      def local?
        @local
      end

      def chat(model:, **)
        raise Error, "no model set" if model.blank?

        PROVIDERS.fetch(provider)::Chat.new(client: client, model: model, max_tokens: @max_tokens)
      end

      def client
        @client ||= PROVIDERS.fetch(provider)::Client.new(api_base: api_base, api_key: api_key.presence || "not-needed-locally")
      end
    end
  end
end
