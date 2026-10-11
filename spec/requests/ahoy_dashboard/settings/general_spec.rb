require "rails_helper"
require "support/ahoy_dashboard/switches"

RSpec.describe "Dashboard general settings", type: :request do
  def stored(name)
    AhoyDashboard::Preferences.stored?(:site, name)
  end

  def page
    Nokogiri::HTML5(response.body)
  end

  def field(id)
    page.at_css("##{id}")
  end

  def settings
    AhoyDashboard::Setting.order(:key).pluck(:key, :value)
  end

  let(:valid) do
    { time_zone: "Tokyo", host: "fpd.example", canonical_host: "www.fpd.example", internal_ips: "10.0.0.0/8\n203.0.113.7" }
  end

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      get "/telemetry/settings/general/edit"

      expect(response).to redirect_to("/users/sign_in")
    end

    it "is a 404 for a signed in visitor who is not an admin, and writes nothing" do
      sign_in create(:user)

      expect { patch "/telemetry/settings/general", params: { general: valid } }.not_to(change { settings })
      expect(response).to have_http_status(:not_found)
    end

    it "will not put the default addresses back for somebody who is not an admin" do
      ahoy_dashboard_preferences(:site, internal_ips: [])
      sign_in create(:user)

      expect { post "/telemetry/settings/default_internal_addresses" }.not_to(change { settings })
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "is listed in the settings nav" do
      get "/telemetry/settings/general/edit"

      expect(page.css("a").map { |link| link["href"] }).to include("/telemetry/settings/general/edit")
    end

    it "labels every field and wires its hint" do
      get "/telemetry/settings/general/edit"

      %w[general_host general_canonical_host general_time_zone general_internal_ips].each do |id|
        expect(page.at_css("label[for='#{id}']")).to be_present, "expected a label for #{id}"
        expect(field(id)["aria-describedby"]).to include("#{id}_hint")
      end
    end

    describe "with nothing stored" do
      before { AhoyDashboard::Preferences.clear(:site, :host) }

      it "fills the host in from the address being browsed and says it is not saved" do
        get "/telemetry/settings/general/edit"

        expect(response).to have_http_status(:ok)
        expect(field("general_host")["value"]).to eq("www.example.com")
        expect(page.at_css("#general_host_hint").text).to include("Not saved yet.")
        expect(stored(:host)).to be(false)
      end

      it "starts on UTC with the default internal addresses" do
        get "/telemetry/settings/general/edit"

        expect(field("general_time_zone").at_css("option[selected]")["value"]).to eq("UTC")
        expect(field("general_internal_ips").text.split).to eq(AhoyDashboard::Preferences::INTERNAL_IPS)
        expect(page.at_css("#general_internal_ips_hint").text).to include("127.0.0.0/8", "fc00::/7")
        expect(response.body).not_to include("config.internal_ips")
      end

      it "offers the defaults switched off with the reason" do
        get "/telemetry/settings/general/edit"

        button = page.css("button[disabled]").find { |node| node.text.squish == "Use the defaults" }
        expect(button).to be_present
        expect(page.at_css("##{button['aria-describedby']}").text).to eq("The list is already the defaults.")
      end
    end

    it "shows what is stored" do
      ahoy_dashboard_preferences(:site, host: "fpd.example", canonical_host: "www.fpd.example",
                                        internal_ips: [ "10.0.0.0/8" ], time_zone: "Tokyo")

      get "/telemetry/settings/general/edit"

      expect(field("general_host")["value"]).to eq("fpd.example")
      expect(field("general_canonical_host")["value"]).to eq("www.fpd.example")
      expect(field("general_time_zone").at_css("option[selected]")["value"]).to eq("Tokyo")
      expect(field("general_internal_ips").text.strip).to eq("10.0.0.0/8")
      expect(page.at_css("#general_host_hint").text).not_to include("Not saved yet.")
    end

    it "saves every field and the dashboard reads them from then on" do
      patch "/telemetry/settings/general", params: { general: valid }

      expect(response).to redirect_to("/telemetry/settings/general/edit")
      expect(AhoyDashboard.time_zone).to eq(ActiveSupport::TimeZone["Tokyo"])
      expect(AhoyDashboard.host).to eq("fpd.example")
      expect(AhoyDashboard.canonical_host).to eq("www.fpd.example")
      expect(AhoyDashboard::Sql::InternalAddresses.ranges.map(&:cidr)).to eq([ "10.0.0.0/8", "203.0.113.7/32" ])
    end

    it "takes a comma separated list of addresses" do
      patch "/telemetry/settings/general", params: { general: valid.merge(internal_ips: "10.0.0.0/8, ::1/128") }

      expect(AhoyDashboard::Preferences.read(:site, :internal_ips)).to eq([ "10.0.0.0/8", "::1/128" ])
    end

    it "strips a pasted scheme and path off both hosts" do
      patch "/telemetry/settings/general",
            params: { general: valid.merge(host: "https://FPD.example/blog?x=1", canonical_host: "http://www.fpd.example/") }

      expect(AhoyDashboard.host).to eq("fpd.example")
      expect(AhoyDashboard.canonical_host).to eq("www.fpd.example")
    end

    it "goes back to the host when the canonical host is cleared" do
      ahoy_dashboard_preferences(:site, canonical_host: "www.fpd.example")

      patch "/telemetry/settings/general", params: { general: valid.merge(canonical_host: "") }

      expect(stored(:canonical_host)).to be(false)
      expect(AhoyDashboard.canonical_host).to eq("fpd.example")
    end

    it "clears the host when it is emptied" do
      ahoy_dashboard_preferences(:site, host: "fpd.example")

      patch "/telemetry/settings/general", params: { general: valid.merge(host: "", canonical_host: "") }

      expect(stored(:host)).to be(false)
      expect(AhoyDashboard.host).to be_nil
    end

    it "keeps an emptied address list empty, which leaves nothing out" do
      patch "/telemetry/settings/general", params: { general: valid.merge(internal_ips: "") }

      expect(stored(:internal_ips)).to be(true)
      expect(AhoyDashboard::Sql::InternalAddresses.ranges).to be_empty

      follow_redirect!
      expect(response.body).to include("The list is empty")
    end

    it "puts the default addresses back" do
      ahoy_dashboard_preferences(:site, internal_ips: [])

      post "/telemetry/settings/default_internal_addresses"

      expect(response).to redirect_to("/telemetry/settings/general/edit#internal-addresses")
      expect(stored(:internal_ips)).to be(false)
      expect(AhoyDashboard::Preferences.read(:site, :internal_ips)).to eq(AhoyDashboard::Preferences::INTERNAL_IPS)
    end

    it "offers the defaults when the list has been changed" do
      ahoy_dashboard_preferences(:site, internal_ips: [ "10.0.0.0/8" ])

      get "/telemetry/settings/general/edit"

      button = page.css("form button").find { |node| node.text.squish == "Use the defaults" }
      expect(button).to be_present
      expect(button["disabled"]).to be_nil
      expect(button.ancestors("form").first["action"]).to eq("/telemetry/settings/default_internal_addresses")
    end

    describe "refusing" do
      def refused(**changes)
        expect { patch "/telemetry/settings/general", params: { general: valid.merge(changes) } }.not_to(change { settings })

        expect(response).to have_http_status(:unprocessable_entity)
        page.at_css("[role='alert']").text.squish
      end

      it "names the bad address" do
        expect(refused(internal_ips: "10.0.0.0/8\nnot-an-ip")).to include("Internal addresses", %("not-an-ip" is not an address or a range))
        expect(field("general_internal_ips")["aria-invalid"]).to eq("true")
        expect(field("general_internal_ips")["aria-describedby"]).to include("general_internal_ips_error")
      end

      it "names every bad address at once" do
        expect(refused(internal_ips: "nope, 10.0.0.0/99")).to include(%("nope" and "10.0.0.0/99" are not addresses or ranges))
      end

      it "names a host that is not a host name" do
        expect(refused(host: "not a host")).to include("Site host", %("not a host" is not a host name))
      end

      it "refuses a host with a port" do
        expect(refused(canonical_host: "fpd.example:3000")).to include("Canonical host", "is not a host name", "no port")
      end

      it "rejects a zone it has never heard of" do
        expect(refused(time_zone: "Mars/Olympus Mons")).to include("is not a time zone this app knows")
      end

      it "rejects a blank zone" do
        expect(refused(time_zone: "")).to include("Time zone has to be picked")
      end

      it "rejects nothing at all" do
        expect { patch "/telemetry/settings/general" }.not_to(change { settings })

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "keeps what was typed" do
        refused(host: "not a host", internal_ips: "nope")

        expect(field("general_host")["value"]).to eq("not a host")
        expect(field("general_internal_ips").text.strip).to eq("nope")
      end
    end
  end
end
