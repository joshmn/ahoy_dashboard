module AhoyDashboard
  module Assistant
    class ReplyJob < AhoyDashboard::Job
      queue_as :default

      def perform(message_id)
        return unless Assistant.installed?

        message = ChatMessage.find_by(id: message_id)
        return if message.nil?

        ReplyCommand.call(message: message) do
          on(:failed) { |reason| Rails.logger.warn "dashboard assistant reply failed: #{reason}" }
          on(:unavailable) { |reason| Rails.logger.info "dashboard assistant unavailable: #{reason}" }
          on(:refused) { |category| Rails.logger.info "dashboard assistant refused: #{category || "no category"}" }
        end
      end
    end
  end
end
