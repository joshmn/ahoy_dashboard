require "csv"

module DashboardExportChecks
  FILENAME = /\Aahoy-dashboard-seo-[a-z0-9-]+-\d{4}-\d{2}-\d{2}\.csv\z/

  def csv_download_links(document)
    document.css("a[aria-label^='Download '][aria-label$=' as CSV']")
  end

  def expect_csv_downloads(path, at_least: 1)
    get path
    expect(response).to have_http_status(:ok)

    links = csv_download_links(Nokogiri::HTML5(response.body))
    expect(links.size).to be >= at_least

    links.map { |link| [ link["href"], fetch_csv(link["href"]) ] }.to_h
  end

  def fetch_csv(href)
    get href

    expect(response).to have_http_status(:ok), "#{href} answered #{response.status}"
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["X-Accel-Buffering"]).to eq("no")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(csv_filename).to match(FILENAME), "#{href} downloads as #{csv_filename}"

    rows = CSV.parse(response.body)

    expect(rows.first).to be_present, "#{href} has no heading row"
    expect(rows.map(&:size).uniq).to eq([ rows.first.size ]), "#{href} has ragged rows"

    rows
  end

  def csv_filename
    response.headers["Content-Disposition"].to_s[/filename="?([^";]+)"?/, 1]
  end
end

RSpec.configure { |config| config.include DashboardExportChecks }
