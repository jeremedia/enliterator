module Ekns
  class ImportStatsController < ApplicationController
    before_action :load_ekn

    def index
      @include_rights = ActiveModel::Type::Boolean.new.cast(params[:include_rights])
      @publishable_only = ActiveModel::Type::Boolean.new.cast(params[:publishable_only])

      @filters = {
        q: params[:q].to_s.strip.presence,
        pools: Array(params[:pool]).presence,
        stages: Array(params[:stage]).presence,
        batch_id: params[:batch_id].presence,
        publishable_only: @publishable_only,
        include_rights: @include_rights
      }

      # Base scope: all ingest items across all batches for this EKN
      scope = @ekn.ingest_items.includes(:provenance_and_rights, :ingest_batch)

      if @filters[:batch_id]
        scope = scope.where(ingest_batch_id: @filters[:batch_id])
      end

      if @filters[:q]
        q = "%#{@filters[:q]}%"
        scope = scope.where("file_path ILIKE ? OR source_type ILIKE ?", q, q)
      end

      if @filters[:stages]
        # Allow filtering by any stage status value provided
        # Example: stage[]=lexicon:extracted
        @filters[:stages].each do |stage_spec|
          stage, status = stage_spec.split(":", 2)
          next unless stage && status
          case stage
          when 'triage' then scope = scope.where(triage_status: status)
          when 'lexicon' then scope = scope.where(lexicon_status: status)
          when 'pool' then scope = scope.where(pool_status: status)
          when 'graph' then scope = scope.where(graph_status: status)
          when 'embedding' then scope = scope.where(embedding_status: status)
          end
        end
      end

      if @publishable_only
        scope = scope.joins(:provenance_and_rights).where(provenance_and_rights: { publishability: true })
      end

      @items = scope.order(created_at: :desc) # Show all

      @service = Reporting::ImportStatsService.new(@ekn, include_rights: @include_rights)
      @summaries = {}
      @items.each do |item|
        summary = @service.summary_for_item(item)
        neo_count = summary[:pool_counts].values.sum
        fallback_count = @service.entity_count_fallback(item)
        summary[:entity_count] = neo_count.zero? ? fallback_count : neo_count
        @summaries[item.id] = summary
      rescue => e
        Rails.logger.error "ImportStats summary error for item #{item.id}: #{e.message}"
        @summaries[item.id] = { pool_counts: {}, relationship_count: 0, entity_count: 0 }
      end

      # Sort items by entity count desc (no pagination as requested)
      @items = @items.sort_by { |it| -(@summaries[it.id][:entity_count] || 0) }
    end

    def details
      @include_rights = ActiveModel::Type::Boolean.new.cast(params[:include_rights])
      @service = Reporting::ImportStatsService.new(@ekn, include_rights: @include_rights)

      @item = @ekn.ingest_items.find(params[:id])
      entities_page = params[:entities_page].to_i
      rels_page = params[:rels_page].to_i
      entities_page = 1 if entities_page <= 0
      rels_page = 1 if rels_page <= 0

      @details = @service.details_for_item(@item, entities_page: entities_page, rels_page: rels_page)
      @api_calls = @service.api_calls_for_item(@item, limit: 8)

      render partial: 'details', formats: [:html]
    end

    private

    def load_ekn
      @ekn = ::Ekn.find_by!(slug: params[:ekn_slug])
    end
  end
end
