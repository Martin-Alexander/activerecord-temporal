require "spec_helper"

RSpec.describe ActiveRecord::Temporal::SystemVersioning::HistoryModel do
  include ActiveRecord::Temporal

  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  it "has the table name of its parent's history table name" do
    model "Cookie" do
      include ActiveRecord::Temporal::SystemVersioning::SystemVersioned
    end
    model "Pie" do
      include ActiveRecord::Temporal::SystemVersioning::SystemVersioned

      self.table_name = "big_pies"
    end
    model "Cake" do
      include ActiveRecord::Temporal::SystemVersioning::SystemVersioned

      def self.history_table_name
        "history_of_cakes"
      end
    end

    model "CookieHistory", Cookie do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end
    model "PieHistory", Pie do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end
    model "CakeHistory", Cake do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end

    expect(CookieHistory.table_name).to eq("cookies_history")
    expect(PieHistory.table_name).to eq("big_pies_history")
    expect(CakeHistory.table_name).to eq("history_of_cakes")
  end

  it "has its parent's table name when parent isn't system versioned" do
    model "Cookie"
    model "Pie" do
      self.table_name = "big_pies"
    end

    model "CookieHistory", Cookie do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end
    model "PieHistory", Pie do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end

    expect(CookieHistory.table_name).to eq("cookies")
    expect(PieHistory.table_name).to eq("big_pies")
  end

  it "has the correct primary key" do
    system_versioned_table :cookies
    system_versioned_table :cakes, primary_key: [:id, :version] do |t|
      t.bigint :id
      t.bigint :version
    end

    model "Cookie" do
      include ActiveRecord::Temporal::SystemVersioning::SystemVersioned
    end
    model "Pie"
    model "Cake" do
      include ActiveRecord::Temporal::SystemVersioning::SystemVersioned
    end

    model "CookieHistory", Cookie do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end
    model "PieHistory", Pie do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end
    model "CakeHistory", Cake do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end

    expect(CookieHistory.primary_key).to eq(%w[id system_period])
    expect(PieHistory.primary_key).to eq("id")
    expect(CakeHistory.primary_key).to eq(%w[id version system_period])
  end

  it "has the correct time dimensions" do
    model "Cookie" do
      include ActiveRecord::Temporal::Querying
      include ActiveRecord::Temporal::SystemVersioning::SystemVersioned

      self.time_dimensions = :validity
    end
    model "Pie" do
      include ActiveRecord::Temporal::Querying

      self.time_dimensions = :validity
    end
    model "Cake"

    model "CookieHistory", Cookie do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end
    model "PieHistory", Pie do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end
    model "CakeHistory", Cake do
      include ActiveRecord::Temporal::SystemVersioning::HistoryModel
    end

    expect(CookieHistory.time_dimensions).to eq([:validity, :system_period])
    expect(PieHistory.time_dimensions).to eq([:validity, :system_period])
    expect(CakeHistory.time_dimensions).to eq([:system_period])
  end

  shared_examples "versions records" do
    it "versions records" do
      t1 = transaction_time { Author.create!(name: "Will") }
      t2 = transaction_time { Author.first.update!(name: "Bob") }
      t3 = transaction_time { Author.first.destroy }
      t4 = transaction_time { Author.create!(name: "Sam") }
      t5 = transaction_time do
        Author.last.update(name: "Bill")
        Author.last.update(name: "Egbert")
      end

      expect(History::Author.count).to eq(4)

      expect(History::Author.first)
        .to have_attributes(name: "Will", system_period: t1...t2)
      expect(History::Author.second)
        .to have_attributes(name: "Bob", system_period: t2...t3)
      expect(History::Author.third)
        .to have_attributes(name: "Sam", system_period: t4...t5)
      expect(History::Author.fourth)
        .to have_attributes(name: "Egbert", system_period: t5...)
    end
  end

  context "source table primary key is 'id'" do
    before do
      system_versioned_table :authors do |t|
        t.string :name
      end
      history_model_namespace
      system_versioning_base "ApplicationRecord"
      system_versioned_model "Author", ApplicationRecord
    end

    include_examples "versions records"

    it "sets table_name to history table" do
      expect(History::Author.table_name).to eq("authors_history")
    end

    it "sets primary_key to source table primary key" do
      expect(History::Author.primary_key).to eq(%w[id system_period])
    end
  end

  context "source table primary key is (id, author_number)" do
    before do
      system_versioned_table :authors, primary_key: [:id, :author_number] do |t|
        t.bigserial :id, null: false
        t.bigserial :author_number, null: false
        t.string :name
      end
      history_model_namespace
      system_versioning_base "ApplicationRecord"
      system_versioned_model "Author", ApplicationRecord
    end

    it "sets primary_key to source table primary key" do
      expect(History::Author.primary_key).to eq(%w[id author_number system_period])
    end

    include_examples "versions records"
  end
end
