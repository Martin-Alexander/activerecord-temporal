require "active_record"
require "active_support/test_case"
require "debug"
require "niceql"

require "activerecord/temporal"

require "support/associations"
require "support/db_config"
require "support/have_column"
require "support/have_versioning_hook"
require "support/model_factory"
require "support/namespace_factory"
require "support/record_factory"
require "support/table_factory"
require "support/transaction_time"

ActiveSupport.on_load(:active_record) do
  require "support/test_connection_adapter"
end

RSpec.configure do |config|
  ActiveRecord::Base.establish_connection(ActiveRecordTemporalTests::DbConfig.get)
  ActiveRecord::Base.logger = Logger.new($stdout) if ENV.fetch("AR_LOG") { false }

  include ActiveRecordTemporalTests

  config.include ActiveSupport::Testing::TimeHelpers
  config.include Associations
  config.include ModelFactory
  config.include NamespaceFactory
  config.include RecordFactory
  config.include TableFactory
  config.include TransactionTime

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  def drop_all_tables
    conn.tables.each { |table| conn.drop_table(table, force: :cascade) }
  end

  def drop_all_versioning_hooks
    functions = test_conn.plpgsql_functions

    return if functions.empty?

    function_names = functions.map { "#{_1.name}()" }.join(", ")

    conn.execute("DROP FUNCTION #{function_names} CASCADE")
  end

  def conn
    ActiveRecord::Base.connection
  end

  def test_conn
    db_config = DbConfig.get

    @test_conn ||= TestConnectionAdapter.new(db_config)
  end

  def p_sql(relation)
    puts(Niceql::Prettifier.prettify_sql(relation.to_sql))
  end
end
