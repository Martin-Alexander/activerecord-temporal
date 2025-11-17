module ActiveRecord::Temporal
  module Querying
    class RangeError < StandardError; end

    extend ActiveSupport::Concern

    class_methods do
      def resolve_time_coords(time_or_time_coords)
        return time_or_time_coords if time_or_time_coords.is_a?(Hash)

        {default_time_dimension.to_sym => time_or_time_coords}
      end
    end

    included do
      include AssociationMacros
      include TimeDimensions
      include PredicateBuilder::Handlers

      delegate :resolve_time_coords, to: :class

      default_scope do
        at_time(Querying::ScopeRegistry.global_constraints_for(time_dimensions))
      end

      scope :as_of, ->(time) do
        time_coords = resolve_time_coords(time)

        at_time(time_coords).time_tags(time_coords)
      end

      scope :at_time, ->(time) do
        time_coords = resolve_time_coords(time)

        constraints = time_coords.slice(*time_dimension_columns)

        return if constraints.empty?

        rewhere_contains(constraints.transform_values { |v| contains(v) })
      end
    end

    def time_tags
      @time_tags || {}
    end

    def time_tags=(value)
      @time_tags = value&.slice(*time_dimensions)
    end

    def time_tag
      time_tags[default_time_dimension]
    end

    def time_tags_for(time_dimensions)
      time_tags.slice(*time_dimensions)
    end

    def as_of!(time)
      time_coords = resolve_time_coords(time)

      ensure_time_tags_in_bounds!(time_coords)

      reload

      self.time_tags = time_coords
    end

    def as_of(time)
      time_coords = resolve_time_coords(time)

      self.class.as_of(time_coords).find_by(self.class.primary_key => [id])
    end

    def initialize_time_tags_from_relation(relation)
      associations = relation.includes_values | relation.eager_load_values

      self.time_tags = relation.time_tag_values

      AssociationWalker.each_target(self, associations) do |target|
        target.time_tags = relation.time_tag_values
      end
    end

    private

    def ensure_time_tags_in_bounds!(time_tags)
      time_tags.each do |dimension, time|
        if time_dimension_column?(dimension) && !time_dimension(dimension).cover?(time)
          raise RangeError, "#{time} is outside of '#{dimension}' range"
        end
      end
    end
  end
end
