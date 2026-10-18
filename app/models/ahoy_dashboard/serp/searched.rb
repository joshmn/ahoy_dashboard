module AhoyDashboard
  module Serp
    module Searched
      extend ActiveSupport::Concern

      include Placed

      included do
        scope :for_tag, ->(tag) { tag.present? ? where(keyword_id: SerpKeyword.tagged(tag).select(:id)) : all }
        scope :at_current_places, -> {
          where("exists (select 1 from #{SerpKeyword.table_name} current_keyword " \
                "where current_keyword.id = #{table_name}.keyword_id " \
                "and current_keyword.locations @> jsonb_build_array(#{table_name}.location))")
        }
        scope :latest_per_search, -> {
          select("distinct on (keyword_id, location) #{table_name}.*")
            .reorder(Arel.sql("keyword_id, location, checked_at desc, id desc"))
        }
      end
    end
  end
end
