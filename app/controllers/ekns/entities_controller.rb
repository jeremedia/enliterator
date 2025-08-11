# frozen_string_literal: true

class Ekns::EntitiesController < ApplicationController
  before_action :set_ekn
  
  def index
    @entities_by_source = get_entities_by_source_document
    @total_entities = @entities_by_source.sum { |_, data| data[:total] }
    @pool_counts = calculate_pool_counts(@entities_by_source)
    
    # Filter parameters
    @selected_pools = params[:pools]&.split(',') || []
    @search_query = params[:search]
    
    # Apply filters if present
    if @selected_pools.any? || @search_query.present?
      filter_entities_by_criteria
    end
    
    # Pagination - show 10 source documents per page
    @page = params[:page].to_i
    @page = 1 if @page <= 0
    @per_page = 10
    @total_pages = (@entities_by_source.size / @per_page.to_f).ceil
    
    # Paginate the source documents
    source_keys = @entities_by_source.keys
    start_index = (@page - 1) * @per_page
    end_index = start_index + @per_page - 1
    paginated_keys = source_keys[start_index..end_index] || []
    
    @paginated_entities = paginated_keys.map { |key| [key, @entities_by_source[key]] }.to_h
    
    respond_to do |format|
      format.html
      format.json { render json: { entities: @paginated_entities, total: @total_entities, pool_counts: @pool_counts, pagination: { page: @page, per_page: @per_page, total_pages: @total_pages } } }
    end
  end

  def show
    @entity = get_entity_details(params[:id])
    return redirect_to entities_path(ekn_slug: @ekn.slug), alert: 'Entity not found' unless @entity
    
    respond_to do |format|
      format.html
      format.json { render json: @entity }
    end
  end

  private

  def set_ekn
    @ekn = Ekn.find_by!(slug: params[:ekn_slug])
  end

  def get_entities_by_source_document
    service = EknStatsService.new(@ekn, include_provenance: false)
    
    # Get batch IDs for this specific EKN
    batch_ids = @ekn.ingest_batches.pluck(:id)
    return {} if batch_ids.empty?
    
    # Query to get entities ONLY for this EKN's batches
    query = <<~CYPHER
      MATCH (n)-[:HAS_RIGHTS]->(p:ProvenanceAndRights)
      WHERE labels(n)[0] <> 'ProvenanceAndRights' AND n.batch_id IN #{batch_ids}
      RETURN 
        id(n) as id,
        CASE 
          WHEN n.label IS NOT NULL AND n.label <> '' THEN n.label
          WHEN n.repr_text IS NOT NULL AND n.repr_text <> '' THEN 
            CASE 
              WHEN n.repr_text STARTS WITH 'How to' THEN substring(n.repr_text, 0, 80) + '...'
              ELSE substring(n.repr_text, 0, 60) + '...'
            END
          ELSE 'Untitled Entity'
        END as label,
        coalesce(n.abstract, '') as abstract,
        n.repr_text as repr_text,
        labels(n)[0] as pool,
        n.created_at as created_at,
        n.batch_id as batch_id,
        p.source_ids as source_ids,
        p.publishability as rights_publishable,
        p.training_eligibility as rights_training
      ORDER BY batch_id, pool
    CYPHER
    
    results = service.send(:execute_cypher, query)
    
    # Group by batch and source document
    grouped_data = {}
    results.each do |result|
      batch_id = result['batch_id']
      source_ids = result['source_ids'] || ['Unknown Source']
      pool = result['pool']
      
      # Create entity hash
      entity = {
        'id' => result['id'],
        'label' => result['label'],
        'abstract' => result['abstract'],
        'repr_text' => result['repr_text'],
        'pool' => result['pool'],
        'created_at' => result['created_at'],
        'rights_publishable' => result['rights_publishable'],
        'rights_training' => result['rights_training']
      }
      
      # Get batch name
      batch_name = begin
        IngestBatch.find(batch_id).name
      rescue
        "Batch #{batch_id}"
      end
      
      source_ids.each do |source_id|
        key = "#{batch_name} / #{source_id}"
        grouped_data[key] ||= {
          batch_id: batch_id,
          batch_name: batch_name,
          source_id: source_id,
          pools: {},
          total: 0
        }
        
        grouped_data[key][:pools][pool] ||= []
        grouped_data[key][:pools][pool] << entity
        grouped_data[key][:total] += 1
      end
    end
    
    # Sort by total entities descending
    Hash[grouped_data.sort_by { |_, data| -data[:total] }]
  end

  def calculate_pool_counts(entities_by_source)
    pool_counts = Hash.new(0)
    entities_by_source.each do |_, data|
      data[:pools].each do |pool, entities|
        pool_counts[pool] += entities.size
      end
    end
    pool_counts
  end

  def filter_entities_by_criteria
    if @selected_pools.any?
      @entities_by_source = @entities_by_source.transform_values do |data|
        filtered_pools = data[:pools].select { |pool, _| @selected_pools.include?(pool) }
        data.merge(
          pools: filtered_pools,
          total: filtered_pools.sum { |_, entities| entities.size }
        )
      end.reject { |_, data| data[:total] == 0 }
    end
    
    if @search_query.present?
      search_term = @search_query.downcase
      @entities_by_source = @entities_by_source.transform_values do |data|
        filtered_pools = {}
        data[:pools].each do |pool, entities|
          matching_entities = entities.select do |entity|
            entity['label'].downcase.include?(search_term) ||
            entity['abstract'].downcase.include?(search_term)
          end
          filtered_pools[pool] = matching_entities if matching_entities.any?
        end
        data.merge(
          pools: filtered_pools,
          total: filtered_pools.sum { |_, entities| entities.size }
        )
      end.reject { |_, data| data[:total] == 0 }
    end
    
    # Recalculate totals after filtering
    @total_entities = @entities_by_source.sum { |_, data| data[:total] }
  end

  def get_entity_details(entity_id)
    service = EknStatsService.new(@ekn, include_provenance: false)
    
    # Get batch IDs for this specific EKN
    batch_ids = @ekn.ingest_batches.pluck(:id)
    return nil if batch_ids.empty?
    
    query = <<~CYPHER
      MATCH (n)-[:HAS_RIGHTS]->(p:ProvenanceAndRights)
      WHERE id(n) = #{entity_id.to_i} AND n.batch_id IN #{batch_ids}
      OPTIONAL MATCH (n)-[r]-(related)
      WHERE labels(related)[0] <> 'ProvenanceAndRights'
      RETURN 
        id(n) as id,
        CASE 
          WHEN n.label IS NOT NULL AND n.label <> '' THEN n.label
          WHEN n.repr_text IS NOT NULL AND n.repr_text <> '' THEN 
            CASE 
              WHEN n.repr_text STARTS WITH 'How to' THEN substring(n.repr_text, 0, 100)
              ELSE substring(n.repr_text, 0, 80)
            END
          ELSE 'Untitled Entity'
        END as label,
        n.abstract as abstract,
        n.repr_text as repr_text,
        labels(n)[0] as pool,
        n.created_at as created_at,
        n.batch_id as batch_id,
        p.source_ids as source_ids,
        p.publishability as rights_publishable,
        p.training_eligibility as rights_training,
        collect(DISTINCT {
          id: id(related),
          label: CASE 
            WHEN related.label IS NOT NULL AND related.label <> '' THEN related.label
            WHEN related.repr_text IS NOT NULL AND related.repr_text <> '' THEN substring(related.repr_text, 0, 40) + '...'
            ELSE 'Untitled'
          END,
          pool: labels(related)[0],
          relationship: type(r)
        }) as relationships
    CYPHER
    
    results = service.send(:execute_cypher, query)
    results.first if results.any?
  end
end