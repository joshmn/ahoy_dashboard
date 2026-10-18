module AhoyDashboard
  module Seo
    class ProviderGate
      UNFIXABLE = %i[disabled no_host].freeze

      def initialize(feature, steps:, providers_path:, urls: {})
        @feature = feature
        @steps = steps
        @providers_path = providers_path
        @urls = urls
      end

      def refusal
        return @refusal if defined?(@refusal)

        @refusal = feature.refusal
      end

      def open?
        refusal.nil?
      end

      def setup_notice
        step = steps[refusal]
        return if step.nil?

        AhoyDashboard::SetupNotice.call(step, url: (urls.fetch(refusal, providers_path) unless refusal == :disabled))
      end

      def reason
        refusal && feature.refusal_message(refusal)
      end

      def fix
        return if open? || UNFIXABLE.include?(refusal)

        { label: "Search provider", url: providers_path }
      end

      private

      attr_reader :feature, :steps, :providers_path, :urls
    end
  end
end
