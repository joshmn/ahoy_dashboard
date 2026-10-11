module AhoyDashboard
  module Keywords
    class FetchJob < AhoyDashboard::Job
      queue_as :low

      def perform(seed, refresh = false, location: nil, language: nil)
        FetchCommand.call(seed: seed, location: location, language: language, refresh: refresh) do
          on(:ok) { |outcome| Rails.logger.info "keyword ideas stored #{outcome.written} for #{outcome.seed} in #{outcome.location}, #{outcome.language}" }
          on(:disabled) { Rails.logger.info "keyword ideas skipped, switched off" }
          on(:saved) { Rails.logger.info "keyword ideas skipped, #{seed} is already saved" }
          on(:capped) { Rails.logger.warn "keyword ideas skipped, the monthly ceiling is reached" }
          on(:refused) { |message| Rails.logger.warn "keyword ideas skipped: #{message.to_s.downcase}" }
          on(:unsupported) { |provider| Rails.logger.warn "#{provider} does not sell keyword data" }
          on(:rate_limited) { |message| Rails.logger.warn "keyword ideas hit a quota: #{message}" }
          on(:failed) { |message| Rails.logger.warn "keyword ideas failed: #{message}" }
        end
      end
    end
  end
end
