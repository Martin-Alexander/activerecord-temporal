module ActiveRecordTemporalTests
  module NamespaceFactory
    def history_model_namespace(name = "History", &block)
      mod = Module.new do
        include SystemVersioning::HistoryModelNamespace

        instance_eval(&block) if block
      end

      stub_const(name, mod)
    end
  end
end
