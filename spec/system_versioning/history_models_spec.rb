require "spec_helper"

RSpec.describe ActiveRecord::Temporal::SystemVersioning::HistoryModels do
  after do
    drop_all_tables
    drop_all_versioning_hooks
  end

  describe "::history_model_namespace" do
    it "defaults to `History`" do
      history_model_namespace

      model "ApplicationRecord" do
        include ActiveRecord::Temporal::SystemVersioning::HistoryModels
      end

      expect(ApplicationRecord.history_model_namespace).to eq(History)
    end

    it "can be overwritten" do
      history_model_namespace "Versions"

      model "ApplicationRecord" do
        include ActiveRecord::Temporal::SystemVersioning::HistoryModels

        def self.history_model_namespace
          Versions
        end
      end

      expect(ApplicationRecord.history_model_namespace).to eq(Versions)
    end
  end

  describe "::history_model" do
    before do
      history_model_namespace

      model "ApplicationRecord" do
        self.abstract_class = true

        include ActiveRecord::Temporal::SystemVersioning::HistoryModels
      end
    end

    it "raises error on abstract classes" do
      expect { ApplicationRecord.history_model }
        .to raise_error(
          ActiveRecord::Temporal::SystemVersioning::HistoryModels::Error,
          "abstract classes cannot have a history model"
        )
    end

    it "returns the history model" do
      model "Cake", ApplicationRecord

      expect(Cake.history_model).to eq(History::Cake)
    end

    it "returns an explicitly set history model" do
      model "Cake", ApplicationRecord do
        def self.history_model
          MyCakeHistory
        end
      end
      model "MyCakeHistory", Cake do
        include ActiveRecord::Temporal::HistoryModel
      end

      expect(Cake.history_model).to eq(MyCakeHistory)
    end
  end

  describe "::history" do
    before do
      history_model_namespace

      model "ApplicationRecord" do
        self.abstract_class = true

        include ActiveRecord::Temporal::SystemVersioning::HistoryModels
      end
    end

    it "raises error on abstract classes" do
      expect { ApplicationRecord.history }
        .to raise_error(
          ActiveRecord::Temporal::SystemVersioning::HistoryModels::Error,
          "abstract classes cannot have a history model"
        )
    end

    it "returns an ActiveRecord::Relation" do
      system_versioned_table :cakes

      model "Cake", ApplicationRecord

      expect(Cake.history).to be_kind_of(ActiveRecord::Relation)
    end
  end

  describe "::at_time" do
    it "is delegated to ::history" do
      history_model_namespace

      model "ApplicationRecord" do
        self.abstract_class = true

        include ActiveRecord::Temporal::SystemVersioning::HistoryModels
      end

      system_versioned_table :cakes

      system_versioned_model "Cake", ApplicationRecord

      insert_time = transaction_time { Cake.create! }

      expect(Cake.at_time(insert_time - 10)).to be_empty
      expect(Cake.at_time(insert_time + 10).sole).to be_an_instance_of(History::Cake)
    end
  end

  describe "::as_of" do
    it "is delegated to ::history" do
      history_model_namespace

      model "ApplicationRecord" do
        self.abstract_class = true

        include ActiveRecord::Temporal::SystemVersioning::HistoryModels
      end

      system_versioned_table :cakes

      system_versioned_model "Cake", ApplicationRecord

      insert_time = transaction_time { Cake.create! }

      expect(Cake.as_of(insert_time - 10)).to be_empty
      expect(Cake.as_of(insert_time + 10).sole).to be_an_instance_of(History::Cake)
    end
  end
end
