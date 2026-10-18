module AhoyDashboard
  module Settings
    class BaseController < AhoyDashboard::BaseController
      helper_method :confirming?

      private

      def rejected(form, template = :edit)
        @form = form
        render template, status: 422
      end

      def confirming?(record)
        params[:confirm] == record.id.to_s
      end

      def read_again(count)
        "#{helpers.pluralize(count, 'past search')} #{count == 1 ? 'was' : 'were'} read again"
      end
    end
  end
end
