require "rails_helper"

RSpec.describe AhoyDashboard::Serp::SearchFields do
  [ AhoyDashboard::Serp::KeywordForm, AhoyDashboard::Serp::KeywordImportForm ].each do |form_class|
    describe "on #{form_class.name.demodulize}" do
      let(:form) { form_class.new }

      it "offers every device the search reads" do
        expect(form.device_options).to eq(%w[desktop mobile tablet])
      end

      it "offers every cadence with its label" do
        expect(form.frequency_options).to eq([
          %w[daily Daily], %w[weekly Weekly], [ "biweekly", "Every 2 weeks" ], %w[monthly Monthly]
        ])
      end

      it "offers each depth up to the deepest, counted in results" do
        expect(form.page_options).to eq([
          [ 1, "Top 10" ], [ 2, "Top 20" ], [ 3, "Top 30" ], [ 4, "Top 40" ], [ 5, "Top 50" ]
        ])
      end
    end
  end
end
