module ActiveRecord::Temporal
  module SystemVersioning
    module Migration
      extend ActiveSupport::Concern

      included do
        prepend Patches
      end

      module Patches
        def create_table(table_name, id: :primary_key, primary_key: nil, force: nil, **options, &block)
          system_versioning = options.delete(:system_versioning)

          if system_versioning
            create_table_with_system_versioning(
              table_name, id:, primary_key:, force:, **options, &block
            )
          else
            super
          end
        end

        def drop_table(*table_names, **options)
          system_versioning = options.delete(:system_versioning)

          if system_versioning
            drop_table_with_system_versioning(*table_names, **options)
          else
            super
          end
        end
      end
    end
  end
end
