module AhoyDashboard
  module Assistant
    class StatusReport
      KEY_SOURCES = {
        stored: "stored on the settings screen",
        not_needed: "not needed for a local reader",
        missing: "missing"
      }.freeze

      def self.lines
        new.lines
      end

      def lines
        return [ not_installed ] unless Assistant.installed?

        [ *setup, *tools, *stored, *next_step ]
      end

      private

      def setup
        [
          "enabled: #{Assistant.enabled?}",
          "reader: #{Assistant.reader_name}#{", the default until one is chosen on settings, assistant" unless Assistant.chosen_here?}",
          "model: #{Assistant.model_name.presence || "not set"}",
          "temperature: #{Assistant.temperature.nil? ? "the model's own" : Assistant.temperature}",
          "output limit: #{Assistant.max_tokens || "the reader's own"}",
          "endpoint: #{Assistant.api_base}",
          "kept out: #{Assistant.withheld_keys.presence&.join(", ") || "nothing"}",
          "key: #{KEY_SOURCES.fetch(Assistant.key_source)}",
          "available: #{Assistant.available?}",
          ("why not: #{Assistant.unavailable_reason.sub(/\A./) { |letter| letter.downcase }}" unless Assistant.available?),
          ("last error: #{last_error.last_error}" if last_error)
        ].compact
      end

      def tools
        Assistant.tool_classes.map do |tool|
          next "tool #{tool.tool_name}: #{tool.label}" if tool.available?

          "tool #{tool.tool_name}: #{tool.label}, not offered because #{FeatureState.for(tool.feature).terminal_line}"
        end
      end

      def not_installed
        FeatureState.for(:assistant).terminal_line
      end

      def stored
        pending = ChatMessage.pending.count

        [
          "conversations: #{Chat.count}",
          "turns: #{ChatMessage.count}",
          ("still waiting on a reply: #{pending}" if pending.positive?)
        ].compact
      end

      def next_step
        return [] if Assistant.available?
        return [ "next: switch the assistant on under settings, features" ] unless Assistant.enabled?
        return [ "next: name a model on settings, assistant" ] if Assistant.model_name.blank?

        [ "next: save a key for #{Assistant.settings.label} on settings, assistant" ]
      end

      def last_error
        return @last_error if defined?(@last_error)

        @last_error = AssistantProvider.for(Assistant.reader_name)&.yield_self { |provider| provider if provider.last_error.present? }
      end
    end
  end
end
