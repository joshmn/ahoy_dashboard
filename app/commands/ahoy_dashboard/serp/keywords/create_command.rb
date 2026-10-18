module AhoyDashboard
  module Serp
    module Keywords
      class CreateCommand < AhoyDashboard::Command
        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          keyword = SerpKeyword.new(form.record_attributes)
          return broadcast(:invalid, form.copy_errors_from(keyword)) unless keyword.save

          attach(keyword)
          broadcast(:ok, keyword)
        rescue ActiveRecord::RecordNotUnique
          form.add_duplicate_error
          broadcast(:invalid, form)
        end

        private

        attr_reader :form

        def attach(keyword)
          SerpSite.where(id: form.chosen_site_ids).find_each do |site|
            Sites::AttachCommand.call(keyword: keyword, site: site, backfill: false)
          end
        end
      end
    end
  end
end
