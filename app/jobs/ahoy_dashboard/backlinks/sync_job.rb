module AhoyDashboard
  module Backlinks
    class SyncJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "backlinks"

      def perform(domain = nil)
        SyncCommand.call(domain: domain) do
          on(:ok) { |outcome| Rails.logger.info "backlinks synced #{outcome.domains} domains, #{outcome.gained} new, #{outcome.lost} gone" }
          on(:disabled) { Rails.logger.info "backlinks skipped, switched off" }
          on(:invalid) { |message| Rails.logger.warn "backlinks skipped, #{message}" }
          on(:capped) { Rails.logger.warn "backlinks skipped, the monthly ceiling is reached" }
          on(:refused) { |message| Rails.logger.warn "backlinks skipped: #{message.to_s.downcase}" }
          on(:unsupported) { |provider| Rails.logger.warn "#{provider} does not sell backlink data" }
          on(:rate_limited) { |message| Rails.logger.warn "backlinks hit a quota: #{message}" }
          on(:failed) do |message|
            Rails.logger.warn "backlinks failed: #{message}"
            raise Failed, message
          end
        end
      end
    end
  end
end
