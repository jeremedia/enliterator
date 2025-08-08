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

ActiveRecord::Schema[8.0].define(version: 2025_08_08_205235) do
  create_schema "ekn_11"
  create_schema "ekn_12"
  create_schema "ekn_13"
  create_schema "ekn_14"
  create_schema "ekn_34"
  create_schema "ekn_7"

  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gin"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "vector"

  create_table "actor_experiences", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.bigint "experience_id", null: false
    t.string "relation_type", default: "participates_in"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id", "experience_id"], name: "index_actor_experiences_on_actor_id_and_experience_id", unique: true
    t.index ["actor_id"], name: "index_actor_experiences_on_actor_id"
    t.index ["experience_id"], name: "index_actor_experiences_on_experience_id"
  end

  create_table "actor_manifests", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.bigint "manifest_id", null: false
    t.string "relation_type", default: "interacts_with"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id", "manifest_id"], name: "index_actor_manifests_on_actor_id_and_manifest_id", unique: true
    t.index ["actor_id"], name: "index_actor_manifests_on_actor_id"
    t.index ["manifest_id"], name: "index_actor_manifests_on_manifest_id"
  end

  create_table "actors", force: :cascade do |t|
    t.string "name", null: false
    t.string "role"
    t.text "description"
    t.jsonb "capabilities", default: []
    t.jsonb "affiliations", default: []
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_actors_on_name"
    t.index ["provenance_and_rights_id"], name: "index_actors_on_provenance_and_rights_id"
    t.index ["role"], name: "index_actors_on_role"
    t.index ["valid_time_start", "valid_time_end"], name: "index_actors_on_valid_time_start_and_valid_time_end"
  end

  create_table "api_calls", force: :cascade do |t|
    t.string "type", null: false
    t.string "service_name", null: false
    t.string "endpoint", null: false
    t.string "model_used"
    t.string "model_version"
    t.jsonb "request_params", default: {}
    t.jsonb "response_data", default: {}
    t.jsonb "response_headers", default: {}
    t.integer "prompt_tokens"
    t.integer "completion_tokens"
    t.integer "total_tokens"
    t.integer "cached_tokens"
    t.integer "reasoning_tokens"
    t.integer "image_count"
    t.string "image_size"
    t.string "image_quality"
    t.float "audio_duration"
    t.string "voice_id"
    t.decimal "input_cost", precision: 12, scale: 8
    t.decimal "output_cost", precision: 12, scale: 8
    t.decimal "total_cost", precision: 12, scale: 8
    t.string "currency", default: "USD"
    t.float "response_time_ms"
    t.float "processing_time_ms"
    t.integer "retry_count", default: 0
    t.float "queue_time_ms"
    t.string "status", default: "pending", null: false
    t.string "error_code"
    t.text "error_message"
    t.jsonb "error_details", default: {}
    t.string "trackable_type"
    t.bigint "trackable_id"
    t.bigint "user_id"
    t.string "request_id"
    t.string "batch_id"
    t.string "response_cache_key"
    t.string "session_id"
    t.jsonb "metadata", default: {}
    t.boolean "cached_response", default: false
    t.string "environment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ekn_id"
    t.string "response_type"
    t.index ["batch_id"], name: "index_api_calls_on_batch_id"
    t.index ["created_at"], name: "index_api_calls_on_created_at"
    t.index ["ekn_id", "created_at"], name: "index_api_calls_on_ekn_id_and_created_at"
    t.index ["ekn_id", "endpoint"], name: "index_api_calls_on_ekn_id_and_endpoint"
    t.index ["ekn_id"], name: "index_api_calls_on_ekn_id"
    t.index ["model_used"], name: "index_api_calls_on_model_used"
    t.index ["request_id"], name: "index_api_calls_on_request_id"
    t.index ["service_name", "status", "created_at"], name: "index_api_calls_on_service_name_and_status_and_created_at"
    t.index ["service_name"], name: "index_api_calls_on_service_name"
    t.index ["session_id", "created_at"], name: "index_api_calls_on_session_id_and_created_at"
    t.index ["session_id"], name: "index_api_calls_on_session_id"
    t.index ["status"], name: "index_api_calls_on_status"
    t.index ["trackable_type", "trackable_id"], name: "idx_api_calls_trackable"
    t.index ["trackable_type", "trackable_id"], name: "index_api_calls_on_trackable"
    t.index ["type", "created_at"], name: "index_api_calls_on_type_and_created_at"
    t.index ["type", "model_used", "created_at"], name: "index_api_calls_on_type_and_model_used_and_created_at"
    t.index ["type"], name: "index_api_calls_on_type"
    t.index ["user_id", "created_at"], name: "index_api_calls_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_api_calls_on_user_id"
  end

  create_table "conversation_histories", force: :cascade do |t|
    t.string "conversation_id"
    t.string "user_id"
    t.string "role"
    t.text "content"
    t.jsonb "metadata"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_conversation_histories_on_conversation_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "ingest_batch_id"
    t.jsonb "context", default: {}
    t.jsonb "model_config", default: {}
    t.string "status"
    t.string "expertise_level"
    t.datetime "last_activity_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ekn_id"
    t.index ["ekn_id"], name: "index_conversations_on_ekn_id"
    t.index ["ingest_batch_id"], name: "index_conversations_on_ingest_batch_id"
    t.index ["last_activity_at"], name: "index_conversations_on_last_activity_at"
    t.index ["status"], name: "index_conversations_on_status"
  end

  create_table "ekn_pipeline_runs", force: :cascade do |t|
    t.bigint "ekn_id", null: false
    t.bigint "ingest_batch_id", null: false
    t.string "status", default: "initialized", null: false
    t.string "current_stage"
    t.integer "current_stage_number", default: 0
    t.jsonb "stage_statuses", default: {}
    t.jsonb "stage_metrics", default: {}
    t.datetime "stage_started_at"
    t.datetime "stage_completed_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "total_items_processed", default: 0
    t.integer "total_nodes_created", default: 0
    t.integer "total_relationships_created", default: 0
    t.float "literacy_score"
    t.string "failed_stage"
    t.text "error_message"
    t.jsonb "error_details", default: {}
    t.integer "retry_count", default: 0
    t.datetime "last_retry_at"
    t.jsonb "options", default: {}
    t.boolean "auto_advance", default: true
    t.boolean "skip_failed_items", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["current_stage"], name: "index_ekn_pipeline_runs_on_current_stage"
    t.index ["ekn_id", "created_at"], name: "index_ekn_pipeline_runs_on_ekn_id_and_created_at"
    t.index ["ekn_id", "status"], name: "index_ekn_pipeline_runs_on_ekn_id_and_status"
    t.index ["ekn_id"], name: "index_ekn_pipeline_runs_on_ekn_id"
    t.index ["ingest_batch_id"], name: "index_ekn_pipeline_runs_on_ingest_batch_id"
    t.index ["status"], name: "index_ekn_pipeline_runs_on_status"
  end

  create_table "ekns", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "initializing"
    t.string "domain_type", default: "general"
    t.string "personality", default: "friendly"
    t.integer "session_id"
    t.jsonb "metadata", default: {}
    t.jsonb "settings", default: {}
    t.integer "total_nodes", default: 0
    t.integer "total_relationships", default: 0
    t.integer "total_items", default: 0
    t.float "literacy_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.index ["metadata"], name: "index_ekns_on_metadata", using: :gin
    t.index ["session_id"], name: "index_ekns_on_session_id"
    t.index ["slug"], name: "index_ekns_on_slug", unique: true
    t.index ["status"], name: "index_ekns_on_status"
  end

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

