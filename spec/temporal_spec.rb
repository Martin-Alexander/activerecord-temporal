require "spec_helper"

RSpec.describe ActiveRecord::Temporal do
  describe "::system_versioning" do
    it "includes SystemVersioning" do
      model "ApplicationRecord"

      ApplicationRecord.extend ActiveRecord::Temporal
      ApplicationRecord.system_versioning

      expect(ApplicationRecord).to be_include(SystemVersioning)
    end
  end

  describe "::application_versioning" do
    it "includes ApplicationVersioning" do
      model "ApplicationRecord"

      ApplicationRecord.extend ActiveRecord::Temporal
      ApplicationRecord.application_versioning

      expect(ApplicationRecord).to be_include(ApplicationVersioning)
    end

    it "sets the time dimension" do
      model "ApplicationRecord"

      ApplicationRecord.extend ActiveRecord::Temporal
      ApplicationRecord.application_versioning dimensions: :validity

      expect(ApplicationRecord).to be_include(ApplicationVersioning)
      expect(ApplicationRecord.time_dimensions).to eq([:validity])
    end
  end
end
