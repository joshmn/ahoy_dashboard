module AhoyDashboard
  class AssistantProviderForm < AhoyDashboard::Form
    include SecretFields

    MAX_TEMPERATURE = 2
    MAX_OUTPUT = 128_000

    attribute :name, :string
    attribute :model, :string
    attribute :api_base, :string
    attribute :temperature, :decimal
    attribute :max_tokens, :integer
    attribute :active, :boolean, default: false

    validates :name, inclusion: { in: AhoyDashboard::AssistantProvider::NAMES,
                                  message: "is not a reader this has" }
    validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_TEMPERATURE,
                                            message: "has to be between 0 and #{MAX_TEMPERATURE}" }, allow_nil: true
    validates :max_tokens, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_OUTPUT,
                                           message: "has to be a whole number from 1 to #{ActiveSupport::NumberHelper.number_to_delimited(MAX_OUTPUT)}" },
                           allow_nil: true
    validate :a_model_is_named

    def self.from_record(provider)
      new(name: AhoyDashboard::Assistant.reader_key(provider.name), model: provider.model, api_base: provider.api_base,
          temperature: provider.temperature, max_tokens: provider.max_tokens,
          active: provider.active)
    end

    def reader
      AhoyDashboard::Assistant.reader_for(name)
    end

    def key_optional?
      reader.key_optional?
    end

    def default_model
      reader.default_model
    end

    def suggested_models
      reader.models
    end

    def model_options
      AhoyDashboard::Assistant::ModelOption.listed(suggested_models)
    end

    def temperature_hint
      reader.temperature_hint
    end

    def default_output
      return reader.max_tokens if reader.max_tokens

      case reader.provider
      when :anthropic then LLM::Anthropic::Models.max_tokens(model.presence || default_model)
      when :openai then LLM::OpenAI::Models::MAX_TOKENS
      else LLM::Compatible::Chat::DEFAULT_MAX_TOKENS
      end
    end

    def endpoint
      api_base.to_s.strip.presence || reader.api_base
    end

    def endpoint_suffix
      URI.parse(reader.api_base).path.presence
    end

    def on_this_machine?
      AhoyDashboard::Assistant.on_this_machine?(endpoint)
    end

    def lede
      return "The key is encrypted before it is stored." unless key_optional?
      return "Nothing leaves the machine. Start the local server and load a model first." if on_this_machine?

      "Questions and what the tools read go to #{URI.parse(endpoint).host.presence || endpoint}, not this machine. " \
        "A key is optional, and encrypted before it is stored."
    rescue URI::InvalidURIError
      "Questions and what the tools read go to #{endpoint}. A key is optional, and encrypted before it is stored."
    end

    def record_attributes
      { model: model.presence, api_base: api_base.presence, temperature: temperature, max_tokens: max_tokens }
    end

    private

    def a_model_is_named
      return if model.present? || default_model.present?

      errors.add(:model, "has to be named, because this reader has no default")
    end
  end
end
