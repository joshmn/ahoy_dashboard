module AhoyDashboard
  class Decorator
    delegate_missing_to :@object

    # delegate_missing_to can't catch to_param: ActiveSupport defines it on
    # Object (as to_s), so it's never "missing", and url helpers given a
    # decorated record build hrefs from the decorator's inspect string.
    # to_model and to_partial_path ride along so form and render helpers treat
    # the decorator as the record.
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
  end
end
