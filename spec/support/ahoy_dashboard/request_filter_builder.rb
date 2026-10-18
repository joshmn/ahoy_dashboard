module AhoyDashboardRequestFilterBuilder
  def filter_rows(body = response.body)
    Nokogiri::HTML5(body).css("[data-dash--filters-target~='row']").reject { |node| node.ancestors("template").any? }
  end

  def filter_values(row)
    row.at_css("textarea[name$='[values_text]']")&.text.to_s.split("\n")
  end
end

RSpec.configure { |config| config.include AhoyDashboardRequestFilterBuilder, type: :request }

RSpec.shared_examples "a settings record built from filters" do |model:, factory:, path:, param:, article:, noun:, name:, filter:, other:|
  describe "create" do
    it "refuses #{article} with no name" do
      post path, params: { param => { name: " ", filters: [ filter ] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(model.count).to be_zero
    end
  end

  describe "edit" do
    it "says so on #{article} that names something gone" do
      record = create(factory, :unreadable)

      get "#{path}/#{record.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This one is not being applied")
    end
  end

  describe "update" do
    it "refuses to leave #{article} with no filters" do
      record = create(factory, filters: [ filter ])

      patch "#{path}/#{record.id}", params: { param => { name: record.name, filters: [ filter.merge("value" => "") ] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(record.reload.entries.size).to eq(1)
    end

    it "refuses a name another #{noun} already has" do
      create(factory, name: "Taken")
      record = create(factory, name: name)

      patch "#{path}/#{record.id}", params: { param => { name: "Taken", filters: [ filter ] } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(record.reload.name).to eq(name)
    end

    it "takes a filter out when its remove is pressed, without saving" do
      record = create(factory, filters: [ filter ])

      patch "#{path}/#{record.id}", params: { param => { name: record.name, remove: "0", filters: [ filter, other ] } }

      expect(response).to have_http_status(:ok)
      expect(filter_rows.map { |row| filter_values(row) }).to eq([ [ other["value"] ] ])
      expect(record.reload.entries.size).to eq(1)
    end
  end

  describe "destroy" do
    it "deletes it" do
      record = create(factory)

      delete "#{path}/#{record.id}"

      expect(response).to redirect_to(path)
      expect(model.count).to be_zero
    end
  end
end
