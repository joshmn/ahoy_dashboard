module AhoyDashboard
  module Assistant
    class Error < StandardError; end

    class NotConfiguredError < Error; end

    HISTORY = 20
    MAX_LENGTH = 2_000

    Reader = Data.define(:label, :api_base, :default_model, :provider, :models, :temperature_hint,
                         :endpoint_hint, :key_optional, :thinking, :replays_reasoning, :max_tokens) do
      def initialize(key_optional: false, thinking: false, replays_reasoning: false, max_tokens: nil, **attributes)
        super(key_optional: key_optional, thinking: thinking, replays_reasoning: replays_reasoning,
              max_tokens: max_tokens, **attributes)
      end

      def key_optional?
        key_optional
      end

      def thinking?
        thinking
      end

      def replays_reasoning?
        replays_reasoning
      end
    end

    READERS = {
      "anthropic" => Reader.new(label: "Anthropic", api_base: "https://api.anthropic.com/v1",
                                default_model: "claude-sonnet-4-6", provider: :anthropic,
                                models: %w[claude-opus-5 claude-sonnet-5 claude-sonnet-4-6 claude-haiku-4-5],
                                temperature_hint: "Opus 5, Sonnet 5 and every model that thinks before answering ignore it.",
                                endpoint_hint: "Only needed for a proxy in front of Anthropic's Messages API."),
      "openai" => Reader.new(label: "OpenAI", api_base: "https://api.openai.com/v1",
                             default_model: "gpt-4.1", provider: :openai,
                             models: %w[gpt-6-sol gpt-6-astra gpt-6-luna gpt-5 gpt-4.1 gpt-4.1-mini],
                             temperature_hint: "GPT-5, GPT-6 and the o models reason first and ignore it.",
                             endpoint_hint: "Only needed for a proxy in front of OpenAI's Responses API."),
      "deepseek" => Reader.new(label: "DeepSeek", api_base: "https://api.deepseek.com",
                               default_model: "deepseek-flash", provider: :compatible, thinking: true,
                               replays_reasoning: true, max_tokens: 65_536, models: %w[deepseek-flash deepseek-v4-pro],
                               temperature_hint: "DeepSeek thinks before every answer here and ignores it, so none is sent.",
                               endpoint_hint: "Only needed for a proxy in front of DeepSeek's API."),
      "compatible" => Reader.new(label: "OpenAI-compatible", api_base: "http://localhost:1234/v1",
                                 default_model: nil, key_optional: true, provider: :compatible, models: [],
                                 temperature_hint: "Sent as is. Some servers ignore it.",
                                 endpoint_hint: "Any server that speaks OpenAI's Chat Completions format: LM Studio, " \
                                                "Ollama, vLLM, OpenRouter, Groq, Together. Blank means LM Studio on " \
                                                "this machine.")
    }.freeze

    LEGACY_READERS = { "lmstudio" => "compatible" }.freeze

    DEFAULT_READER = "anthropic".freeze

    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1 0.0.0.0].freeze

    WITHHELD_KEY = "assistant_withheld_dimensions".freeze

    TOOLS = [
      "AhoyDashboard::Assistant::Tools::TrafficSummary",
      "AhoyDashboard::Assistant::Tools::Breakdown",
      "AhoyDashboard::Assistant::Tools::Trend",
      "AhoyDashboard::Assistant::Tools::SearchConsole",
      "AhoyDashboard::Assistant::Tools::Rankings",
      "AhoyDashboard::Assistant::Tools::AppContext"
    ].freeze

    class << self
      def enabled?
        Features.on?(:assistant) && installed?
      end

      def installed?
        Installation.installed?(:assistant)
      end

      def temperature
        record&.temperature&.to_f
      end

      def max_tokens
        record&.max_tokens
      end

      def record
        return nil unless installed?

        AssistantProvider.current
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def reader
        reader_key(record&.name).presence || DEFAULT_READER
      end

      def reader_name
        READERS.key?(reader) ? reader : DEFAULT_READER
      end

      def reader_for(name)
        READERS.fetch(reader_key(name)) { READERS.fetch(DEFAULT_READER) }
      end

      def reader_key(name)
        LEGACY_READERS.fetch(name.to_s, name.to_s)
      end

      def stored_names(name)
        key = reader_key(name)

        [ key, *LEGACY_READERS.select { |_legacy, current| current == key }.keys ]
      end

      def settings
        reader_for(reader)
      end

      def chosen_here?
        record.present?
      end

      def key_source
        return :stored if api_key.present?

        key_optional? ? :not_needed : :missing
      end

      def on_this_machine?(url)
        host = URI.parse(url.to_s.strip).host.to_s.downcase.delete_prefix("[").delete_suffix("]")

        LOOPBACK_HOSTS.include?(host) || host.end_with?(".localhost") || host.start_with?("127.")
      rescue URI::InvalidURIError
        false
      end

      def api_base
        record&.endpoint.presence || settings.api_base
      end

      def model_name
        record&.model_name.presence || settings.default_model
      end

      def api_key
        record&.api_key.presence
      end

      def key_optional?
        settings.key_optional?
      end

      def tool_classes
        TOOLS.map(&:constantize)
      end

      def offered_tool_classes
        tool_classes.select(&:available?)
      end

      def tools(views: nil, slice: Slice.new)
        offered_tool_classes.map { |klass| klass.new(views: views, slice: slice) }
      end

      def tool_labels
        @tool_labels = nil unless Rails.application.config.eager_load
        @tool_labels ||= tool_classes.index_by(&:tool_name).transform_values(&:label)
      end

      def tool_label(stored)
        key = stored.to_s.split("--").last.to_s.underscore
        return stored.to_s if key.blank?

        tool_labels[key] || key.humanize.downcase
      end

      def available?
        enabled? && model_name.present? && provider_ready?
      end

      def provider_ready?
        context.configured?
      rescue StandardError
        false
      end

      def unavailable_reason
        return Schedule.not_installed_reason(:assistant) unless installed?
        return "The assistant is switched off." unless enabled?
        return "No model is set for #{settings.label}." if model_name.blank?

        "#{settings.label} has no key set, so nothing can be asked."
      end

      def chat(views: nil, page: nil, slice: Slice.new)
        raise NotConfiguredError, unavailable_reason unless available?

        built = context.chat(model: model_name)
          .with_instructions(Instructions.fixed, context: Instructions.notes(page: page))
          .with_tools(*tools(views: views, slice: slice))

        temperature.nil? ? built : built.with_temperature(temperature)
      end

      def context
        LLM::Context.new(api_base: api_base, api_key: api_key, key_optional: key_optional?,
                         max_tokens: max_tokens || settings.max_tokens, provider: settings.provider,
                         thinking: settings.thinking?, replays_reasoning: settings.replays_reasoning?)
      end

      def withheld?(key)
        withheld_keys.include?(key.to_s)
      end

      def withheld_keys
        Preferences.read(:assistant, :withheld)
      end
    end
  end
end
