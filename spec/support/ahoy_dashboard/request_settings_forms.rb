module AhoyDashboardRequestSettingsForms
  def stored_settings
    AhoyDashboard::Setting.order(:key).pluck(:key, :value)
  end

  def field(id)
    document.at_css("##{id}")
  end

  def refusal(path, params)
    expect { patch path, params: params }.not_to(change { stored_settings })

    expect(response).to have_http_status(:unprocessable_entity)
    document.at_css("[role='alert']").text.squish
  end

  def expect_labelled_fields(ids, within: document)
    ids.each do |id|
      expect(within.at_css("label[for='#{id}']")).to be_present, "expected a label for #{id}"
      expect(field(id)["aria-describedby"]).to include("#{id}_hint")
    end
  end
end

RSpec.configure { |config| config.include AhoyDashboardRequestSettingsForms, type: :request }
