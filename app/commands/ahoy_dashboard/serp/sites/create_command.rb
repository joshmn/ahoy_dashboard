module AhoyDashboard
  module Serp
    module Sites
      class CreateCommand < AhoyDashboard::Command
        Outcome = Data.define(:site, :attached, :backfilled)

        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          site = SerpSite.new(form.record_attributes)
          return broadcast(:invalid, form.copy_errors_from(site)) unless site.save

          broadcast(:ok, Outcome.new(site: site, **attach_everywhere(site)))
        rescue ActiveRecord::RecordNotUnique
          form.add_duplicate_error
          broadcast(:invalid, form)
        end

        private

        attr_reader :form

        def attach_everywhere(site)
          attached = 0
          backfilled = 0
          return { attached: attached, backfilled: backfilled } unless form.every_keyword

          SerpKeyword.find_each do |keyword|
            Sites::AttachCommand.call(keyword: keyword, site: site) do
              on(:ok) do |outcome|
                attached += 1
                backfilled += outcome.backfilled
              end
            end
          end

          { attached: attached, backfilled: backfilled }
        end
      end
    end
  end
end
