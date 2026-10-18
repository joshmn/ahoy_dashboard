# frozen_string_literal: true

module AhoyDashboard

  module FilterDialogs

    class NewPresenter
      delegate :category, :dimensions, :editing, :edit_index, :group_number, :carried, to: :form

      def initialize(query:, form:, options:, routes:)
        @query = query
        @form = form
        @options = options
        @routes = routes
      end

      def destination
        routes.public_send(destination_route)
      end

      def cancel
        routes.public_send(destination_route, query.to_query.merge(carried))
      end

      def options_url
        routes.filter_options_path(query.to_query.merge(format: :json, edit: edit_index))
      end

      def options_for(dimension)
        options.fetch(dimension.key, [])
      end

      def editing_for(dimension)
        filter = editing
        filter if filter && filter.dimension && filter.dimension.key == dimension.key
      end

      private

      attr_reader :query, :form, :options, :routes

      def destination_route
        FilterDestination.route(form.return_to)
      end
    end
  end
end
