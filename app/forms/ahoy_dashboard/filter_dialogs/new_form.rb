# frozen_string_literal: true

module AhoyDashboard

  module FilterDialogs

    class NewForm
      attr_reader :category, :carried, :return_to

      def initialize(query:, category:, edit: nil, return_to: nil, carried: {})
        @query = query
        @category = FilterCategory.find_by_key(category) || FilterCategory.default
        @edit = edit
        @return_to = return_to
        @carried = carried.symbolize_keys.reject { |_key, value| value.blank? }
      end

      def dimensions
        @dimensions ||= category.dimensions
      end

      def edit_index
        edit if editing
      end

      def editing
        return @editing if defined?(@editing)
        return unless edit

        filter = query.filters[edit]
        @editing = filter && dimensions.any? { |dimension| dimension.key == filter.dimension.key } ? filter : nil
      end

      def group_number
        return unless editing

        group = query.filters.group_at(edit_index)
        return if group.single?

        query.filters.groups.index { |candidate| candidate.equal?(group) }
      end

      private

      attr_reader :query, :edit
    end
  end
end
