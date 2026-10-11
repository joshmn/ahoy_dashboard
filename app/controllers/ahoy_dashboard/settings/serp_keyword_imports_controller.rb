module AhoyDashboard
  module Settings
    class SerpKeywordImportsController < AhoyDashboard::BaseController
      requires_installed :serp

      before_action :set_sites
      before_action :set_batch
      before_action :set_candidates

      # More than fits on a screen on purpose. The list is searched and sorted
      # in the browser, so what it costs to send another hundred rows is a
      # hundred rows of HTML, and what it buys is the query somebody is actually
      # looking for being on the page at all.
      CANDIDATES = 150

      helper_method :return_path

      def new
        return redirect_to(return_path || settings_serp_keywords_path, alert: "Tick at least one search to track.") if @batch && @picked.empty?

        @form = AhoyDashboard::Serp::KeywordImportForm.new(site_ids: default_site_ids, selected: @picked)
        @plan = plan_for(@form)
      end

      def create
        @form = AhoyDashboard::Serp::KeywordImportForm.new(import_params)

        AhoyDashboard::Serp::Keywords::ImportCommand.call(form: @form) do
          on(:ok) { |outcome| redirect_to return_path || settings_serp_keywords_path, notice: report(outcome) }
          on(:invalid) do |form|
            @form = form
            @plan = plan_for(form)
            render :new, status: :unprocessable_entity
          end
        end
      end

      private

      def plan_for(form)
        AhoyDashboard::Settings::KeywordPlanPresenter.new(form: form)
      end

      def set_sites
        @sites = AhoyDashboard::SerpSite.ordered.to_a
      end

      def set_batch
        @batch = params[:batch].present?
        @picked = @batch ? untracked(params[:track]) : []
      end

      def set_candidates
        @candidates = @batch ? [] : AhoyDashboard::Serp::ImportCandidatesQuery.call(limit: CANDIDATES)
      end

      def untracked(queries)
        phrases = Array(queries)
          .map { |query| query.to_s.strip.squeeze(" ") }
          .reject(&:blank?)
          .uniq(&:downcase)
        tracked = AhoyDashboard::TrackedKeywordsQuery.call(phrases: phrases).map { |keyword| keyword.query.downcase }

        phrases.reject { |phrase| tracked.include?(phrase.downcase) }
          .first(AhoyDashboard::Serp::KeywordImportForm::MAX_QUERIES)
      end

      def return_path
        value = params[:return_to].to_s
        return nil unless value.start_with?("/") && !value.start_with?("//") && !value.include?("\\")

        value
      end

      def default_site_ids
        AhoyDashboard::SerpSite.ours ? [ AhoyDashboard::SerpSite.ours.id.to_s ] : []
      end

      def report(outcome)
        parts = [ "#{helpers.pluralize(outcome.created.size, 'keyword')} now tracked." ]
        parts << "#{outcome.existing.size} were already on the list." if outcome.existing.any?
        parts << "#{outcome.rejected.size} would not save." if outcome.rejected.any?

        parts.join(" ")
      end

      def import_params
        params.require(:serp_keyword_import)
          .permit(:pasted, :locations, :pages, :frequency, :device, :language, :engine, :tags,
                  selected: [], site_ids: [], place_countries: [], place_cities: [], tags: [])
      end
    end
  end
end
