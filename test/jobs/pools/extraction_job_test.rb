# frozen_string_literal: true

require 'test_helper'

module Pools
  class ExtractionJobTest < ActiveJob::TestCase
    setup do
      @batch = IngestBatch.create!(
        source: 'test_extraction',
        status: 'rights_completed',
        metadata: { test: true }
      )
      
      @provenance = ProvenanceAndRights.create!(
        source_ids: ['test_extraction'],
        collectors: ['Test Extractor'],
        collection_method: 'test',
        consent_status: 'explicit_consent',
        license_type: 'cc_by',
        source_owner: 'Test',
        valid_time_start: Time.current
      )
      
      @ingest_item = @batch.ingest_items.create!(
        source_type: 'text',
        raw_content: test_content,
        provenance_and_rights: @provenance,
        triage_status: 'completed',
        lexicon_status: 'extracted',
        content: test_content
      )
    end

    test "extracts entities and relations from content" do
      # Stub OpenAI responses
      stub_entity_extraction_response
      stub_relation_extraction_response
      
      assert_difference -> { Idea.count } => 1,
                       -> { Manifest.count } => 1,
                       -> { Experience.count } => 1 do
        ExtractionJob.perform_now(@batch.id)
      end
      
      @batch.reload
      assert_equal 'pool_filling_completed', @batch.status
      
      # Check entities were created
      idea = Idea.last
      assert_equal 'Radical Inclusion', idea.label
      assert idea.provenance_and_rights.present?
      
      manifest = Manifest.last
      assert_equal 'Temple of Whollyness', manifest.label
      
      # Check relations were created
      assert IdeaManifest.exists?(idea: idea, manifest: manifest)
    end
    
    test "handles extraction failures gracefully" do
      # Stub OpenAI to fail
      stub_extraction_failure
      
      ExtractionJob.perform_now(@batch.id)
      
      @ingest_item.reload
      assert_equal 'failed', @ingest_item.pool_status
      assert @ingest_item.pool_metadata['error'].present?
      
      @batch.reload
      assert_equal 'pool_filling_completed', @batch.status
    end
    
    test "records path provenance" do
      stub_entity_extraction_response
      stub_relation_extraction_response
      
      ExtractionJob.perform_now(@batch.id)
      
      @batch.reload
      metadata = @batch.metadata['pool_filling_results']
      assert metadata['path_provenance_count'] > 0
    end
    
    private
    
    def test_content
      <<~CONTENT
        The principle of Radical Inclusion means anyone may be a part of Burning Man.
        We welcome and respect the stranger. No prerequisites exist for participation
        in our community.
        
        The Temple of Whollyness was an amazing structure that embodied this principle.
        Many participants reported feeling deeply moved when they visited, saying it
        changed their perspective on community and belonging.
      CONTENT
    end
    
    def stub_entity_extraction_response
      response = mock_response({
        entities: [
          {
            pool_type: 'idea',
            confidence: 0.9,
            attributes: {
              label: 'Radical Inclusion',
              abstract: 'Anyone may be a part of Burning Man',
              principle_tags: ['inclusion', 'community'],
              time_reference: 'current'
            },
            lexicon_match: nil,
            source_span: 'The principle of Radical Inclusion'
          },
          {
            pool_type: 'manifest',
            confidence: 0.85,
            attributes: {
              label: 'Temple of Whollyness',
              components: ['structure'],
              time_reference: nil
            },
            lexicon_match: nil,
            source_span: 'The Temple of Whollyness was an amazing structure'
          },
          {
            pool_type: 'experience',
            confidence: 0.8,
            attributes: {
              label: 'Participant testimonial',
              narrative_text: 'feeling deeply moved when they visited',
              time_reference: nil
            },
            lexicon_match: nil,
            source_span: 'participants reported feeling deeply moved'
          }
        ],
        extraction_metadata: {
          total_entities: 3,
          source_length: test_content.length
        }
      })
      
      OPENAI.expects(:responses).returns(mock_responses_api(response))
    end
    
    def stub_relation_extraction_response
      response = mock_response({
        relations: [
          {
            verb: 'embodies',
            source: { pool_type: 'idea', label: 'Radical Inclusion', entity_index: 0 },
            target: { pool_type: 'manifest', label: 'Temple of Whollyness', entity_index: 1 },
            confidence: 0.9,
            evidence: 'Temple of Whollyness was an amazing structure that embodied this principle'
          },
          {
            verb: 'elicits',
            source: { pool_type: 'manifest', label: 'Temple of Whollyness', entity_index: 1 },
            target: { pool_type: 'experience', label: 'Participant testimonial', entity_index: 2 },
            confidence: 0.85,
            evidence: 'participants reported feeling deeply moved when they visited'
          }
        ],
        unmapped_relations: []
      })
      
      OPENAI.expects(:responses).returns(mock_responses_api(response))
    end
    
    def stub_extraction_failure
      OPENAI.expects(:responses).raises(StandardError, "API Error")
    end
    
    def mock_response(data)
      OpenStruct.new(
        output: [
          OpenStruct.new(
            content: [
              OpenStruct.new(parsed: OpenStruct.new(data))
            ]
          )
        ]
      )
    end
    
    def mock_responses_api(response)
      OpenStruct.new(create: response)
    end
  end
end