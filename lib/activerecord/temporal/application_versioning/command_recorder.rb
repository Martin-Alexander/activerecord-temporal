module ActiveRecord::Temporal
  module ApplicationVersioning
    module CommandRecorder
      def create_application_versioned_table(*args)
        record(:create_application_versioned_table, args)
      end
      ruby2_keywords(:create_application_versioned_table)

      def invert_create_application_versioned_table(args)
        [:drop_table, args]
      end
    end
  end
end
