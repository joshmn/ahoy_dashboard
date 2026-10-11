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
          return copy_errors(site) unless site.save

          broadcast(:ok, Outcome.new(site: site, **attach_everywhere(site)))
        rescue ActiveRecord::RecordNotUnique
          form.errors.add(:domain, "is already on the list")
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

        def copy_errors(site)
          site.errors.messages.each do |attribute, messages|
            messages.each { |message| form.errors.add(attribute, message) }
          end

          broadcast(:invalid, form)
        end
      end
    end
  end
end
