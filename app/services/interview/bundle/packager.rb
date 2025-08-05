# app/services/interview/bundle/packager.rb
module Interview
  module Bundle
    class Packager
      def initialize(dataset:, metadata:, session_id:)
        @dataset = dataset
        @metadata = metadata
        @session_id = session_id
      end

      def package
        bundle_id = "interview_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{@session_id[0..7]}"
        bundle_path = Rails.root.join('tmp', 'bundles', "#{bundle_id}.json")
        
        # Ensure directory exists
        FileUtils.mkdir_p(File.dirname(bundle_path))
        
        # Prepare bundle content
        bundle_content = {
          id: bundle_id,
          created_at: Time.current,
          session_id: @session_id,
          metadata: @metadata,
          dataset: @dataset.to_h,
          manifest: generate_manifest,
          ready_for_pipeline: true
        }
        
        # Write bundle
        File.write(bundle_path, JSON.pretty_generate(bundle_content))
        
        {
          id: bundle_id,
          path: bundle_path.to_s,
          size: File.size(bundle_path),
          stats: bundle_stats
        }
      end

      private

      def generate_manifest
        {
          version: '1.0',
          generator: 'Interview Module',
          dataset_type: @metadata[:dataset_type],
          rights: @metadata[:rights],
          entity_count: @dataset.entity_count,
          has_temporal: @dataset.has_temporal?,
          has_spatial: @dataset.has_spatial?,
          has_descriptions: @dataset.has_descriptions?,
          processing_hints: {
            primary_entity_type: detect_primary_entity_type,
            temporal_field: detect_temporal_field,
            spatial_field: detect_spatial_field
          }
        }
      end

      def bundle_stats
        "#{@dataset.entity_count} entities, #{@dataset.sources.count} sources"
      end

      def detect_primary_entity_type
        return nil if @dataset.entities.empty?
        
        # Return type with most entities
        @dataset.entities.max_by { |_, entities| entities.count }&.first
      end

      def detect_temporal_field
        @dataset.instance_variable_get(:@temporal_fields).keys.first
      end

      def detect_spatial_field
        @dataset.instance_variable_get(:@spatial_fields).keys.first
      end
    end
  end
end