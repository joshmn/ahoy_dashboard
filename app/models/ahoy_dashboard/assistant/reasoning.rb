module AhoyDashboard
  module Assistant
    Reasoning = Data.define(:reader, :api_base, :text) do
      class << self
        def stored(text)
          return nil if text.blank?

          current(text).to_column
        end

        def replayed(stored)
          reasoning = load(stored)

          reasoning.text if reasoning&.current?
        end

        def load(stored)
          return nil unless stored.is_a?(Hash) && stored["text"].present?

          new(reader: stored["reader"].to_s, api_base: stored["api_base"].to_s, text: stored["text"].to_s)
        end

        def current(text)
          new(reader: Assistant.reader_name, api_base: endpoint(Assistant.api_base), text: text.to_s)
        end

        def endpoint(url)
          url.to_s.strip.chomp("/")
        end
      end

      def current?
        reader == Assistant.reader_name && api_base == self.class.endpoint(Assistant.api_base)
      end

      def to_column
        { "reader" => reader, "api_base" => api_base, "text" => text }
      end
    end
  end
end
