RSpec.shared_examples "a stored secret removal" do |secret_path:, confirm_path:, edit_path:, word:, nothing:, model:, unknown:|
  it "never offers a #{word} from anywhere else to take over" do
    store_secret

    get confirm_path

    expect(response.body).not_to include("initializer", "used instead")
  end

  it "says there was nothing to remove" do
    expect { delete secret_path }.not_to change(model, :count)

    expect(response).to redirect_to(edit_path)
    expect(flash[:alert]).to eq(nothing)
  end

  unknown.each do |label, path|
    it "is a 404 for #{label}" do
      delete path

      expect(response).to have_http_status(:not_found)
    end
  end
end
