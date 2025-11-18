module ActiveRecord::Temporal
  module ApplicationVersioning
    module Migration
      extend ActiveSupport::Concern

      included do
        prepend Patches
      end

      module Patches
        def create_table(table_name, id: :primary_key, primary_key: nil, force: nil, **options, &block)
          application_versioning = options.delete(:application_versioning)

          if application_versioning
            create_application_versioned_table(
              table_name, id:, primary_key:, force:, **options, &block
            )
          else
            super
          end
        end
      end
    end
  end
end
