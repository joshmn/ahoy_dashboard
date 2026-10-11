module AhoyDashboard
  module Settings
    class StoredSecretPresenter
      STORED_HINT = "Stored. Leave this blank to keep it.".freeze
      MISSING_HINT = "Nothing stored.".freeze
      GOOGLE_LABELS = { client_id: "client ID", client_secret: "client secret" }.freeze

      attr_reader :key, :label, :consequence

      class << self
        def assistant(name)
          record = AssistantProvider.for(name)
          provider = Assistant::READERS.fetch(name.to_s)[:label]

          consequence = if record&.active?
            "The assistant stops answering until a key is saved again."
          else
            "Nothing uses it while #{provider} is not the active provider."
          end

          new(key: :api_key, label: "#{provider} key", stored: record&.api_key.present?, consequence: consequence)
        end

        def serp(name, key, record: SerpProvider.for(name))
          provider = Display.serp_label(name)
          label = sentence_label(key)

          users = serp_users(name, active: record&.active?)

          consequence = if users.any?
            "#{users.to_sentence.upcase_first} #{users == [ "keyword research" ] ? "stops" : "stop"} until it is saved again."
          else
            "Nothing uses it while #{provider} is not the active provider."
          end

          new(key: key.to_sym, label: "#{provider} #{label}", stored: record&.credential(key).present?,
              consequence: consequence)
        end

        def ai_visibility(name)
          record = AiVisibility::Assistant.for(name)
          label = AiVisibility.label(name)

          consequence = if AiVisibility.enabled? && AiVisibility::Prompt.exists? && AiVisibility.on?(name, record: record)
            "#{label} stops being asked until a key is saved again."
          elsif AiVisibility.enabled? && AiVisibility::Prompt.exists?
            "#{label} is off, so nothing asks it either way."
          else
            "Nothing asks #{label} until AI visibility is on and has prompts."
          end

          new(key: :api_key, label: "#{label} key", stored: record&.api_key.present?, consequence: consequence)
        end

        def google(key, connected: SearchConsole.installed? && GoogleAccount.current&.connected?)
          label = GOOGLE_LABELS.fetch(key.to_sym)

          consequence = if connected
            "Syncing stops until one is saved again. The Google connection stays."
          else
            "Google cannot be connected until one is saved again."
          end

          new(key: key.to_sym, label: label, stored: SearchConsole.credential&.value(key).present?,
              consequence: consequence)
        end

        private

        def sentence_label(key)
          label = Display.credential_label(key)
          label.match?(/\A[A-Z][a-z]/) ? label.sub(/\A./) { |letter| letter.downcase } : label
        end

        def serp_users(name, active:)
          users = []
          users << "rank checks" if active && Serp.installed?
          users << "keyword research" if Keywords.enabled? && Keywords.provider.to_s == name.to_s
          users << "backlinks" if Backlinks.enabled? && Backlinks.provider.to_s == name.to_s
          active ? users.presence || [ "searches" ] : users
        end
      end

      def initialize(key:, label:, stored:, consequence:)
        @key = key
        @label = label
        @stored = stored
        @consequence = consequence
      end

      def stored?
        @stored
      end

      def hint(stored: STORED_HINT)
        stored? ? stored : MISSING_HINT
      end

      def question
        "Remove the stored #{label}? #{consequence}"
      end

      def removed_notice
        "#{label.upcase_first} removed."
      end

      def missing_notice
        "There was no #{label} stored."
      end
    end
  end
end
