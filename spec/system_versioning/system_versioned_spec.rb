require "spec_helper"

RSpec.describe ActiveRecord::Temporal::SystemVersioning::SystemVersioned do
  it "::history_table_name adds '_history' to table name" do
    model "Cookie" do
      include ActiveRecord::Temporal::SystemVersioning::SystemVersioned
    end

    expect(Cookie.history_table_name).to eq("cookies_history")
  end
end
