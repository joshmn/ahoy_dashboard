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
          return copy_errors(keyword) unless keyword.save

          attach(keyword)
          broadcast(:ok, keyword)
        rescue ActiveRecord::RecordNotUnique
          form.errors.add(:base, KeywordForm::DUPLICATE_MESSAGE)
          broadcast(:duplicate, form)
        end

        private

        attr_reader :form

        def attach(keyword)
          SerpSite.where(id: form.chosen_site_ids).find_each do |site|
            Sites::AttachCommand.call(keyword: keyword, site: site, backfill: false)
          end
        end

        def copy_errors(keyword)
          keyword.errors.messages.each do |attribute, messages|
            messages.each { |message| form.errors.add(attribute, message) }
          end

          broadcast(:invalid, form)
        end
      end
    end
  end
end
