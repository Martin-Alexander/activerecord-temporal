module ActiveRecord::Temporal
  module SystemVersioning
    module CommandRecorder
      [
        :create_versioning_hook,
        :drop_versioning_hook,
        :change_versioning_hook
      ].each do |method|
        class_eval <<-EOV, __FILE__, __LINE__ + 1
          def #{method}(*args)
            record(:#{method}, args)
          end
        EOV

        ruby2_keywords(method)
      end

      def invert_drop_versioning_hook(args)
        _, _, columns = args

        if columns.nil?
          raise ActiveRecord::IrreversibleMigration, "drop_versioning_hook is only reversible if given :columns option."
        end

        [:create_versioning_hook, args]
      end

      def invert_create_versioning_hook(args)
        [:drop_versioning_hook, args]
      end

      def invert_change_versioning_hook(args)
        source_table, history_table, options = args

        [
          :change_versioning_hook,
          [
            source_table,
            history_table,
            add_columns: options[:remove_columns],
            remove_columns: options[:add_columns]
          ]
        ]
      end
    end
  end
end
