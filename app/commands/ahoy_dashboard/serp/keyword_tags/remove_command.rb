module AhoyDashboard
  module Serp
    module KeywordTags
      class RemoveCommand < AhoyDashboard::Command
        Outcome = Data.define(:tags, :changed)

        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          unwanted = form.tag_list.map(&:downcase)
          changed = 0

          SerpKeyword.where(id: form.chosen_keyword_ids).find_each do |keyword|
            kept = keyword.tags.reject { |tag| unwanted.include?(tag.downcase) }
            next if kept == keyword.tags

            keyword.update_columns(tags: kept, updated_at: Time.current)
            changed += 1
          end

          broadcast(:ok, Outcome.new(tags: form.tag_list, changed: changed))
        end

        private

        attr_reader :form
      end
    end
  end
end