# Could not dump table "embeddings" because of following StandardError
#   Unknown type 'vector(1536)' for column 'embedding'


  create_table "evidence_experiences", force: :cascade do |t|
    t.bigint "evidence_id", null: false
    t.bigint "experience_id", null: false
    t.string "relation_type", default: "supports"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["evidence_id", "experience_id"], name: "index_evidence_experiences_on_evidence_id_and_experience_id", unique: true
    t.index ["evidence_id"], name: "index_evidence_experiences_on_evidence_id"
    t.index ["experience_id"], name: "index_evidence_experiences_on_experience_id"
  end

  create_table "evidences", force: :cascade do |t|
    t.string "evidence_type", null: false
    t.text "description", null: false
    t.jsonb "source_refs", default: []
    t.float "confidence_score"
    t.jsonb "corroboration", default: []
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "observed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["confidence_score"], name: "index_evidences_on_confidence_score"
    t.index ["evidence_type"], name: "index_evidences_on_evidence_type"
    t.index ["observed_at"], name: "index_evidences_on_observed_at"
    t.index ["provenance_and_rights_id"], name: "index_evidences_on_provenance_and_rights_id"
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

  create_table "fine_tune_jobs", force: :cascade do |t|
    t.string "openai_job_id", null: false
    t.string "openai_file_id"
    t.string "base_model", null: false
    t.string "fine_tuned_model"
    t.string "status", null: false
    t.jsonb "hyperparameters", default: {}
    t.jsonb "training_metrics", default: {}
    t.integer "trained_tokens"
    t.decimal "training_cost", precision: 10, scale: 4
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.bigint "ingest_batch_id"
    t.string "dataset_path"
    t.integer "example_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fine_tuned_model"], name: "index_fine_tune_jobs_on_fine_tuned_model"
    t.index ["ingest_batch_id"], name: "index_fine_tune_jobs_on_ingest_batch_id"
    t.index ["openai_job_id"], name: "index_fine_tune_jobs_on_openai_job_id", unique: true
    t.index ["status"], name: "index_fine_tune_jobs_on_status"
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
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
    t.decimal "literacy_score"
    t.bigint "ekn_id"
    t.jsonb "literacy_gaps"
    t.jsonb "deliverables"
    t.string "fine_tune_dataset_path"
    t.string "fine_tune_job_id"
    t.index ["created_at"], name: "index_ingest_batches_on_created_at"
    t.index ["ekn_id"], name: "index_ingest_batches_on_ekn_id"
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
    t.string "graph_status"
    t.jsonb "graph_metadata"
    t.string "embedding_status"
    t.jsonb "embedding_metadata"
    t.boolean "training_eligible"
    t.boolean "publishable"
    t.boolean "quarantined"
    t.string "quarantine_reason"
    t.string "file_hash"
    t.integer "file_size"
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

  create_table "interview_sessions", force: :cascade do |t|
    t.string "session_id"
    t.jsonb "data"
    t.boolean "completed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_interview_sessions_on_session_id"
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

  create_table "log_items", force: :cascade do |t|
    t.uuid "uuid", null: false
    t.bigint "log_id", null: false
    t.integer "num"
    t.string "log_label"
    t.string "status"
    t.text "text"
    t.jsonb "item_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["log_id"], name: "index_log_items_on_log_id"
    t.index ["uuid"], name: "index_log_items_on_uuid", unique: true
  end

  create_table "logs", force: :cascade do |t|
    t.uuid "uuid", null: false
    t.string "loggable_type", null: false
    t.bigint "loggable_id", null: false
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["loggable_type", "loggable_id"], name: "index_logs_on_loggable"
    t.index ["uuid"], name: "index_logs_on_uuid", unique: true
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

  create_table "manifest_spatials", force: :cascade do |t|
    t.bigint "manifest_id", null: false
    t.bigint "spatial_id", null: false
    t.string "relation_type", default: "located_at"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["manifest_id", "spatial_id"], name: "index_manifest_spatials_on_manifest_id_and_spatial_id", unique: true
    t.index ["manifest_id"], name: "index_manifest_spatials_on_manifest_id"
    t.index ["spatial_id"], name: "index_manifest_spatials_on_spatial_id"
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

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.integer "role"
    t.text "content"
    t.jsonb "metadata"
    t.integer "tokens_used"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "method_pool_practicals", force: :cascade do |t|
    t.bigint "method_pool_id", null: false
    t.bigint "practical_id", null: false
    t.string "relation_type", default: "implements"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["method_pool_id", "practical_id"], name: "idx_on_method_pool_id_practical_id_0f0229a2ca", unique: true
    t.index ["method_pool_id"], name: "index_method_pool_practicals_on_method_pool_id"
    t.index ["practical_id"], name: "index_method_pool_practicals_on_practical_id"
  end

  create_table "method_pools", force: :cascade do |t|
    t.string "method_name", null: false
    t.string "category"
    t.text "description", null: false
    t.jsonb "steps", default: []
    t.jsonb "prerequisites", default: []
    t.jsonb "outcomes", default: []
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_method_pools_on_category"
    t.index ["method_name"], name: "index_method_pools_on_method_name"
    t.index ["provenance_and_rights_id"], name: "index_method_pools_on_provenance_and_rights_id"
    t.index ["valid_time_start", "valid_time_end"], name: "index_method_pools_on_valid_time_start_and_valid_time_end"
  end

  create_table "negative_knowledges", force: :cascade do |t|
    t.bigint "batch_id"
    t.string "gap_type"
    t.text "gap_description"
    t.string "severity"
    t.text "affected_pools"
    t.text "impact"
    t.text "suggested_remediation"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_negative_knowledges_on_batch_id"
  end

  create_table "openai_settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "category"
    t.text "value"
    t.text "description"
    t.string "model_type"
    t.jsonb "metadata", default: {}
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_openai_settings_on_active"
    t.index ["category"], name: "index_openai_settings_on_category"
    t.index ["key"], name: "index_openai_settings_on_key", unique: true
    t.index ["model_type"], name: "index_openai_settings_on_model_type"
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

  create_table "prompt_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "service_class"
    t.text "system_prompt"
    t.text "user_prompt_template"
    t.jsonb "variables", default: []
    t.jsonb "metadata", default: {}
    t.boolean "active", default: true
    t.string "purpose"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_prompt_templates_on_active"
    t.index ["name"], name: "index_prompt_templates_on_name", unique: true
    t.index ["purpose"], name: "index_prompt_templates_on_purpose"
    t.index ["service_class"], name: "index_prompt_templates_on_service_class"
  end

  create_table "prompt_versions", force: :cascade do |t|
    t.bigint "prompt_id", null: false
    t.text "content"
    t.jsonb "variables"
    t.integer "status"
    t.integer "version_number"
    t.float "performance_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["prompt_id"], name: "index_prompt_versions_on_prompt_id"
  end

  create_table "prompts", force: :cascade do |t|
    t.string "key"
    t.string "name"
    t.text "description"
    t.integer "category"
    t.integer "context"
    t.boolean "active"
    t.integer "current_version_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_prompts_on_key", unique: true
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

  create_table "risk_practicals", force: :cascade do |t|
    t.bigint "risk_id", null: false
    t.bigint "practical_id", null: false
    t.string "relation_type", default: "mitigated_by"
    t.float "strength"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["practical_id"], name: "index_risk_practicals_on_practical_id"
    t.index ["risk_id", "practical_id"], name: "index_risk_practicals_on_risk_id_and_practical_id", unique: true
    t.index ["risk_id"], name: "index_risk_practicals_on_risk_id"
  end

  create_table "risks", force: :cascade do |t|
    t.string "risk_type", null: false
    t.string "severity"
    t.float "probability"
    t.text "description", null: false
    t.jsonb "mitigations", default: []
    t.jsonb "impacts", default: []
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["probability"], name: "index_risks_on_probability"
    t.index ["provenance_and_rights_id"], name: "index_risks_on_provenance_and_rights_id"
    t.index ["risk_type"], name: "index_risks_on_risk_type"
    t.index ["severity"], name: "index_risks_on_severity"
    t.index ["valid_time_start", "valid_time_end"], name: "index_risks_on_valid_time_start_and_valid_time_end"
  end

  create_table "sessions", force: :cascade do |t|
    t.string "browser_session_id", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["browser_session_id"], name: "index_sessions_on_browser_session_id", unique: true
  end

  create_table "spatials", force: :cascade do |t|
    t.string "location_name", null: false
    t.string "sector"
    t.string "portal"
    t.integer "year"
    t.jsonb "coordinates", default: {}
    t.jsonb "neighbors", default: []
    t.string "placement_type"
    t.text "description"
    t.text "repr_text", null: false
    t.bigint "provenance_and_rights_id", null: false
    t.datetime "valid_time_start", null: false
    t.datetime "valid_time_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_name"], name: "index_spatials_on_location_name"
    t.index ["portal"], name: "index_spatials_on_portal"
    t.index ["provenance_and_rights_id"], name: "index_spatials_on_provenance_and_rights_id"
    t.index ["sector"], name: "index_spatials_on_sector"
    t.index ["valid_time_start", "valid_time_end"], name: "index_spatials_on_valid_time_start_and_valid_time_end"
    t.index ["year"], name: "index_spatials_on_year"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name"
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "webhook_id", null: false
    t.datetime "timestamp", null: false
    t.string "signature"
    t.jsonb "headers", default: {}
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "processed_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}
    t.integer "retry_count", default: 0
    t.string "resource_type"
    t.string "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_webhook_events_on_created_at"
    t.index ["event_id"], name: "index_webhook_events_on_event_id", unique: true
    t.index ["event_type"], name: "index_webhook_events_on_event_type"
    t.index ["resource_type", "resource_id"], name: "index_webhook_events_on_resource_type_and_resource_id"
    t.index ["status"], name: "index_webhook_events_on_status"
    t.index ["webhook_id"], name: "index_webhook_events_on_webhook_id"
  end

  add_foreign_key "actor_experiences", "actors"
  add_foreign_key "actor_experiences", "experiences"
  add_foreign_key "actor_manifests", "actors"
  add_foreign_key "actor_manifests", "manifests"
  add_foreign_key "actors", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "api_calls", "ekns"
  add_foreign_key "conversations", "ekns"
  add_foreign_key "conversations", "ingest_batches"
  add_foreign_key "ekn_pipeline_runs", "ekns"
  add_foreign_key "ekn_pipeline_runs", "ingest_batches"
  add_foreign_key "emanation_ideas", "emanations"
  add_foreign_key "emanation_ideas", "ideas"
  add_foreign_key "emanation_relationals", "emanations"
  add_foreign_key "emanation_relationals", "relationals"
  add_foreign_key "emanations", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "evidence_experiences", "evidences"
  add_foreign_key "evidence_experiences", "experiences"
  add_foreign_key "evidences", "provenance_and_rights", column: "provenance_and_rights_id"
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
  add_foreign_key "ingest_batches", "ekns"
  add_foreign_key "ingest_items", "ingest_batches"
  add_foreign_key "ingest_items", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "intent_and_tasks", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "lexicon_and_ontologies", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "log_items", "logs"
  add_foreign_key "manifest_experiences", "experiences"
  add_foreign_key "manifest_experiences", "manifests"
  add_foreign_key "manifest_spatials", "manifests"
  add_foreign_key "manifest_spatials", "spatials"
  add_foreign_key "manifests", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "messages", "conversations"
  add_foreign_key "method_pool_practicals", "method_pools"
  add_foreign_key "method_pool_practicals", "practicals"
  add_foreign_key "method_pools", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "negative_knowledges", "ingest_batches", column: "batch_id"
  add_foreign_key "pipeline_artifacts", "pipeline_runs"
  add_foreign_key "pipeline_errors", "pipeline_runs"
  add_foreign_key "practical_ideas", "ideas"
  add_foreign_key "practical_ideas", "practicals"
  add_foreign_key "practicals", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "prompt_versions", "prompts"
  add_foreign_key "relationals", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "risk_practicals", "practicals"
  add_foreign_key "risk_practicals", "risks"
  add_foreign_key "risks", "provenance_and_rights", column: "provenance_and_rights_id"
  add_foreign_key "spatials", "provenance_and_rights", column: "provenance_and_rights_id"
end
