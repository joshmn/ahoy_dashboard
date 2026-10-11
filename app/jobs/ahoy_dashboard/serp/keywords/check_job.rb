module AhoyDashboard
  module Serp
    module Keywords
      class CheckJob < AhoyDashboard::Job
        queue_as :low

        def perform(keyword_id, location)
          return unless Serp.installed?

          keyword = SerpKeyword.find_by(id: keyword_id)
          return if keyword.nil? || !keyword.enabled?

          Checks::RunCommand.call(keyword: keyword, location: location) do
            on(:ok) { |outcome| Rails.logger.info "serp checked #{keyword.query} at #{location}, #{outcome.units} units" }
            on(:skipped) { |reason| Rails.logger.info "serp check skipped: #{reason}" }
            on(:capped) { Rails.logger.warn "serp check skipped, the monthly ceiling is reached" }
            on(:rate_limited) { |message| Rails.logger.warn "serp check hit a quota: #{message}" }
            on(:failed) { |message| Rails.logger.warn "serp check failed for #{keyword.query}: #{message}" }
          end
        end
      end
    end
  end
end
