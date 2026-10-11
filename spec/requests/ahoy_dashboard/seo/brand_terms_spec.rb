require "rails_helper"

RSpec.describe "Dashboard seo brand terms", type: :request do
  let(:key) { AhoyDashboard::Seo::BrandTerms::KEY }

  after { AhoyDashboard::Setting.clear(key) }

  describe "gating" do
    it "sends a signed out visitor to sign in" do
      patch "/telemetry/seo/brand_terms", params: { brand_terms: { terms: "prison dude" } }

      expect(response).to redirect_to("/users/sign_in")
      expect(AhoyDashboard::Setting.read(key)).to be_nil
    end

    it "is a 404 for a signed in visitor who is not an admin" do
      sign_in create(:user)

      patch "/telemetry/seo/brand_terms", params: { brand_terms: { terms: "prison dude" } }

      expect(response).to have_http_status(:not_found)
      expect(AhoyDashboard::Setting.read(key)).to be_nil
    end
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    it "stores the list, one term per comma, without repeats" do
      patch "/telemetry/seo/brand_terms", params: { period: "6mo", brand_terms: { terms: " federal prison dude, Prison Dude ,federalprisondude,, prison-dude " } }

      expect(response).to redirect_to("/telemetry/seo/brand_split?period=6mo")
      expect(AhoyDashboard::Setting.read(key)).to eq([ "federal prison dude", "Prison Dude" ])
      expect(flash[:notice]).to eq("Brand words saved.")
    end

    it "clears the list when the box is emptied and goes back to the site's name" do
      AhoyDashboard::Setting.write(key, [ "prison dude" ])

      patch "/telemetry/seo/brand_terms", params: { brand_terms: { terms: "  " } }

      expect(response).to redirect_to("/telemetry/seo/brand_split?period=28d")
      expect(AhoyDashboard::Setting.read(key)).to be_nil
      expect(AhoyDashboard::Seo::BrandTerms.current).to eq(AhoyDashboard::Seo::BrandTerms.default)
    end

    it "refuses a list too long to be a list of brand words" do
      patch "/telemetry/seo/brand_terms", params: { brand_terms: { terms: "x" * 2001 } }

      expect(response).to redirect_to("/telemetry/seo/brand_split?period=28d")
      expect(AhoyDashboard::Setting.read(key)).to be_nil
      expect(flash[:alert]).to be_present
    end
  end
end
