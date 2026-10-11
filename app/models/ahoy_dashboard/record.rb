module AhoyDashboard
  class Record < ActiveRecord::Base
    extend AhoyDashboard::Compatibility::Record

    self.abstract_class = true
  end
end
