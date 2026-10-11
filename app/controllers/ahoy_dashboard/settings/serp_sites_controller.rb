module AhoyDashboard
  module Settings
    class SerpSitesController < AhoyDashboard::BaseController
      requires_installed :serp

      before_action :set_site, only: [ :edit, :update, :destroy ]

      def index
        @sites = AhoyDashboard::SerpSite.ordered.to_a
        @keyword_counts = AhoyDashboard::SerpKeywordTarget.where(site_id: @sites.map(&:id)).group(:site_id).count
        @confirming = params[:confirm].presence
      end

      def new
        @form = AhoyDashboard::Serp::SiteForm.new(domain: (AhoyDashboard::Serp.own_domain unless AhoyDashboard::SerpSite.ours))
      end

      def create
        @form = AhoyDashboard::Serp::SiteForm.new(site_params(AhoyDashboard::Serp::SiteForm::NEW_FIELDS))

        AhoyDashboard::Serp::Sites::CreateCommand.call(form: @form) do
          on(:ok) { |outcome| redirect_to settings_serp_sites_path, notice: created(outcome) }
          on(:invalid) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::Serp::SiteForm.from_record(@site)
      end

      def update
        @form = AhoyDashboard::Serp::SiteForm.new(site_params)

        AhoyDashboard::Serp::Sites::UpdateCommand.call(site: @site, form: @form) do
          on(:ok) { redirect_to settings_serp_sites_path, notice: "Site saved." }
          on(:invalid) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::Serp::Sites::DestroyCommand.call(site: @site) do
          on(:ok) do |site|
            redirect_to settings_serp_sites_path,
              notice: "#{site.name} is off the list, and so is everything that was recorded about it."
          end
        end
      end

      private

      def set_site
        @site = AhoyDashboard::SerpSite.find(params[:id])
      end

      def rejected(form, template)
        @form = form
        render template, status: :unprocessable_entity
      end

      def created(outcome)
        return "Site saved." if outcome.attached.zero?

        helpers = ActionController::Base.helpers
        notice = "Site saved and added to #{helpers.pluralize(outcome.attached, 'keyword')}."
        return notice if outcome.backfilled.zero?

        "#{notice} #{helpers.pluralize(outcome.backfilled, 'past search')} " \
          "#{outcome.backfilled == 1 ? 'was' : 'were'} read again for it."
      end

      def site_params(fields = AhoyDashboard::Serp::SiteForm::FIELDS)
        params.require(:serp_site).permit(*fields)
      end
    end
  end
end
