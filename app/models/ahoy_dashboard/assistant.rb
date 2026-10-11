module AhoyDashboard
  module Assistant
    class Error < StandardError; end

    class NotConfiguredError < Error; end

    HISTORY = 20
    MAX_LENGTH = 2_000

    # local means no key is needed, not that the address is on this machine.
    READERS = {
      "anthropic" => { label: "Anthropic", api_base: "https://api.anthropic.com/v1",
                       default_model: "claude-sonnet-4-6", provider: :anthropic,
                       models: %w[claude-opus-5 claude-sonnet-5 claude-sonnet-4-6 claude-haiku-4-5],
                       temperature_hint: "Opus 5, Sonnet 5 and every model that thinks before answering ignore it.",
                       endpoint_hint: "Only needed for a proxy in front of Anthropic's Messages API." },
      "openai" => { label: "OpenAI", api_base: "https://api.openai.com/v1",
                    default_model: "gpt-4.1", provider: :openai,
                    models: %w[gpt-6-sol gpt-6-astra gpt-6-luna gpt-5 gpt-4.1 gpt-4.1-mini],
                    temperature_hint: "GPT-5, GPT-6 and the o models reason first and ignore it.",
                    endpoint_hint: "Only needed for a proxy in front of OpenAI's Responses API." },
      "lmstudio" => { label: "LM Studio (local)", api_base: "http://localhost:1234/v1",
                      default_model: nil, local: true, provider: :compatible, models: [],
                      temperature_hint: "Sent as is. Some local servers ignore it.",
                      endpoint_hint: "Any other server that speaks OpenAI's Chat Completions format, " \
                                     "like Ollama or vLLM, works here too." }
    }.freeze

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
      # The deployment wide switch and the operator's choice of provider are two
      # different things. This one is a kill switch: off here and nothing is
      # asked no matter what is set up on the settings screen.
      def enabled?
        Features.on?(:assistant) && installed?
      end

      def installed?
        Installation.installed?(:assistant)
      end

      # nil is a real answer here: it means send no temperature at all.
      def temperature
        record&.temperature&.to_f
      end

      def max_tokens
        record&.max_tokens
      end

      # Reading the record through a rescue so a box part way through a
      # migration answers "not set up" rather than raising on every dashboard
      # page.
      def record
        return nil unless installed?

        AssistantProvider.current
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def reader
        record&.name.presence || DEFAULT_READER
      end

      def reader_name
        READERS.key?(reader) ? reader : DEFAULT_READER
      end

      def settings
        READERS.fetch(reader) { READERS.fetch(DEFAULT_READER) }
      end

      def chosen_here?
        record.present?
      end

      def key_source
        return :not_needed if local?

        api_key.present? ? :stored : :missing
      end

      def on_this_machine?(url)
        host = URI.parse(url.to_s.strip).host.to_s.downcase.delete_prefix("[").delete_suffix("]")

        LOOPBACK_HOSTS.include?(host) || host.end_with?(".localhost") || host.start_with?("127.")
      rescue URI::InvalidURIError
        false
      end

      def api_base
        record&.endpoint.presence || settings[:api_base]
      end

      def model_name
        record&.model_name.presence || settings[:default_model]
      end

      def api_key
        record&.api_key.presence
      end

      def local?
        settings[:local].present?
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

      # Rows written before the tools had short names still hold the class name
      # the gem built, which is every :: turned into a pair of dashes.
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
        return "No model is set for #{settings[:label]}." if model_name.blank?

        "#{settings[:label]} has no key set, so nothing can be asked."
      end

      def chat(views: nil, page: nil, slice: Slice.new)
        raise NotConfiguredError, unavailable_reason unless available?

        built = context.chat(model: model_name)
          .with_instructions(Instructions.fixed, context: Instructions.notes(page: page))
          .with_tools(*tools(views: views, slice: slice))

        temperature.nil? ? built : built.with_temperature(temperature)
      end

      # Built per call from this reader's settings rather than held globally, so
      # pointing the dashboard at a model on this machine cannot reconfigure
      # anything else in the host that talks to a provider.
      def context
        LLM::Context.new(api_base: api_base, api_key: api_key, local: local?,
                         max_tokens: max_tokens, provider: settings[:provider])
      end

      def withheld?(key)
        withheld_keys.include?(key.to_s)
      end

      def withheld_keys
        Array(Setting.read(WITHHELD_KEY, [])).map(&:to_s)
      end
    end
  end
end
