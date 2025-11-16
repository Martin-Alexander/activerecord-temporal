module ActiveRecord::Temporal
  module ApplicationVersioned
    extend ActiveSupport::Concern

    included do
      include ActiveRecord::Temporal::Querying
    end

    class Revision
      attr_reader :record, :time, :options

      def initialize(record, time, **options)
        @record = record
        @time = time
        @options = options
      end

      def with(attributes)
        new_revision = record.dup
        new_revision.assign_attributes(attributes)
        new_revision.set_time_dimension_start(time)
        new_revision.time_tags = record.time_tags
        record.set_time_dimension_end(time)

        new_revision.after_initialize_revision(record)

        if options[:save]
          record.class.transaction do
            new_revision.save if record.save
          end
        end

        new_revision
      end
    end

    def after_initialize_revision(old_revision)
      self.version = old_revision.version + 1
      self.id_value = old_revision.id_value
    end

    def head_revision?
      time_dimension && !time_dimension_end
    end

    def revise
      time_coord = ActiveRecord::Temporal::Querying::ScopeRegistry.global_constraints

      revise_at(time_coord[default_time_dimension] || Time.current)
    end

    def revise_at(time)
      raise "not head revision" unless head_revision?

      Revision.new(self, time, save: true)
    end

    def revision
      time_coord = ActiveRecord::Temporal::Querying::ScopeRegistry.global_constraints

      revision_at(time_coord[default_time_dimension] || Time.current)
    end

    def revision_at(time)
      raise "not head revision" unless head_revision?

      Revision.new(self, time, save: false)
    end

    def inactivate
      time_coord = ActiveRecord::Temporal::Querying::ScopeRegistry.global_constraints

      inactivate_at(time_coord[default_time_dimension] || Time.current)
    end

    def inactivate_at(time)
      raise "not head revision" unless head_revision?

      set_time_dimension_end(time)
      save
    end
  end
end
