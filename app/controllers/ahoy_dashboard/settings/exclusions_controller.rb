module AhoyDashboard
  module Settings
    class ExclusionsController < AhoyDashboard::Settings::BaseController
      before_action :set_exclusion, only: [ :edit, :update, :destroy ]

      def index
        @exclusions = AhoyDashboard::ExclusionDecorator.wrap(AhoyDashboard::Exclusion.listed)
        counts = AhoyDashboard::ExclusionCountsQuery.call(
          filters: @exclusions.map { |exclusion| exclusion.to_blocks if exclusion.readable? }
        )
        @exclusions.zip(counts).each { |exclusion, count| exclusion.hidden_count = count }
      end

      def new
        @form = AhoyDashboard::ExclusionForm.from_blocks(AhoyDashboard::FilterBlocks.from_params(params))
        preview
      end

      def create
        @form = AhoyDashboard::ExclusionForm.new(exclusion_params)
        return redraw(:new) if removing?

        AhoyDashboard::Records::SaveCommand.call(record: AhoyDashboard::Exclusion.new, form: @form) do
          on(:ok) { redirect_to settings_exclusions_path, notice: "Exclusion saved." }
          on(:invalid) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::ExclusionForm.from_record(@exclusion)
        preview
      end

      def update
        @form = AhoyDashboard::ExclusionForm.new(exclusion_params)
        return redraw(:edit) if removing?

        AhoyDashboard::Records::SaveCommand.call(record: @exclusion, form: @form) do
          on(:ok) { redirect_to settings_exclusions_path, notice: "Exclusion saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      def destroy
        AhoyDashboard::Records::DestroyCommand.call(record: @exclusion) do
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

      def rejected(form, template = :edit)
        @form = form
        preview
        super
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
