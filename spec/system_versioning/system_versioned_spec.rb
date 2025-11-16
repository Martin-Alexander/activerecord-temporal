require "spec_helper"

RSpec.describe ActiveRecord::Temporal::SystemVersioning::SystemVersioned do
  describe "::history_table_name" do
    it "defaults to _history" do
      model "Cookie" do
        include SystemVersioned
      end

      expect(Cookie.history_table_name).to eq("cookies_history")
    end

    it "can be set" do
      model "Cookie" do
        include SystemVersioned

        self.history_table_name = "my_cookies_history"
      end

      expect(Cookie.history_table_name).to eq("my_cookies_history")
    end
  end
end
