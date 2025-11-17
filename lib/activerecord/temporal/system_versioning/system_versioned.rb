module ActiveRecord::Temporal
  module SystemVersioning
    module SystemVersioned
      extend ActiveSupport::Concern

      class_methods do
        def history_table_name
          table_name + "_history" if table_name
        end
      end
    end
  end
end
