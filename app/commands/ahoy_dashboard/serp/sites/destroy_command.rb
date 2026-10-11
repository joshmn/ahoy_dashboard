module AhoyDashboard
  module Serp
    module Sites
      class DestroyCommand < AhoyDashboard::Command
        def initialize(site:)
          @site = site
        end

        def call
          site.destroy!

          broadcast(:ok, site)
        end

        private

        attr_reader :site
      end
    end
  end
end
