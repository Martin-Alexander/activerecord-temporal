module ActiveRecord::Temporal
  module ApplicationVersioning
    module SchemaStatements
      def create_application_versioned_table(table_name, **options, &block)
        pk_option = options[:primary_key]

        primary_key = if options[:primary_key]
          Array(options[:primary_key]) | [:version]
        else
          [:id, :version]
        end

        exclusion_constraint_expression = (primary_key - [:version]).map do |col|
          "#{col} WITH ="
        end.join(", ") + ", validity WITH &&"

        options = options.merge(primary_key: primary_key)

        create_table(table_name, **options) do |t|
          unless pk_option.is_a?(Array)
            t.bigserial pk_option || :id, null: false
          end

          t.bigint :version, null: false, default: 1
          t.tstzrange :validity, null: false
          t.exclusion_constraint exclusion_constraint_expression, using: :gist

          instance_exec(t, &block)
        end
      end
    end
  end
end
