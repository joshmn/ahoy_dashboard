module AhoyDashboard
  module CsvRenderable
    def default_render
      return super unless request_format == :csv

      table = @presenter&.csv_table(params[:table])
      raise ActiveRecord::RecordNotFound, "no csv table #{params[:table].inspect}" if table.nil?

      stream_csv(@presenter.csv_filename(table), table.rows)
    end
  end
end
