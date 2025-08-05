# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_05_225433) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gin"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "vector"

  create_table "emanation_ideas", force: :cascade do |t|
    t.bigint "emanation_id", null: false
    t.bigint "idea_id", null: false
    t.string "relation_type"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["emanation_id", "idea_id", "relation_type"], name: "index_eman_idea_on_ids_and_type", unique: true
    t.index ["emanation_id"], name: "index_emanation_ideas_on_emanation_id"
    t.index ["idea_id"], name: "index_emanation_ideas_on_idea_id"
  end

  create_table "emanation_relationals", force: :cascade do |t|
    t.bigint "emanation_id", null: false
    t.bigint "relational_id", null: false
    t.string "relation_type", default: "diffuses_through"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["emanation_id", "relational_id"], name: "index_emanation_relationals_on_emanation_id_and_relational_id", unique: true
    t.index ["emanation_id"], name: "index_emanation_relationals_on_emanation_id"
    t.index ["relational_id"], name: "index_emanation_relationals_on_relational_id"
  end

  create_table "emanations", force: :cascade do |t|
    t.string "influence_type", null: false
    t.text "target_context"
    t.text "pathway"
    t.text "evidence"
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "strength"
    t.jsonb "evidence_refs", default: []
    t.jsonb "temporal_extent", default: {}
    t.index ["influence_type"], name: "index_emanations_on_influence_type"
    t.index ["provenance_and_rights_id"], name: "index_emanations_on_provenance_and_rights_id"
    t.index ["valid_time_start", "valid_time_end"], name: "index_emanations_on_valid_time_start_and_valid_time_end"
  end

  create_table "embeddings", force: :cascade do |t|
    t.string "embeddable_type", null: false
    t.string "embeddable_id", null: false
    t.string "pool", null: false
    t.string "embedding_type", null: false
    t.text "source_text", null: false
    t.string "text_hash", null: false
    t.vector "embedding", limit: 1536, null: false
    t.boolean "publishable", default: false, null: false
    t.boolean "training_eligible", default: false, null: false
    t.jsonb "metadata", default: {}
    t.string "model_version"
    t.datetime "indexed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embeddable_type", "embeddable_id"], name: "index_embeddings_on_embeddable"
    t.index ["embedding"], name: "index_embeddings_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["embedding_type"], name: "index_embeddings_on_embedding_type"
    t.index ["indexed_at"], name: "index_embeddings_on_indexed_at"
    t.index ["pool"], name: "index_embeddings_on_pool"
    t.index ["publishable", "training_eligible"], name: "index_embeddings_on_rights"
    t.index ["text_hash"], name: "index_embeddings_on_text_hash", unique: true
  end

  create_table "evolutionaries", force: :cascade do |t|
    t.text "change_note", null: false
    t.string "prior_ref_type"
    t.bigint "prior_ref_id"
    t.string "version_id"
    t.bigint "refined_idea_id"
    t.bigint "manifest_version_id"
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "repr_text", null: false
    t.text "change_summary", null: false
    t.jsonb "delta_metrics", default: {}
    t.index ["manifest_version_id"], name: "index_evolutionaries_on_manifest_version_id"
    t.index ["prior_ref_type", "prior_ref_id"], name: "index_evolutionaries_on_prior_ref"
    t.index ["prior_ref_type", "prior_ref_id"], name: "index_evolutionaries_on_prior_ref_type_and_prior_ref_id"
    t.index ["provenance_and_rights_id"], name: "index_evolutionaries_on_provenance_and_rights_id"
    t.index ["refined_idea_id"], name: "index_evolutionaries_on_refined_idea_id"
    t.index ["valid_time_start", "valid_time_end"], name: "index_evolutionaries_on_valid_time_start_and_valid_time_end"
    t.index ["version_id"], name: "index_evolutionaries_on_version_id"
  end

  create_table "experience_emanations", force: :cascade do |t|
    t.bigint "experience_id", null: false
    t.bigint "emanation_id", null: false
    t.string "relation_type", default: "inspires"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["emanation_id"], name: "index_experience_emanations_on_emanation_id"
    t.index ["experience_id", "emanation_id"], name: "index_experience_emanations_on_experience_id_and_emanation_id", unique: true
    t.index ["experience_id"], name: "index_experience_emanations_on_experience_id"
  end

  create_table "experience_practicals", force: :cascade do |t|
    t.bigint "experience_id", null: false
    t.bigint "practical_id", null: false
    t.string "relation_type"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["experience_id", "practical_id", "relation_type"], name: "index_exp_prac_on_ids_and_type", unique: true
    t.index ["experience_id"], name: "index_experience_practicals_on_experience_id"
    t.index ["practical_id"], name: "index_experience_practicals_on_practical_id"
  end

  create_table "experiences", force: :cascade do |t|
    t.string "agent_label"
    t.text "context"
    t.text "narrative_text", null: false
    t.string "sentiment"
    t.datetime "observed_at", null: false
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_experiences_on_actor_id"
    t.index ["agent_label"], name: "index_experiences_on_agent_label"
    t.index ["narrative_text"], name: "index_experiences_on_narrative_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["observed_at"], name: "index_experiences_on_observed_at"
    t.index ["provenance_and_rights_id"], name: "index_experiences_on_provenance_and_rights_id"
    t.index ["sentiment"], name: "index_experiences_on_sentiment"
  end

  create_table "idea_emanations", force: :cascade do |t|
    t.bigint "idea_id", null: false
    t.bigint "emanation_id", null: false
    t.string "relation_type", default: "influences"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["emanation_id"], name: "index_idea_emanations_on_emanation_id"
    t.index ["idea_id", "emanation_id"], name: "index_idea_emanations_on_idea_id_and_emanation_id", unique: true
    t.index ["idea_id"], name: "index_idea_emanations_on_idea_id"
  end

  create_table "idea_manifests", force: :cascade do |t|
    t.bigint "idea_id", null: false
    t.bigint "manifest_id", null: false
    t.string "relation_type", default: "embodies"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "manifest_id"], name: "index_idea_manifests_on_idea_id_and_manifest_id", unique: true
    t.index ["idea_id"], name: "index_idea_manifests_on_idea_id"
    t.index ["manifest_id"], name: "index_idea_manifests_on_manifest_id"
  end

  create_table "idea_practicals", force: :cascade do |t|
    t.bigint "idea_id", null: false
    t.bigint "practical_id", null: false
    t.string "relation_type", default: "codifies"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "practical_id"], name: "index_idea_practicals_on_idea_id_and_practical_id", unique: true
    t.index ["idea_id"], name: "index_idea_practicals_on_idea_id"
    t.index ["practical_id"], name: "index_idea_practicals_on_practical_id"
  end

  create_table "ideas", force: :cascade do |t|
    t.string "label", null: false
    t.text "abstract", null: false
    t.jsonb "principle_tags", default: []
    t.string "authorship"
    t.date "inception_date", null: false
    t.text "repr_text", null: false
    t.boolean "is_canonical", default: false, null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["abstract"], name: "index_ideas_on_abstract_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["is_canonical"], name: "index_ideas_on_is_canonical"
    t.index ["label"], name: "index_ideas_on_label"
    t.index ["label"], name: "index_ideas_on_label_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["principle_tags"], name: "index_ideas_on_principle_tags", using: :gin
    t.index ["provenance_and_rights_id"], name: "index_ideas_on_provenance_and_rights_id"
    t.index ["valid_time_start", "valid_time_end"], name: "index_ideas_on_valid_time_start_and_valid_time_end"
  end

  create_table "ingest_batches", force: :cascade do |t|
    t.string "name", null: false
    t.string "source_type", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "metadata", default: {}
    t.jsonb "statistics", default: {}
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "graph_assembly_stats"
    t.datetime "graph_assembled_at"
    t.datetime "deliverables_generated_at"
    t.string "deliverables_path"
    t.text "deliverables_errors"
    t.index ["created_at"], name: "index_ingest_batches_on_created_at"
    t.index ["source_type"], name: "index_ingest_batches_on_source_type"
    t.index ["status"], name: "index_ingest_batches_on_status"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])", name: "check_status_values"
  end

  create_table "ingest_items", force: :cascade do |t|
    t.bigint "ingest_batch_id", null: false
    t.bigint "provenance_and_rights_id"
    t.string "pool_item_type"
    t.bigint "pool_item_id"
    t.string "source_hash", null: false
    t.string "file_path", null: false
    t.string "source_type"
    t.string "media_type", default: "unknown", null: false
    t.string "triage_status", default: "pending", null: false
    t.bigint "size_bytes"
    t.text "content_sample"
    t.jsonb "metadata", default: {}
    t.jsonb "triage_metadata", default: {}
    t.string "triage_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "lexicon_status", default: "pending"
    t.jsonb "lexicon_metadata", default: {}
    t.text "content"
    t.string "pool_status", default: "pending"
    t.jsonb "pool_metadata", default: {}
    t.index ["ingest_batch_id"], name: "index_ingest_items_on_ingest_batch_id"
    t.index ["lexicon_status"], name: "index_ingest_items_on_lexicon_status"
    t.index ["media_type"], name: "index_ingest_items_on_media_type"
    t.index ["pool_item_type", "pool_item_id"], name: "index_ingest_items_on_pool_item"
    t.index ["pool_item_type", "pool_item_id"], name: "index_ingest_items_on_pool_item_type_and_pool_item_id"
    t.index ["pool_status"], name: "index_ingest_items_on_pool_status"
    t.index ["provenance_and_rights_id"], name: "index_ingest_items_on_provenance_and_rights_id"
    t.index ["source_hash"], name: "index_ingest_items_on_source_hash", unique: true
    t.index ["triage_status"], name: "index_ingest_items_on_triage_status"
  end

  create_table "intent_and_tasks", force: :cascade do |t|
    t.text "user_goal", null: false
    t.text "query_text"
    t.jsonb "presentation_preference", default: {}
    t.string "outcome_signal"
    t.jsonb "success_criteria", default: {}
    t.text "repr_text", null: false
    t.string "deliverable_type"
    t.string "modality"
    t.jsonb "constraints", default: {}
    t.string "adapter_name"
    t.jsonb "adapter_params", default: {}
    t.jsonb "evaluation", default: {}
    t.datetime "observed_at", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "raw_intent"
    t.jsonb "normalized_intent", default: {}
    t.integer "status", default: 0, null: false
    t.datetime "resolved_at"
    t.jsonb "metadata", default: {}
    t.bigint "user_session_id"
    t.datetime "valid_time_start", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "valid_time_end"
    t.index ["deliverable_type"], name: "index_intent_and_tasks_on_deliverable_type"
    t.index ["modality"], name: "index_intent_and_tasks_on_modality"
    t.index ["observed_at"], name: "index_intent_and_tasks_on_observed_at"
    t.index ["provenance_and_rights_id"], name: "index_intent_and_tasks_on_provenance_and_rights_id"
    t.index ["resolved_at"], name: "index_intent_and_tasks_on_resolved_at"
    t.index ["status"], name: "index_intent_and_tasks_on_status"
  end

  create_table "lexicon_and_ontologies", force: :cascade do |t|
    t.string "term", null: false
    t.text "definition"
    t.text "canonical_description"
    t.jsonb "surface_forms", default: []
    t.jsonb "negative_surface_forms", default: []
    t.jsonb "type_mapping", default: {}
    t.string "unit_system"
    t.string "schema_version"
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "repr_text", null: false
    t.string "pool_association", null: false
    t.boolean "is_canonical", default: false, null: false
    t.jsonb "relations", default: {}
    t.index ["negative_surface_forms"], name: "index_lexicon_and_ontologies_on_negative_surface_forms", using: :gin
    t.index ["provenance_and_rights_id"], name: "index_lexicon_and_ontologies_on_provenance_and_rights_id"
    t.index ["surface_forms"], name: "index_lexicon_and_ontologies_on_surface_forms", using: :gin
    t.index ["term"], name: "index_lexicon_and_ontologies_on_term", unique: true
    t.index ["valid_time_start", "valid_time_end"], name: "idx_on_valid_time_start_valid_time_end_5b95b14d20"
  end

  create_table "manifest_experiences", force: :cascade do |t|
    t.bigint "manifest_id", null: false
    t.bigint "experience_id", null: false
    t.string "relation_type", default: "elicits"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["experience_id"], name: "index_manifest_experiences_on_experience_id"
    t.index ["manifest_id", "experience_id"], name: "index_manifest_experiences_on_manifest_id_and_experience_id", unique: true
    t.index ["manifest_id"], name: "index_manifest_experiences_on_manifest_id"
  end

  create_table "manifests", force: :cascade do |t|
    t.string "label", null: false
    t.string "manifest_type"
    t.jsonb "components", default: []
    t.jsonb "time_bounds", default: {}
    t.string "spatial_ref"
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["components"], name: "index_manifests_on_components", using: :gin
    t.index ["label"], name: "index_manifests_on_label"
    t.index ["label"], name: "index_manifests_on_label_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["manifest_type"], name: "index_manifests_on_manifest_type"
    t.index ["provenance_and_rights_id"], name: "index_manifests_on_provenance_and_rights_id"
    t.index ["spatial_ref"], name: "index_manifests_on_spatial_ref"
    t.index ["valid_time_start", "valid_time_end"], name: "index_manifests_on_valid_time_start_and_valid_time_end"
  end

  create_table "pg_search_documents", force: :cascade do |t|
    t.text "content"
    t.string "searchable_type"
    t.bigint "searchable_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["searchable_type", "searchable_id"], name: "index_pg_search_documents_on_searchable"
  end

  create_table "pipeline_artifacts", force: :cascade do |t|
    t.bigint "pipeline_run_id", null: false
    t.string "artifact_type", null: false
    t.string "file_path", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artifact_type"], name: "index_pipeline_artifacts_on_artifact_type"
    t.index ["pipeline_run_id"], name: "index_pipeline_artifacts_on_pipeline_run_id"
  end

  create_table "pipeline_errors", force: :cascade do |t|
    t.bigint "pipeline_run_id", null: false
    t.string "stage", null: false
    t.string "error_type", null: false
    t.text "message"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pipeline_run_id"], name: "index_pipeline_errors_on_pipeline_run_id"
    t.index ["stage"], name: "index_pipeline_errors_on_stage"
  end

  create_table "pipeline_runs", force: :cascade do |t|
    t.string "bundle_path", null: false
    t.string "stage", null: false
    t.string "status", null: false
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.jsonb "metrics", default: {}
    t.jsonb "options", default: {}
    t.integer "file_count"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stage", "status"], name: "index_pipeline_runs_on_stage_and_status"
    t.index ["stage"], name: "index_pipeline_runs_on_stage"
    t.index ["started_at"], name: "index_pipeline_runs_on_started_at"
    t.index ["status"], name: "index_pipeline_runs_on_status"
  end

  create_table "practical_ideas", force: :cascade do |t|
    t.bigint "practical_id", null: false
    t.bigint "idea_id", null: false
    t.string "relation_type"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id"], name: "index_practical_ideas_on_idea_id"
    t.index ["practical_id", "idea_id", "relation_type"], name: "index_prac_idea_on_ids_and_type", unique: true
    t.index ["practical_id"], name: "index_practical_ideas_on_practical_id"
  end

  create_table "practicals", force: :cascade do |t|
    t.string "goal", null: false
    t.jsonb "steps", default: []
    t.jsonb "prerequisites", default: []
    t.jsonb "hazards", default: []
    t.jsonb "validation_refs", default: []
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["goal"], name: "index_practicals_on_goal"
    t.index ["provenance_and_rights_id"], name: "index_practicals_on_provenance_and_rights_id"
    t.index ["steps"], name: "index_practicals_on_steps", using: :gin
    t.index ["valid_time_start", "valid_time_end"], name: "index_practicals_on_valid_time_start_and_valid_time_end"
  end

  create_table "provenance_and_rights", force: :cascade do |t|
    t.jsonb "source_ids", default: [], null: false
    t.string "source_owner"
    t.jsonb "collectors", default: []
    t.string "collection_method", null: false
    t.integer "consent_status", default: 0, null: false
    t.integer "license_type", default: 0, null: false
    t.jsonb "custom_terms", default: {}
    t.boolean "publishability", default: false, null: false
    t.boolean "training_eligibility", default: false, null: false
    t.datetime "embargo_until"
    t.boolean "quarantined", default: false, null: false
    t.string "quarantine_reason"
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embargo_until"], name: "index_provenance_and_rights_on_embargo_until"
    t.index ["publishability", "training_eligibility"], name: "index_p_and_r_on_publish_and_train"
    t.index ["publishability"], name: "index_provenance_and_rights_on_publishability"
    t.index ["quarantined"], name: "index_provenance_and_rights_on_quarantined"
    t.index ["source_ids"], name: "index_provenance_and_rights_on_source_ids", using: :gin
    t.index ["training_eligibility"], name: "index_provenance_and_rights_on_training_eligibility"
    t.index ["valid_time_start", "valid_time_end"], name: "idx_on_valid_time_start_valid_time_end_afad4edcbc"
  end

  create_table "relationals", force: :cascade do |t|
    t.string "relation_type", null: false
    t.string "source_type", null: false
    t.bigint "source_id", null: false
    t.string "target_type", null: false
    t.bigint "target_id", null: false
    t.float "strength"
    t.jsonb "period", default: {}
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "repr_text", null: false
    t.index ["provenance_and_rights_id"], name: "index_relationals_on_provenance_and_rights_id"
    t.index ["relation_type"], name: "index_relationals_on_relation_type"
    t.index ["source_type", "source_id"], name: "index_relationals_on_source"
    t.index ["source_type", "source_id"], name: "index_relationals_on_source_type_and_source_id"
    t.index ["target_type", "target_id"], name: "index_relationals_on_target"
    t.index ["target_type", "target_id"], name: "index_relationals_on_target_type_and_target_id"
    t.index ["valid_time_start", "valid_time_end"], name: "index_relationals_on_valid_time_start_and_valid_time_end"
  end

  add_foreign_key "emanation_ideas", "emanations"
  add_foreign_key "emanation_ideas", "ideas"
  add_foreign_key "emanation_relationals", "emanations"
  add_foreign_key "emanation_relationals", "relationals"
  add_foreign_key "emanations", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "evolutionaries", "ideas", column: "refined_idea_id"
  add_foreign_key "evolutionaries", "manifests", column: "manifest_version_id"
  add_foreign_key "evolutionaries", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "experience_emanations", "emanations"
  add_foreign_key "experience_emanations", "experiences"
  add_foreign_key "experience_practicals", "experiences"
  add_foreign_key "experience_practicals", "practicals"
  add_foreign_key "experiences", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "idea_emanations", "emanations"
  add_foreign_key "idea_emanations", "ideas"
  add_foreign_key "idea_manifests", "ideas"
  add_foreign_key "idea_manifests", "manifests"
  add_foreign_key "idea_practicals", "ideas"
  add_foreign_key "idea_practicals", "practicals"
  add_foreign_key "ideas", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "ingest_items", "ingest_batches"
  add_foreign_key "ingest_items", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "intent_and_tasks", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "lexicon_and_ontologies", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "manifest_experiences", "experiences"
  add_foreign_key "manifest_experiences", "manifests"
  add_foreign_key "manifests", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "pipeline_artifacts", "pipeline_runs"
  add_foreign_key "pipeline_errors", "pipeline_runs"
  add_foreign_key "practical_ideas", "ideas"
  add_foreign_key "practical_ideas", "practicals"
  add_foreign_key "practicals", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "relationals", "provenance_and_rights", column: "provenance_and_rights_id"
end
