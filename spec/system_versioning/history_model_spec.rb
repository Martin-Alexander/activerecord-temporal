require "spec_helper"

RSpec.describe ActiveRecord::Temporal::SystemVersioning::HistoryModel do
  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  it "has the table name of its parent's history table name" do
    model "Cookie" do
      include ActiveRecord::Temporal::SystemVersioned
    end
    model "Pie" do
      include ActiveRecord::Temporal::SystemVersioned

      self.table_name = "big_pies"
    end
    model "Cake" do
      include ActiveRecord::Temporal::SystemVersioned

      self.history_table_name = "history_of_cakes"
    end

    model "CookieHistory", Cookie do
      include ActiveRecord::Temporal::HistoryModel
    end
    model "PieHistory", Pie do
      include ActiveRecord::Temporal::HistoryModel
    end
    model "CakeHistory", Cake do
      include ActiveRecord::Temporal::HistoryModel
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
      include ActiveRecord::Temporal::HistoryModel
    end
    model "PieHistory", Pie do
      include ActiveRecord::Temporal::HistoryModel
    end

    expect(CookieHistory.table_name).to eq("cookies")
    expect(PieHistory.table_name).to eq("big_pies")
  end

  it "has the correct primary key" do
    system_versioned_table :cookies

    model "Cookie" do
      include ActiveRecord::Temporal::SystemVersioned
    end
    model "Pie"

    model "CookieHistory", Cookie do
      include ActiveRecord::Temporal::HistoryModel
    end
    model "PieHistory", Pie do
      include ActiveRecord::Temporal::HistoryModel
    end

    expect(CookieHistory.primary_key).to eq(["id", "system_period"])
    expect(PieHistory.primary_key).to eq("id")
  end

  it "has the correct time dimensions" do
    model "Cookie" do
      include ActiveRecord::Temporal::Querying
      include ActiveRecord::Temporal::SystemVersioned

      self.time_dimensions = :validity
    end
    model "Pie" do
      include ActiveRecord::Temporal::Querying

      self.time_dimensions = :validity
    end
    model "Cake"

    model "CookieHistory", Cookie do
      include ActiveRecord::Temporal::HistoryModel
    end
    model "PieHistory", Pie do
      include ActiveRecord::Temporal::HistoryModel
    end
    model "CakeHistory", Cake do
      include ActiveRecord::Temporal::HistoryModel
    end

    expect(CookieHistory.time_dimensions).to eq([:validity, :system_period])
    expect(PieHistory.time_dimensions).to eq([:validity, :system_period])
    expect(CakeHistory.time_dimensions).to eq([:system_period])
  end
end
