module AhoyDashboard
  module Visitors
    class LookupsController < AhoyDashboard::BaseController
      def show
        found = AhoyDashboard::Visitors::LookupQuery.call(params[:q])
        path = AhoyDashboard::Visitors::Destination.new(found: found, query: query, routes: self).path if found

        if path
          redirect_to path
        else
          redirect_to visitors_path(query.to_query), alert: "Nothing matches that visitor, visit or user."
        end
      end
    end
  end
end
