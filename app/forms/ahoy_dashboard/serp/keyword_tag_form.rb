module AhoyDashboard
  module Serp
    class KeywordTagForm < AhoyDashboard::Form
      attribute :tag, :string
      attribute :keyword_ids

      validate :tag_is_usable
      validate :something_is_ticked

      def chosen_keyword_ids
        Array(keyword_ids).reject(&:blank?).map(&:to_i).uniq
      end

      def tag_list
        @tag_list ||= SerpKeyword.canonical_tags(tag)
      end

      private

      def tag_is_usable
        values = SerpKeyword.clean_tags(tag)
        return errors.add(:base, "Type a tag first.") if values.empty?

        long = values.select { |value| value.length > SerpKeyword::MAX_TAG_LENGTH }
        return if long.empty?

        errors.add(:base, "A tag can be #{SerpKeyword::MAX_TAG_LENGTH} characters at most, and #{long.to_sentence} is longer.")
      end

      def something_is_ticked
        errors.add(:base, "Tick at least one search first.") if chosen_keyword_ids.empty?
      end
    end
  end
end
