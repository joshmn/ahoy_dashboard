require "rails_helper"

RSpec.describe "Dashboard email settings", type: :request do
  def read(scope, name)
    AhoyDashboard::Preferences.read(scope, name)
  end

  let(:valid) do
    {
      alerts_digest: [ "", "daily", "monthly" ], alerts_recipients: "one@example.com\ntwo@example.com",
      alerts_from: "Alerts <alerts@example.com>", alerts_send_empty: "0",
      reports_digest: [ "", "weekly" ], reports_recipients: "three@example.com, four@example.com",
      reports_from: "reports@example.com"
    }
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "is listed in the settings nav" do
      get "/telemetry/settings/emails/edit"

      expect(response).to have_http_status(:ok)
      expect(document.css("a").map { |link| link["href"] }).to include("/telemetry/settings/emails/edit")
      expect(document.css("a").find { |link| link["href"] == "/telemetry/settings/emails/edit" }.text.squish).to eq("Emails")
    end

    it "labels every field" do
      get "/telemetry/settings/emails/edit"

      expect_labelled_fields(%w[emails_alerts_recipients emails_alerts_from emails_alerts_send_empty
                                emails_reports_recipients emails_reports_from])
      expect(document.css("fieldset legend").map { |legend| legend.text.squish }).to eq([ "How often", "How often" ])
      expect(document.css("input[type=checkbox][name='emails[alerts_digest][]']").map { |box| box["value"] })
        .to eq(%w[daily weekly monthly])
    end

    it "starts with nothing set up and sends when nothing fired" do
      get "/telemetry/settings/emails/edit"

      expect(document.css("input[type=checkbox][name$='_digest][]'][checked]")).to be_empty
      expect(field("emails_alerts_recipients").text.strip).to eq("")
      expect(field("emails_alerts_send_empty")["checked"]).to eq("checked")
    end

    it "shows what is stored" do
      AhoyDashboard::Preferences.write(:alerts, digest: [ :weekly ], recipients: [ "a@example.com" ], from: "x@example.com",
                                                send_empty: false)
      AhoyDashboard::Preferences.write(:reports, digest: [ :monthly ], recipients: [ "b@example.com", "c@example.com" ])

      get "/telemetry/settings/emails/edit"

      expect(document.css("input[name='emails[alerts_digest][]'][checked]").map { |box| box["value"] }).to eq([ "weekly" ])
      expect(document.css("input[name='emails[reports_digest][]'][checked]").map { |box| box["value"] }).to eq([ "monthly" ])
      expect(field("emails_alerts_recipients").text.strip).to eq("a@example.com")
      expect(field("emails_reports_recipients").text.split).to eq([ "b@example.com", "c@example.com" ])
      expect(field("emails_alerts_from")["value"]).to eq("x@example.com")
      expect(field("emails_alerts_send_empty")["checked"]).to be_nil
    end

    it "saves every field and the digests read them from then on" do
      patch "/telemetry/settings/emails", params: { emails: valid }

      expect(response).to redirect_to("/telemetry/settings/emails/edit")
      expect(AhoyDashboard::Alerts::Digests.periods).to eq(%i[daily monthly])
      expect(AhoyDashboard::Alerts::Digests.recipients).to eq([ "one@example.com", "two@example.com" ])
      expect(AhoyDashboard::Alerts::Digests.from).to eq("Alerts <alerts@example.com>")
      expect(AhoyDashboard::Alerts::Digests.send_empty?).to be(false)
      expect(AhoyDashboard::Reports::Digests.periods).to eq(%i[weekly])
      expect(AhoyDashboard::Reports::Digests.recipients).to eq([ "three@example.com", "four@example.com" ])
      expect(AhoyDashboard::Reports::Digests.from).to eq("reports@example.com")
    end

    it "goes back to the defaults when everything is cleared" do
      AhoyDashboard::Preferences.write(:alerts, digest: [ :weekly ], recipients: [ "a@example.com" ], from: "x@example.com",
                                                send_empty: false)
      AhoyDashboard::Preferences.write(:reports, digest: [ :monthly ], recipients: [ "b@example.com" ], from: "y@example.com")

      patch "/telemetry/settings/emails",
            params: { emails: { alerts_digest: [ "" ], alerts_recipients: "", alerts_from: "", alerts_send_empty: "1",
                                reports_digest: [ "" ], reports_recipients: "", reports_from: "" } }

      expect(response).to redirect_to("/telemetry/settings/emails/edit")
      expect(read(:alerts, :digest)).to eq([])
      expect(read(:alerts, :recipients)).to eq([])
      expect(AhoyDashboard::Preferences.stored?(:alerts, :from)).to be(false)
      expect(read(:alerts, :send_empty)).to be(true)
      expect(read(:reports, :digest)).to eq([])
      expect(read(:reports, :recipients)).to eq([])
      expect(AhoyDashboard::Preferences.stored?(:reports, :from)).to be(false)
    end

    describe "refusing" do
      def refused(**changes)
        refusal("/telemetry/settings/emails", emails: valid.merge(changes))
      end

      it "names the bad recipient" do
        expect(refused(alerts_recipients: "one@example.com\nnobody")).to include("Alert email recipients", %("nobody" is not an email address))
        expect(field("emails_alerts_recipients")["aria-invalid"]).to eq("true")
        expect(field("emails_alerts_recipients")["aria-describedby"]).to include("emails_alerts_recipients_error")
      end

      it "names every bad traffic recipient" do
        expect(refused(reports_recipients: "x, y@nowhere")).to include("Traffic email recipients", %("x" and "y@nowhere" are not email addresses))
      end

      it "names a sender that is not an address" do
        expect(refused(alerts_from: "Alerts")).to include("Alert email sender", %("Alerts" is not an email address))
        expect(refused(reports_from: "reports at example")).to include("Traffic email sender", "is not an email address")
      end

      it "refuses a period that is not daily, weekly or monthly" do
        expect(refused(reports_digest: [ "hourly" ])).to include("Traffic emails", %("hourly" is not daily, weekly or monthly))
      end

      it "keeps what was typed" do
        refused(alerts_recipients: "nobody", alerts_digest: [ "weekly" ])

        expect(field("emails_alerts_recipients").text.strip).to eq("nobody")
        expect(document.css("input[name='emails[alerts_digest][]'][checked]").map { |box| box["value"] }).to eq([ "weekly" ])
      end
    end

    describe "when a feature is not ready" do
      it "says nothing about either when both are on" do
        switch_on_ahoy_dashboard(:alerts, :reports)

        get "/telemetry/settings/emails/edit"

        expect(document.at_css("#alerts-state")).to be_nil
        expect(document.at_css("#reports-state")).to be_nil
      end

      it "still shows the fields when alerts and reports are off, and says so with a way to turn them on" do
        switch_off_ahoy_dashboard(:alerts, :reports)

        get "/telemetry/settings/emails/edit"

        expect(document.at_css("#alerts-state").text.squish).to include("Switched off", "turn alerts on")
        expect(document.at_css("#reports-state").text.squish).to include("Switched off", "turn email reports on")
        expect(document.at_css("#alerts-state a")["href"]).to eq("/telemetry/settings/features#feature-alerts")
        expect(document.at_css("#reports-state a")["href"]).to eq("/telemetry/settings/features#feature-reports")
        expect(field("emails_alerts_recipients")).to be_present
        expect(field("emails_reports_recipients")).to be_present
      end

      it "says when they are not installed, and still saves" do
        uninstall_ahoy_dashboard(:alerts, :reports)

        get "/telemetry/settings/emails/edit"

        expect(response).to have_http_status(:ok)
        expect(document.at_css("#alerts-state").text.squish).to include("Not installed in this app yet")
        expect(document.at_css("#reports-state").text.squish).to include("Not installed in this app yet")

        patch "/telemetry/settings/emails", params: { emails: valid }

        expect(read(:alerts, :recipients)).to eq([ "one@example.com", "two@example.com" ])
      end
    end
  end
end
