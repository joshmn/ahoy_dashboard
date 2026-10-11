module AhoyDashboard
  module Serp
    module TagFields
      extend ActiveSupport::Concern

      included do
        attribute :tags

        validate :tags_are_usable
      end

      def tag_list
        @tag_list ||= SerpKeyword.canonical_tags(tags)
      end

      def tag_suggestions
        @tag_suggestions ||= SerpKeyword.tags_in_use
      end

      private

      def tags_are_usable
        values = SerpKeyword.clean_tags(tags)
        errors.add(:tags, "are more than #{SerpKeyword::MAX_TAGS}") if values.size > SerpKeyword::MAX_TAGS

        long = values.select { |tag| tag.length > SerpKeyword::MAX_TAG_LENGTH }
        return if long.empty?

        errors.add(:tags, "can be #{SerpKeyword::MAX_TAG_LENGTH} characters at most, and #{long.to_sentence} is longer")
      end
    end
  end
end
