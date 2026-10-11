module AhoyDashboard
  module Serp
    module KeywordTags
      class AddCommand < AhoyDashboard::Command
        Outcome = Data.define(:tags, :changed, :full)

        def initialize(form:)
          @form = form
        end

        def call
          return broadcast(:invalid, form) if form.invalid?

          changed = 0
          full = 0

          SerpKeyword.where(id: form.chosen_keyword_ids).find_each do |keyword|
            wanted = SerpKeyword.clean_tags(keyword.tags + form.tag_list)
            next if wanted == keyword.tags

            keyword.update(tags: wanted) ? changed += 1 : full += 1
          end

          broadcast(:ok, Outcome.new(tags: form.tag_list, changed: changed, full: full))
        end

        private

        attr_reader :form
      end
    end
  end
end
