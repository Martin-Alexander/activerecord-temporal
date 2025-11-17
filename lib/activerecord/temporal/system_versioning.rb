module ActiveRecord::Temporal
  module SystemVersioning
    extend ActiveSupport::Concern

    included do
      include HistoryModels
    end

    class_methods do
      def system_versioned
        include SystemVersioned
      end
    end
  end
end
