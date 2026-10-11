module AhoyDashboard
  module Settings
    class SerpKeywordsController < AhoyDashboard::BaseController
      requires_installed :serp

      before_action :set_keyword, only: [ :edit, :update, :destroy ]
      before_action :set_sites, only: [ :new, :create, :edit, :update ]

      SUGGESTIONS = 8

      helper_method :return_path

      def index
        @keywords = AhoyDashboard::SerpKeywordDecorator.wrap(AhoyDashboard::SerpKeyword.ordered.to_a)
        @site_counts = AhoyDashboard::SerpKeywordTarget.where(keyword_id: @keywords.map(&:id)).group(:keyword_id).count
        @latest = AhoyDashboard::Serp::LatestChecksQuery.call(
          keyword_ids: @keywords.map(&:id), site: AhoyDashboard::SerpSite.ours
        )
        @provider_notice = AhoyDashboard::Settings::SerpProviderStatus.notice
        @adapter = AhoyDashboard::Serp.adapter_class
        @spend = AhoyDashboard::Serp::SpendPresenter.new
        @confirming = params[:confirm].presence
      end

      def new
        @form = AhoyDashboard::Serp::KeywordForm.new(site_ids: default_site_ids, query: params[:query].to_s.strip.presence)
        @plan = plan_for(@form, suggestions: suggestions)
      end

      def create
        @form = AhoyDashboard::Serp::KeywordForm.new(keyword_params)

        AhoyDashboard::Serp::Keywords::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to return_path || settings_serp_keywords_path, notice: "Keyword saved." }
          on(:invalid) { |form| rejected(form, :new) }
          on(:duplicate) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::Serp::KeywordForm.from_record(@keyword)
        @plan = plan_for(@form)
      end

      def update
        @form = AhoyDashboard::Serp::KeywordForm.new(keyword_params)

        AhoyDashboard::Serp::Keywords::UpdateCommand.call(keyword: @keyword, form: @form) do
          on(:ok) { |outcome| redirect_to settings_serp_keywords_path, notice: saved(outcome) }
          on(:invalid) { |form| rejected(form, :edit) }
          on(:duplicate) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::Serp::Keywords::DestroyCommand.call(keyword: @keyword) do
          on(:ok) do |keyword|
            redirect_to settings_serp_keywords_path,
              notice: "#{keyword.query} is no longer tracked, and its history is gone with it."
          end
        end
      end

      private

      def return_path
        value = params[:return_to].to_s
        return nil unless value.start_with?("/") && !value.start_with?("//") && !value.include?("\\")

        value
      end

      def set_keyword
        @keyword = AhoyDashboard::SerpKeyword.find(params[:id])
      end

      def set_sites
        @sites = AhoyDashboard::SerpSite.ordered.to_a
      end

      def default_site_ids
        AhoyDashboard::SerpSite.ours ? [ AhoyDashboard::SerpSite.ours.id.to_s ] : []
      end

      def saved(outcome)
        parts = [ "Keyword saved." ]
        if outcome.archived
          parts << "Its history starts over. The old readings are kept on a paused keyword, " \
                   "#{outcome.archived.query} (#{AhoyDashboard::SerpKeywordDecorator.new(outcome.archived).search_label})."
        end
        if outcome.backfilled.positive?
          parts << "#{ActionController::Base.helpers.pluralize(outcome.backfilled, 'past search')} " \
                   "#{outcome.backfilled == 1 ? 'was' : 'were'} read again for the site you attached."
        end

        parts.join(" ")
      end

      def rejected(form, template)
        @form = form
        @plan = plan_for(form, suggestions: template == :new ? suggestions : [])
        render template, status: :unprocessable_entity
      end

      def plan_for(form, suggestions: [])
        AhoyDashboard::Settings::KeywordPlanPresenter.new(form: form, suggestions: suggestions)
      end

      def suggestions
        AhoyDashboard::Serp::ImportCandidatesQuery.call(limit: SUGGESTIONS)
      end

      def keyword_params
        params.require(:serp_keyword)
          .permit(:query, :engine, :device, :language, :locations, :pages, :frequency, :enabled, :tags,
                  site_ids: [], place_countries: [], place_cities: [], tags: [])
      end
    end
  end
end
