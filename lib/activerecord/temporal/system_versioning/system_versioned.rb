module ActiveRecord::Temporal
  module SystemVersioning
    module SystemVersioned
      extend ActiveSupport::Concern

      class_methods do
        def history_table_name
          @history_table_name || table_name&.+("_history")
        end

        def history_table_name=(name)
          @history_table_name = name
        end

        def inherited(child)
          super

          child.history_table_name = history_table_name
        end
      end
    end
  end
end
