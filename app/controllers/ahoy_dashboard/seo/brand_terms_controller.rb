module AhoyDashboard
  module Seo
    class BrandTermsController < BaseController
      def update
        form = BrandTermsForm.new(terms: params.dig(:brand_terms, :terms))

        BrandTerms::SaveCommand.call(form: form) do
          on(:ok) { redirect_to back_path, notice: "Brand words saved." }
          on(:reset) { redirect_to back_path, notice: "Brand words cleared. The site's name is used until you add some." }
          on(:invalid) { redirect_to back_path, alert: "That list is too long to save." }
        end
      end

      private

      def back_path
        seo_brand_split_path(query.to_query.merge(slice.to_query))
      end

      def surface_key
        "brand_split"
      end
    end
  end
end
