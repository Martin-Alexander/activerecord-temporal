module ActiveRecord::Temporal
  module ApplicationVersioning
    extend ActiveSupport::Concern

    class_methods do
      def application_versioned
        include ApplicationVersioned
      end
    end
  end
end
