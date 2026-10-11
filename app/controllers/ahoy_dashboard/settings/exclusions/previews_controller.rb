module AhoyDashboard
  module Settings
    module Exclusions
      class PreviewsController < AhoyDashboard::BaseController
        FRAME = "dash_exclusion_preview".freeze

        def show
          @form = AhoyDashboard::ExclusionForm.new(preview_params)
          filters = @form.usable? ? @form.to_blocks.presence : nil
          @preview = AhoyDashboard::ExclusionCountsQuery.call(filters: [ filters ]).first
        end

        private

        def preview_params
          params.fetch(:exclusion, {}).permit(**AhoyDashboard::ExclusionForm::FILTERS_FIELD)
        end
      end
    end
  end
end
