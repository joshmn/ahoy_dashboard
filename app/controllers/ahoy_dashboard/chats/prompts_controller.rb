module AhoyDashboard
  module Chats
    class PromptsController < AhoyDashboard::BaseController
      requires_installed :assistant, :ai_visibility

      def create
        chat = AhoyDashboard::ChatDecorator.new(AhoyDashboard::Chat.find(params[:chat_id]))
        form = AhoyDashboard::AiVisibility::PromptAppendForm.from_params(params.fetch(:prompts, {}))

        AhoyDashboard::AiVisibility::Prompts::AppendCommand.call(form: form) do
          on(:ok) { |added| added_to(chat, added) }
          on(:invalid) { |invalid| refused(chat, invalid) }
        end
      end

      private

      def required_permission
        :manage
      end

      def added_to(chat, added)
        return redirect_to(chat_path(chat, view: ChatsController::THREAD_VIEW), status: :see_other) if frame_request?

        redirect_to chat_path(chat), notice: added_notice(added)
      end

      def refused(chat, form)
        message = form.errors.full_messages.to_sentence
        return redirect_to(chat_path(chat), alert: message) unless frame_request?

        render partial: "ahoy_dashboard/chats/thread", locals: { chat: chat, prompt_error: message },
               status: 422
      end

      def added_notice(added)
        return "Those prompts were already tracked." if added.empty?

        "#{helpers.pluralize(added.size, "prompt")} added to AI visibility."
      end
    end
  end
end
