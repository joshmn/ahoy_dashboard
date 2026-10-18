module DashboardDecorators
  def decorate(object)
    described_class.new(object)
  end
end

RSpec.configure { |config| config.include DashboardDecorators, type: :decorator }
