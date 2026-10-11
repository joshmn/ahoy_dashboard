module AhoyDashboard
  module Serp
    module Keywords
      class DestroyCommand < AhoyDashboard::Command
        def initialize(keyword:)
          @keyword = keyword
        end

        def call
          keyword.destroy!

          broadcast(:ok, keyword)
        end

        private

        attr_reader :keyword
      end
    end
  end
end
