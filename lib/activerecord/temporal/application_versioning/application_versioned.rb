module ActiveRecord::Temporal
  module ApplicationVersioning
    module ApplicationVersioned
      extend ActiveSupport::Concern

      included do
        delegate :scope_time, to: :class

        include Querying
      end

      class_methods do
        def originate
          originate_at(scope_time || Time.current)
        end

        def originate_at(time)
          Original.new(self, time, save: true)
        end

        def original
          original_at(scope_time || Time.current)
        end

        def original_at(time)
          Original.new(self, time)
        end

        def scope_time
          Querying::ScopeRegistry.global_constraint_for(time_dimensions.first)
        end
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
          new_revision.id = record.id
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

      class Original
        attr_reader :klass, :time, :options

        def initialize(klass, time, **options)
          @klass = klass
          @time = time
          @options = options
        end

        def with(attributes)
          new_record = klass.new(attributes)
          new_record.set_time_dimension_start(time)

          new_record.save if options[:save]

          new_record
        end
      end

      def after_initialize_revision(old_revision)
        self.version = old_revision.version + 1
      end

      def head_revision?
        time_dimension && !time_dimension_end
      end

      def revise
        revise_at(scope_time || Time.current)
      end

      def revise_at(time)
        raise ClosedRevisionError, "Cannot revise closed version" unless head_revision?

        Revision.new(self, time, save: true)
      end

      def revision
        revision_at(scope_time || Time.current)
      end

      def revision_at(time)
        raise ClosedRevisionError, "Cannot revise closed version" unless head_revision?

        Revision.new(self, time, save: false)
      end

      def inactivate
        inactivate_at(scope_time || Time.current)
      end

      def inactivate_at(time)
        raise ClosedRevisionError, "Cannot inactivate closed version" unless head_revision?

        set_time_dimension_end(time)
        save
      end
    end
  end
end
