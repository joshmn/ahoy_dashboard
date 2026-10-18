module AhoyDashboard
  module Assistant
    ModelOption = Data.define(:id, :label) do
      class << self
        def listed(ids)
          ids.map { |id| new(id: id, label: nil) }
        end
      end
    end
  end
end
