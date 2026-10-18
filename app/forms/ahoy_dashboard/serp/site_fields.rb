module AhoyDashboard
  module Serp
    module SiteFields
      extend ActiveSupport::Concern

      included do
        attribute :site_ids
      end

      class_methods do
        def default_site_ids
          own = SerpSite.ours
          own ? [ own.id.to_s ] : []
        end
      end

      def chosen_site_ids
        Array(site_ids).reject(&:blank?).map(&:to_i)
      end

      def site_options
        @site_options ||= SerpSite.ordered.to_a
      end
    end
  end
end
