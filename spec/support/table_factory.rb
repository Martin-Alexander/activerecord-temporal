module ActiveRecordTemporalTests
  module TableFactory
    def table(name, **options, &block)
      conn.create_table name, **options do |t|
        instance_exec(t, &block) if block
      end

      Array(options[:primary_key] || :id).each do |col|
        randomize_sequence(name, col)
      end
    end

    def as_of_table name, **options, &block
      options = options.merge(primary_key: [:id, :version])

      table name, **options do |t|
        t.bigint :id
        t.bigserial :version
        t.tstzrange :period, null: false

        instance_exec(t, &block) if block
      end
    end

    def system_versioned_table(table_name, **options, &block)
      conn.enable_extension(:btree_gist)

      conn.create_table(table_name, **options, &block)

      source_pk = Array(conn.primary_key(table_name))
      history_options = options.merge(primary_key: source_pk + ["system_period"])

      exclusion_constraint_expression = source_pk.map do |col|
        "#{col} WITH ="
      end.join(", ") + ", system_period WITH &&"

      conn.create_table("#{table_name}_history", **history_options) do |t|
        conn.columns(table_name).each do |column|
          t.send(
            column.type,
            column.name,
            comment: column.comment,
            collation: column.collation,
            default: nil,
            limit: column.limit,
            null: column.null,
            precision: column.precision,
            scale: column.scale
          )
        end

        t.tstzrange :system_period, null: false
        t.exclusion_constraint exclusion_constraint_expression, using: :gist
      end

      conn.create_versioning_hook table_name,
        "#{table_name}_history",
        columns: :all,
        primary_key: source_pk
    end

    def application_versioned_table(table_name, **options, &block)
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

      conn.create_table(table_name, **options) do |t|
        unless pk_option.is_a?(Array)
          t.bigserial pk_option || :id, null: false
        end

        t.bigint :version, null: false, default: 1
        t.tstzrange :validity, null: false
        t.exclusion_constraint exclusion_constraint_expression, using: :gist

        instance_exec(t, &block)
      end
    end

    private

    def randomize_sequence(table, column)
      offset = Math.exp(2 + rand * (10 - 2)).to_i

      quoted_table = conn.quote_table_name(conn.quote_string(table.to_s))

      conn.execute(<<~SQL)
        SELECT setval(
          pg_get_serial_sequence('#{quoted_table}', '#{column}'),
          #{offset}
        )
      SQL
    end
  end
end
