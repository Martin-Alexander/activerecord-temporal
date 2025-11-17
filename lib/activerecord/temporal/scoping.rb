module ActiveRecord::Temporal
  module Scoping
    def temporal_scoping
      Querying::Scoping
    end
  end
end
