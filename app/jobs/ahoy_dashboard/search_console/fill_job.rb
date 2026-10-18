module AhoyDashboard
  module SearchConsole
    class FillJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "search_console_fill"

      def perform
        loop { break unless fill }
      end

      private

      def fill
        carry_on = false

        FillCommand.call do
          on(:ok) do |result|
            Rails.logger.info "search console fill stored #{result.date}, #{result.remaining} days left"
            carry_on = result.more?
          end
          on(:done) { |reason| Rails.logger.info "search console fill stopped: #{reason}" }
          on(:skipped) { |reason| Rails.logger.info "search console fill skipped: #{reason}" }
          on(:rate_limited) { |message| Rails.logger.warn "search console fill hit a quota: #{message}" }
          on(:failed) do |message|
            Rails.logger.warn "search console fill failed: #{message}"
            raise Failed, message
          end
        end

        carry_on
      end
    end
  end
end
