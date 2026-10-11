module AhoyDashboard
  module Serp
    module Sites
      class UpdateCommand < AhoyDashboard::Command
        def initialize(site:, form:)
          @site = site
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          site.assign_attributes(form.record_attributes)
          return copy_errors unless site.save

          broadcast(:ok, site)
        rescue ActiveRecord::RecordNotUnique
          form.errors.add(:domain, "is already on the list")
          broadcast(:invalid, form)
        end

        private

        attr_reader :site, :form

        def copy_errors
          site.errors.messages.each do |attribute, messages|
            messages.each { |message| form.errors.add(attribute, message) }
          end

          broadcast(:invalid, form)
        end
      end
    end
  end
end
