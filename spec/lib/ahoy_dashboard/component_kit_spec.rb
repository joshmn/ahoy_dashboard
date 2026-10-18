require "rails_helper"

RSpec.describe "Dashboard component kit" do
  before(:context) do
    mode = ENV["AHOY_KIT_BASELINE"]
    AhoyDashboardComponentKit.update_baseline!(mode) if %w[create lower].include?(mode)
  end

  {
    "retired" => "a class the component kit replaced",
    "bootstrap" => "Bootstrap component markup written outside the component helpers",
    "stylesheet" => "a colour or radius literal outside the theme and tokens files"
  }.each do |kind, what|
    describe kind do
      it "gains no new use of #{what}" do
        grown, = AhoyDashboardComponentKit.compare(kind)

        expect(grown).to be_empty, <<~MESSAGE
          Use the component helpers instead of #{what}:
          #{grown.join("\n")}
        MESSAGE
      end

      it "has a baseline no higher than what is left" do
        _, stale = AhoyDashboardComponentKit.compare(kind)

        expect(stale).to be_empty, <<~MESSAGE
          These went down. Lower the baseline with AHOY_KIT_BASELINE=lower:
          #{stale.join("\n")}
        MESSAGE
      end
    end
  end
end
