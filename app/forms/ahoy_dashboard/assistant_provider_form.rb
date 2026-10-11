module AhoyDashboard
  class AssistantProviderForm < AhoyDashboard::Form
    FIELDS = %i[name model api_base temperature max_tokens active credentials].freeze
    MAX_TEMPERATURE = 2
    MAX_OUTPUT = 128_000

    attribute :name, :string
    attribute :model, :string
    attribute :api_base, :string
    attribute :temperature, :decimal
    attribute :max_tokens, :integer
    attribute :active, :boolean, default: false
    attribute :credentials

    validates :name, inclusion: { in: AhoyDashboard::AssistantProvider::NAMES,
                                  message: "is not a reader this has" }
    validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_TEMPERATURE,
                                            message: "has to be between 0 and #{MAX_TEMPERATURE}" }, allow_nil: true
    validates :max_tokens, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_OUTPUT,
                                           message: "has to be a whole number from 1 to #{ActiveSupport::NumberHelper.number_to_delimited(MAX_OUTPUT)}" },
                           allow_nil: true
    validate :a_model_is_named

    def self.from_record(provider)
      new(name: provider.name, model: provider.model, api_base: provider.api_base,
          temperature: provider.temperature, max_tokens: provider.max_tokens,
          active: provider.active, credentials: provider.credentials)
    end

    def reader
      AhoyDashboard::Assistant::READERS.fetch(name.to_s) { {} }
    end

    def local?
      reader[:local].present?
    end

    def default_model
      reader[:default_model]
    end

    def suggested_models
      Array(reader[:models])
    end

    def temperature_hint
      reader[:temperature_hint]
    end

    def default_output
      case reader[:provider]
      when :anthropic then LLM::Anthropic::Models.max_tokens(model.presence || default_model)
      when :openai then LLM::OpenAI::Models::MAX_TOKENS
      else LLM::Compatible::Chat::DEFAULT_MAX_TOKENS
      end
    end

    def endpoint
      api_base.to_s.strip.presence || reader[:api_base]
    end

    def on_this_machine?
      AhoyDashboard::Assistant.on_this_machine?(endpoint)
    end

    def lede
      return "The key is encrypted before it is stored." unless local?
      return "Nothing leaves the machine. Start the local server and load a model first." if on_this_machine?

      "Questions and what the tools read go to #{URI.parse(endpoint).host.presence || endpoint}, not this machine. " \
        "Start that server and load a model first."
    rescue URI::InvalidURIError
      "Questions and what the tools read go to #{endpoint}. Start that server and load a model first."
    end

    def credential(key)
      (credentials || {}).to_h.symbolize_keys[key.to_sym]
    end

    def submitted_credentials
      (credentials || {}).to_h.symbolize_keys.slice(:api_key)
    end

    def record_attributes
      { model: model.presence, api_base: api_base.presence, temperature: temperature, max_tokens: max_tokens }
    end

    private

    # A local server names whatever model it has loaded, and there is no default
    # to fall back on, so leaving it blank there is not a setup.
    def a_model_is_named
      return if model.present? || default_model.present?

      errors.add(:model, "has to be named, because this reader has no default")
    end
  end
end
