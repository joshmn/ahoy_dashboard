module AhoyDashboard
  module Rankings
    class TagsController < AhoyDashboard::BaseController
      requires_installed :serp

      def create
        AhoyDashboard::Serp::KeywordTags::AddCommand.call(form: form) do
          on(:ok) { |outcome| redirect_to back_path, notice: added(outcome) }
          on(:invalid) { |form| redirect_to back_path, alert: form.errors.full_messages.to_sentence }
        end
      end

      def destroy
        AhoyDashboard::Serp::KeywordTags::RemoveCommand.call(form: form) do
          on(:ok) { |outcome| redirect_to back_path, notice: removed(outcome) }
          on(:invalid) { |form| redirect_to back_path, alert: form.errors.full_messages.to_sentence }
        end
      end

      private

      def form
        AhoyDashboard::Serp::KeywordTagForm.new(tag_params)
      end

      def added(outcome)
        named = outcome.tags.to_sentence
        return "Every ticked keyword already has #{named}." if outcome.changed.zero? && outcome.full.zero?

        parts = []
        parts << "Added #{named} to #{helpers.pluralize(outcome.changed, 'keyword')}." if outcome.changed.positive?
        if outcome.full.positive?
          parts << "#{helpers.pluralize(outcome.full, 'keyword')} already #{outcome.full == 1 ? 'has' : 'have'} " \
                   "#{AhoyDashboard::SerpKeyword::MAX_TAGS} tags and #{outcome.full == 1 ? 'was' : 'were'} left alone."
        end

        parts.join(" ")
      end

      def removed(outcome)
        named = outcome.tags.to_sentence
        return "None of the ticked keywords had #{named}." if outcome.changed.zero?

        "Took #{named} off #{helpers.pluralize(outcome.changed, 'keyword')}."
      end

      def back_path
        value = params[:return_to].to_s
        return rankings_path unless value.start_with?("/") && !value.start_with?("//") && !value.include?("\\")

        value
      end

      def tag_params
        params.fetch(:keyword_tag, {}).permit(:tag, keyword_ids: [])
      end
    end
  end
end
