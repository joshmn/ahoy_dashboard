module AhoyDashboard
  class Decorator
    DATE = "%-d %b".freeze

    delegate_missing_to :@object

    delegate :to_param, :to_model, :to_partial_path, to: :@object

    def initialize(object)
      @object = object
    end

    def self.wrap(collection)
      collection.map { |object| new(object) }
    end

    def object
      @object
    end

    def dates
      return "Created #{on(created_at)}" if created_at.to_i == updated_at.to_i

      "Created #{on(created_at)}, last updated #{on(updated_at)}"
    end

    private

    def on(time)
      time.in_time_zone(AhoyDashboard.time_zone).strftime(DATE)
    end
  end
end
