module AhoyDashboard
  module Seo
    class BrandTerms
      class SaveCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          list = form.list

          if list.empty?
            AhoyDashboard::Setting.clear(BrandTerms::KEY)
            return broadcast(:reset, BrandTerms.default)
          end

          AhoyDashboard::Setting.write(BrandTerms::KEY, list)
          broadcast(:ok, list)
        end

        private

        attr_reader :form
      end
    end
  end
end
