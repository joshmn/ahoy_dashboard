require "rails_helper"

RSpec.describe "Dashboard access", type: :request do
  variants = [
    [ "page", "", {} ],
    [ "frame", "", { "Tm-Frame" => "tm-control" } ],
    [ "json", ".json", {} ],
    [ "csv", ".csv", {} ]
  ].freeze

  before do
    allow(Rails.application).to receive(:env_config).and_wrap_original do |original|
      original.call.merge("action_dispatch.show_detailed_exceptions" => false)
    end
  end

  def knock(route, path, headers)
    names = [ AhoyDashboard::BaseController::VIEW_COOKIE, AhoyDashboard::BaseController::ASK_COOKIE ]
    names.each { |name| cookies.delete(name) }
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size
    mails = ActionMailer::Base.deliveries.size
    statements = captured_sql(cached: true) do
      public_send(route.verb.downcase, path, params: { period: "7d" }, headers: headers)
    end

    expect(statements).to be_empty, "#{route} ran #{statements.first}"
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(jobs), "#{route} enqueued a job"
    expect(ActionMailer::Base.deliveries.size).to eq(mails), "#{route} sent mail"
    expect(names.select { |name| cookies[name].present? }).to be_empty, "#{route} wrote a dashboard cookie"
  end

  variants.each do |variant, extension, headers|
    describe "as a #{variant}" do
      let(:routes) { AhoyDashboardRequestRoutes.every.select { |route| extension.empty? || route.formats? } }

      it "sends a signed out visitor to sign in from every route without running anything" do
        aggregate_failures do
          routes.each do |route|
            knock(route, "#{route.path}#{extension}", headers)

            expect(response).to redirect_to("/users/sign_in"), "#{route} as a #{variant} answered #{response.status}"
          end
        end
      end

      it "is a 404 on every route for a signed in visitor who is not an admin, without running anything" do
        user = create(:user)

        aggregate_failures do
          routes.each do |route|
            sign_in user
            knock(route, "#{route.path}#{extension}", headers)

            expect(response).to have_http_status(:not_found), "#{route} as a #{variant} answered #{response.status}"
            expect(document.at_css("a.live")).to be_nil, "#{route} as a #{variant} showed the dashboard"
          end
        end
      end
    end
  end
end
