require "spec_helper"

RSpec.describe ActiveRecord::Temporal::Scoping do
  it "#temporal_scope returns Querying::Scoping" do
    klass = Class.new do
      include ActiveRecord::Temporal::Scoping
    end

    expect(klass.new.temporal_scoping).to eq(ActiveRecord::Temporal::Querying::Scoping)
  end
end
