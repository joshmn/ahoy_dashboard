module AhoyDashboard
  module Visitors
    class VisitsController < AhoyDashboard::BaseController
      def show
        found = AhoyDashboard::Visitors::LookupQuery.call(params[:token])
        path = AhoyDashboard::Visitors::Destination.new(found: found, query: query, routes: self).path if found&.visit?
        raise ActiveRecord::RecordNotFound if path.nil?

        redirect_to path
      end
    end
  end
end
