# frozen_string_literal: true

module AhoyDashboard
  class Query
    class << self
      def call(*args, **kwargs)
        (kwargs.empty? ? new(*args) : new(*args, **kwargs)).call
      end
    end
  end
end
