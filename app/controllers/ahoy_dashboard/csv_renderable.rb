module AhoyDashboard
  module CsvRenderable
    def default_render
      return super unless request.format.symbol == :csv

      table = csv_presenter&.csv_table(params[:table])
      raise ActiveRecord::RecordNotFound, "no csv table #{params[:table].inspect}" if table.nil?

      stream_csv(csv_presenter.csv_filename(table), table.rows)
    end

    private

    def csv_presenter
      @presenter
    end
  end
end
