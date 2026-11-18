module AhoyDashboard
  module AiVisibility
    class Error < StandardError; end

    class AuthError < Error; end

    class QuotaError < Error; end

    ASSISTANTS = {
      "openai" => { label: "ChatGPT", provider: "OpenAI", default_model: "gpt-5",
                    models: %w[gpt-5 gpt-5-mini gpt-4.1 gpt-4.1-mini],
                    client: "AhoyDashboard::AiVisibility::Clients::OpenAiClient" },
      "anthropic" => { label: "Claude", provider: "Anthropic", default_model: "claude-opus-5",
                       models: %w[claude-opus-5 claude-sonnet-5 claude-haiku-4-5],
                       client: "AhoyDashboard::AiVisibility::Clients::AnthropicClient" },
      "gemini" => { label: "Gemini", provider: "Google", default_model: "gemini-2.5-flash",
                    models: %w[gemini-2.5-pro gemini-2.5-flash gemini-2.5-flash-lite],
                    client: "AhoyDashboard::AiVisibility::Clients::GeminiClient" },
      "perplexity" => { label: "Perplexity", provider: "Perplexity", default_model: "sonar",
                        models: %w[sonar sonar-pro sonar-reasoning-pro],
                        client: "AhoyDashboard::AiVisibility::Clients::PerplexityClient" }
    }.freeze

    NAMES = ASSISTANTS.keys.freeze

    MAX_MODELS = 10

    FREQUENCIES = {
      "daily" => { label: "Daily", every: 1.day },
      "weekly" => { label: "Weekly", every: 1.week },
      "monthly" => { label: "Monthly", every: 1.month }
    }.freeze

    DEFAULT_FREQUENCY = "weekly".freeze
    DAYS_PER_MONTH = 30.44
    DEFAULT_CAP = 200

    FREQUENCY_KEY = "ai_visibility_frequency".freeze
    CAP_KEY = "ai_visibility_monthly_cap".freeze

    Target = Data.define(:assistant, :model) do
      def label
        AiVisibility.target_label(assistant, model)
      end
    end

    def self.table_name_prefix
      "ahoy_dashboard_ai_visibility_"
    end

    class << self
      def enabled?
        Features.on?(:ai_visibility) && installed?
      end

      def installed?
        Installation.installed?(:ai_visibility)
      end

      def label(name)
        ASSISTANTS.dig(name.to_s, :label) || name.to_s.titleize
      end

      def target_label(name, model)
        model.present? ? "#{label(name)} (#{model})" : label(name)
      end

      def target_order(name, model)
        [ NAMES.index(name) || NAMES.size, name, model.to_s ]
      end

      def default_model(name)
        ASSISTANTS.fetch(name.to_s)[:default_model]
      end

      def catalog(name)
        ASSISTANTS.fetch(name.to_s)[:models]
      end

      def api_key(name)
        Assistant.for(name)&.api_key.presence
      end

      def models_for(name, record: Assistant.for(name))
        record&.models.presence || [ default_model(name) ]
      end

      def on?(name, record: Assistant.for(name))
        record.nil? || record.enabled?
      end

      def records
        Assistant.where(name: NAMES).index_by(&:name)
      end

      def asked_names(records = self.records)
        NAMES.select do |name|
          record = records[name]
          on?(name, record: record) && record&.api_key.present?
        end
      end

      def targets(records = self.records)
        asked_names(records).flat_map do |name|
          models_for(name, record: records[name]).map { |model| Target.new(assistant: name, model: model) }
        end
      end

      def frequency
        stored = Preferences.read(:ai_visibility, :frequency)

        FREQUENCIES.key?(stored) ? stored : DEFAULT_FREQUENCY
      end

      def every
        FREQUENCIES.fetch(frequency)[:every]
      end

      def monthly_cap
        Preferences.read(:ai_visibility, :monthly_cap)
      end

      def runs_per_month
        DAYS_PER_MONTH / (every / 1.day)
      end

      def monthly_requests(prompts, targets: self.targets.size)
        (prompts * targets * runs_per_month).round
      end

      def capped?
        monthly_cap.positive?
      end

      def month_start(now: Time.current)
        now.in_time_zone(AhoyDashboard.time_zone).beginning_of_month
      end

      def used_this_month(now: Time.current)
        Answer.where(Answer.arel_table[:asked_at].gteq(month_start(now: now))).count
      end

      def remaining(now: Time.current)
        return Float::INFINITY unless capped?

        [ monthly_cap - used_this_month(now: now), 0 ].max
      end

      def client_for(name, model, key: api_key(name))
        ASSISTANTS.fetch(name.to_s)[:client].constantize.new(api_key: key, model: model)
      end

      def ready?
        enabled? && asked_names.any? && Prompt.exists?
      end

      def due?(now: Time.current)
        last = Run.triggered_by_schedule.maximum(:started_at)

        last.nil? || last <= now - every
      end
    end
  end
end
