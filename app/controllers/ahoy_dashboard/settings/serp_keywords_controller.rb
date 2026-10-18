module AhoyDashboard
  module Settings
    class SerpKeywordsController < AhoyDashboard::Settings::BaseController
      requires_installed :serp

      before_action :set_keyword, only: [ :edit, :update, :destroy ]
      before_action :set_check, only: [ :edit, :update ]

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
        @check_all = AhoyDashboard::Serp::CheckNowPresenter.new(listed: @keywords)
      end

      def new
        @form = AhoyDashboard::Serp::KeywordForm.new(
          site_ids: AhoyDashboard::Serp::KeywordForm.default_site_ids, query: params[:query].to_s.strip.presence
        )
        @plan = plan_for(@form, suggestions: suggestions)
      end

      def create
        @form = AhoyDashboard::Serp::KeywordForm.new(keyword_params)

        AhoyDashboard::Serp::Keywords::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to return_path || settings_serp_keywords_path, notice: "Keyword saved." }
          on(:invalid) { |form| rejected(form, :new) }
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
          on(:invalid) { |form| rejected(form) }
        end
      end

      def destroy
        AhoyDashboard::Records::DestroyCommand.call(record: @keyword) do
          on(:ok) do |keyword|
            redirect_to settings_serp_keywords_path,
              notice: "#{keyword.query} is no longer tracked, and its history is gone with it."
          end
        end
      end

      private

      def return_path
        local_path(params[:return_to])
      end

      def set_keyword
        @keyword = AhoyDashboard::SerpKeyword.find(params[:id])
      end

      def set_check
        @check = AhoyDashboard::Serp::CheckNowPresenter.new(keyword: @keyword)
      end

      def saved(outcome)
        parts = [ "Keyword saved." ]
        if outcome.archived
          parts << "Its history starts over. The old readings are kept on a paused keyword, " \
                   "#{outcome.archived.query} (#{AhoyDashboard::SerpKeywordDecorator.new(outcome.archived).search_label})."
        end
        parts << "#{read_again(outcome.backfilled)} for the site you attached." if outcome.backfilled.positive?

        parts.join(" ")
      end

      def rejected(form, template = :edit)
        @plan = plan_for(form, suggestions: template == :new ? suggestions : [])
        super
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
