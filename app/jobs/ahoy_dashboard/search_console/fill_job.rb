module AhoyDashboard
  module SearchConsole
    # Works through the queue a day at a time until it empties or Google stops
    # answering. Started by the button on the settings screen and by nothing
    # else: it is the one piece of this that somebody has to ask for, because
    # nothing in the stored data can tell a hole from a quiet day.
    #
    # Sequential on purpose. Three requests a day against a quota measured in
    # thousands is nothing, and the reason to take them one after another is that
    # a fill must never be the thing that uses up the quota the nightly run needs.
    #
    # It re-reads the queue every day rather than holding the list it started
    # with, so two of these running at once converge on an empty queue instead of
    # writing each other's days back.
    class FillJob < AhoyDashboard::Job
      queue_as :low

      self.schedule_key = "search_console_fill"

      def perform
        return unless SearchConsole.enabled?

        account = GoogleAccount.current
        return unless account&.ready?

        loop { break unless fill(account) }
      end

      private

      def fill(account)
        carry_on = false

        FillCommand.call(account: account) do
          on(:ok) do |result|
            Rails.logger.info "search console fill stored #{result.date}, #{result.remaining} days left"
            carry_on = result.more?
          end
          on(:done) { |reason| Rails.logger.info "search console fill stopped: #{reason}" }
          on(:skipped) { |reason| Rails.logger.info "search console fill skipped: #{reason}" }
          on(:rate_limited) { |message| Rails.logger.warn "search console fill hit a quota: #{message}" }
          on(:failed) { |message| Rails.logger.warn "search console fill failed: #{message}" }
        end

        carry_on
      end
    end
  end
end
