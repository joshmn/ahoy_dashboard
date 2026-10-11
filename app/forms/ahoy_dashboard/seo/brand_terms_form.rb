module AhoyDashboard
  module Seo
    class BrandTermsForm < AhoyDashboard::Form
      MAX_INPUT = 2_000

      attribute :terms, :string

      validates :terms, length: { maximum: MAX_INPUT }

      def list
        AhoyDashboard::Seo::BrandTerms.parse(terms)
      end
    end
  end
end
