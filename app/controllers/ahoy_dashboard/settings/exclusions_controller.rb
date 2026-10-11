module AhoyDashboard
  module Settings
    class ExclusionsController < AhoyDashboard::BaseController
      before_action :set_exclusion, only: [ :edit, :update, :destroy ]

      def index
        @exclusions = AhoyDashboard::ExclusionDecorator.wrap(AhoyDashboard::Exclusion.listed)
        counts = AhoyDashboard::ExclusionCountsQuery.call(
          filters: @exclusions.map { |exclusion| exclusion.to_blocks if exclusion.readable? }
        )
        @exclusions.zip(counts).each { |exclusion, count| exclusion.hidden_count = count }
        @confirming = params[:confirm].presence
      end

      def new
        @form = AhoyDashboard::ExclusionForm.from_blocks(AhoyDashboard::FilterBlocks.from_params(params))
        preview
      end

      def create
        @form = AhoyDashboard::ExclusionForm.new(exclusion_params)
        return redraw(:new) if removing?

        AhoyDashboard::Exclusions::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to settings_exclusions_path, notice: "Exclusion saved." }
          on(:invalid) { |form| rejected(form, :new) }
          on(:duplicate) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::ExclusionForm.from_record(@exclusion)
        preview
      end

      def update
        @form = AhoyDashboard::ExclusionForm.new(exclusion_params)
        return redraw(:edit) if removing?

        AhoyDashboard::Exclusions::UpdateCommand.call(exclusion: @exclusion, form: @form) do
          on(:ok) { redirect_to settings_exclusions_path, notice: "Exclusion saved." }
          on(:invalid) { |form| rejected(form, :edit) }
          on(:duplicate) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::Exclusions::DestroyCommand.call(exclusion: @exclusion) do
          on(:ok) { redirect_to settings_exclusions_path, notice: "Exclusion deleted." }
        end
      end

      private

      def set_exclusion
        @exclusion = AhoyDashboard::Exclusion.find(params[:id])
      end

      def removing?
        params.dig(:exclusion, :remove).present? || params.dig(:exclusion, :done).present?
      end

      def redraw(template)
        @form = @form.without_slot(params.dig(:exclusion, :remove))
        preview

        render template
      end

      def rejected(form, template)
        @form = form
        preview

        render template, status: :unprocessable_entity
      end

      def preview
        @preview = AhoyDashboard::ExclusionCountsQuery.call(filters: [ @form.to_blocks.presence ]).first
      end

      def exclusion_params
        params.require(:exclusion).permit(*AhoyDashboard::ExclusionForm::FIELDS, **AhoyDashboard::ExclusionForm::FILTERS_FIELD)
      end
    end
  end
end
