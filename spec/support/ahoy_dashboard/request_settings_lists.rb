RSpec.shared_examples "an empty settings list" do |path:, text:|
  it "renders an empty list" do
    get path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(text)
  end
end

RSpec.shared_examples "a settings list that adds at the end" do |factory:, path:, noun:, created:|
  it "puts a new #{noun} at the end of the list" do
    existing = create(factory, position: 7)

    post path, params: addition

    expect(existing.class.find_by!(created).position).to eq(8)
  end
end

RSpec.shared_examples "a nudgeable settings list" do |factory:, path:, param:, noun:|
  it "moves a #{noun} up the list" do
    first = create(factory, position: 1)
    second = create(factory, position: 2)

    patch "#{path}/#{second.to_param}", params: { param => { nudge: "up" } }

    expect(response).to redirect_to(path)
    expect(first.class.ordered.pluck(:id)).to eq([ second.id, first.id ])
  end

  it "moves a #{noun} down the list" do
    first = create(factory, position: 1)
    second = create(factory, position: 2)

    patch "#{path}/#{first.to_param}", params: { param => { nudge: "down" } }

    expect(response).to redirect_to(path)
    expect(first.class.ordered.pluck(:id)).to eq([ second.id, first.id ])
  end

  it "numbers a list nobody has ordered yet rather than swapping two zeroes" do
    first = create(factory, position: 0)
    second = create(factory, position: 0)

    patch "#{path}/#{second.to_param}", params: { param => { nudge: "up" } }

    expect(first.class.ordered.pluck(:id)).to eq([ second.id, first.id ])
    expect(first.class.ordered.pluck(:position)).to eq([ 1, 2 ])
  end

  it "does nothing at the top of the list" do
    top = create(factory, position: 1)
    other = create(factory, position: 2)

    patch "#{path}/#{top.to_param}", params: { param => { nudge: "up" } }

    expect(response).to redirect_to(path)
    expect(top.reload.position).to eq(1)
    expect(top.class.ordered.pluck(:id)).to eq([ top.id, other.id ])
  end

  it "does nothing for a direction nobody offered" do
    top = create(factory, position: 1)
    other = create(factory, position: 2)

    patch "#{path}/#{top.to_param}", params: { param => { nudge: "sideways" } }

    expect(response).to redirect_to(path)
    expect(top.reload.position).to eq(1)
    expect(top.class.ordered.pluck(:id)).to eq([ top.id, other.id ])
  end
end

RSpec.shared_examples "a settings record nobody created" do |path:, noun:, changes:|
  it "404s on edit, update and destroy for #{noun} nobody created" do
    [ [ :get, "#{path}/9999/edit", {} ], [ :patch, "#{path}/9999", changes ], [ :delete, "#{path}/9999", {} ] ].each do |verb, url, params|
      public_send(verb, url, params: params)

      expect(response).to have_http_status(:not_found), "#{verb} #{url} answered #{response.status}"
    end
  end
end
