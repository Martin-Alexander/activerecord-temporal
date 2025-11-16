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

    def system_versioned_table(name, **options, &block)
      conn.create_table_with_system_versioning name, **options, &block
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
