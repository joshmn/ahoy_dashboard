require "rails_helper"

RSpec.describe "Dashboard Search Console fill", type: :request do
  let(:path) { "/telemetry/settings/search_console_fill" }
  let(:connection) { "/telemetry/settings/google_connection" }
  let(:queue) { AhoyDashboard::SearchConsole::FillQueue }
  let(:last_final) { AhoyDashboard::SearchConsole.latest_final_date }

  def store(dates)
    Array(dates).each do |date|
      create(:dash_search_console_day, date: date)
      create(:dash_search_console_total, date: date)
    end
  end

  def store_with_a_hole
    store((last_final - 20)..(last_final - 15))
    store((last_final - 5)..last_final)
  end

  describe "as an admin" do
    before { sign_in create(:user, :admin) }

    describe "starting one" do
      it "refuses while search console is switched off rather than saying it started" do
        allow(AhoyDashboard::SearchConsole).to receive_messages(enabled?: false, client_id: "cid", client_secret: "secret")
        create(:dash_google_account, :with_property)
        store_with_a_hole

        expect { post path }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::FillJob)

        expect(response).to redirect_to(connection)
        expect(flash[:alert]).to eq(AhoyDashboard::SearchConsole::OFF_MESSAGE)
      end

      it "refuses when nothing is connected" do
        search_console_enabled!

        expect { post path }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::FillJob)

        expect(flash[:alert]).to eq("Connect Google first.")
      end

      it "refuses when connected with no property picked" do
        search_console_enabled!
        create(:dash_google_account)

        expect { post path }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::FillJob)

        expect(flash[:alert]).to eq("Pick a property first.")
      end

      it "says nothing is missing rather than starting a job with no days in it" do
        search_console_enabled!
        create(:dash_google_account, :with_property)
        store((last_final - 5)..last_final)

        expect { post path }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::FillJob)

        expect(flash[:alert]).to include("Nothing is missing")
      end

      it "queues the days the page was offering, oldest first" do
        search_console_enabled!
        create(:dash_google_account, :with_property)
        store_with_a_hole

        expect { post path }.to have_enqueued_job(AhoyDashboard::SearchConsole::FillJob)

        expect(response).to redirect_to(connection)
        expect(flash[:notice]).to include("Filling 9 days")
        expect(queue.load.next_date).to eq(last_final - 14)
        expect(queue.load.remaining).to eq(9)
      end

      it "will not start a second one over the top of the first" do
        search_console_enabled!
        create(:dash_google_account, :with_property)
        store_with_a_hole
        queue.start!([ last_final - 14, last_final - 13 ])

        expect { post path }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::FillJob)

        expect(flash[:alert]).to include("already going", "2 days left")
      end
    end

    describe "the missing days section" do
      before do
        search_console_enabled!
        create(:dash_google_account, :with_property)
      end

      it "lists a hole with its dates and how many days it is" do
        store_with_a_hole

        get connection
        row = document.css("table tbody tr").map { |node| node.text.squish }.find { |text| text.include?("Missing") }

        expect(row).to include("9 days")
        expect(response.body).to include("Fill these days")
      end

      it "marks days Google no longer serves as gone, and does not offer to fill them" do
        floor = AhoyDashboard::SearchConsole.earliest_available_date
        store([ floor - 10 ])
        store(floor..last_final)

        get connection
        rows = document.css("table tbody tr").map { |node| node.text.squish }

        expect(rows.any? { |text| text.include?("Gone") }).to be(true)
        expect(rows.none? { |text| text.include?("Missing") }).to be(true)
        expect(document.css("button[disabled]").map(&:text)).to include("Fill these days")
      end

      it "says nothing is missing when the record has no holes in it" do
        store((last_final - 5)..last_final)

        get connection

        expect(response.body).to include("Nothing is missing")
      end

      it "stays off the page until something has been pulled" do
        get connection

        expect(response.body).not_to include("Missing days")
      end

      it "leaves out a day that was scanned and had nothing on it, and says how many of those there are" do
        store((last_final - 10)..(last_final - 6))
        store((last_final - 3)..last_final)
        ((last_final - 5)..(last_final - 4)).each { |date| create(:dash_search_console_day, date: date) }

        get connection

        expect(response.body).to include("Nothing is missing")
        expect(document.text.gsub(/\s+/, " "))
          .to include("2 days of the 11 asked about came back with nothing on them")
      end

      it "says a fill is running and points at the job" do
        store_with_a_hole
        queue.start!([ last_final - 14, last_final - 13 ])

        get connection

        expect(response.body).to include("2 days left of 2")
        expect(document.css("a").map { |node| node["href"] })
          .to include("/telemetry/settings/job_runs/search_console_fill#runs")
      end
    end

    describe "the jobs screen" do
      around do |example|
        search_console_settings(enabled: true) { example.run }
      end

      before do
        search_console_enabled!
        create(:dash_google_account, :with_property)
      end

      def fill_row
        document.css(".jr-job").find { |node| node.at_css(".jr-name[title='search_console_fill']") }
      end

      it "names the fill and says how many days are left while one is going" do
        queue.start!([ last_final - 14, last_final - 13, last_final - 12 ])

        get "/telemetry/settings/job_runs"

        expect(fill_row.at_css(".jr-name").text.squish).to include("Search Console, filling gaps")
        expect(fill_row.at_css(".jr-why").text.squish).to eq("3 days left of 3.")
      end

      it "says there is nothing waiting rather than offering to start one" do
        get "/telemetry/settings/job_runs"

        expect(fill_row.at_css(".jr-why").text.squish).to include("No days are waiting to be filled.")
        expect(document.css("button[disabled]")).to be_present
      end

      it "only ever runs when it is asked to" do
        queue.start!([ last_final - 14 ])

        get "/telemetry/settings/job_runs"

        expect(fill_row.ancestors("tr").first.text.squish).to include("Only when you ask")
      end

      it "never starts itself on a tick" do
        queue.start!([ last_final - 14 ])

        expect { AhoyDashboard::TickJob.perform_now }.not_to have_enqueued_job(AhoyDashboard::SearchConsole::FillJob)
      end
    end
  end
end
