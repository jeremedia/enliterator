# Issue: Refactor to introduce proper EKN (Enliterated Knowledge Navigator) model

## Problem Statement

We're currently using `IngestBatch` as the top-level entity for Knowledge Navigators, but this is architecturally incorrect. An IngestBatch represents a single data import session, while an EKN represents a persistent, evolving knowledge domain that can receive multiple data imports over time.

### Current (Wrong) Architecture
```
IngestBatch (treated as the Knowledge Navigator)
├── IngestItems (files)
├── Neo4j database
├── PostgreSQL schema
└── Storage directory
```

### Correct Architecture
```
EKN (the actual Knowledge Navigator)
├── IngestBatch #1 (initial data import)
│   └── IngestItems
├── IngestBatch #2 (supplemental data)
│   └── IngestItems
├── IngestBatch #3 (updates)
│   └── IngestItems
├── Conversations (chat sessions)
├── Neo4j database (persistent)
├── PostgreSQL schema (persistent)
└── Storage directory (persistent)
```

## User Story

**As a user**, I want to:
1. Create a Knowledge Navigator about "chickens"
2. Add initial data (PDFs about chicken care)
3. Later add more data (breeding records)
4. Have conversations that reference ALL the data
5. See my EKN grow and improve over time

**Current problem**: Each IngestBatch creates a new isolated world, preventing knowledge accumulation.

## Proposed Solution

### 1. Create EKN Model

```ruby
# app/models/ekn.rb
class Ekn < ApplicationRecord
  # Associations
  belongs_to :user, optional: true  # For now, until auth is added
  has_many :ingest_batches, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :ingest_items, through: :ingest_batches
  
  # Validations
  validates :name, presence: true
  validates :status, inclusion: { in: %w[
    initializing active archived failed
  ]}
  
  # Status management
  enum status: {
    initializing: 'initializing',
    active: 'active',
    archived: 'archived',
    failed: 'failed'
  }
  
  # Resource naming
  def neo4j_database_name
    "ekn_#{id}"
  end
  
  def postgres_schema_name
    "ekn_#{id}"
  end
  
  def storage_root_path
    Rails.root.join('storage', 'ekns', id.to_s)
  end
  
  # Statistics
  def total_items
    ingest_items.count
  end
  
  def total_nodes
    # Query Neo4j for node count
  end
  
  def literacy_score
    # Weighted average of all batch literacy scores
    ingest_batches.where.not(literacy_score: nil)
                  .average(:literacy_score) || 0
  end
  
  # Resource management
  def ensure_resources_exist!
    ensure_neo4j_database_exists!
    ensure_postgres_schema_exists!
    ensure_storage_exists!
  end
  
  def destroy_resources!
    drop_neo4j_database!
    drop_postgres_schema!
    drop_all_storage!
  end
end
```

### 2. Update IngestBatch Model

```ruby
class IngestBatch < ApplicationRecord
  belongs_to :ekn  # NEW: Now belongs to an EKN
  has_many :ingest_items
  
  # Remove database/schema methods - delegate to EKN
  delegate :neo4j_database_name, :postgres_schema_name, 
           :storage_root_path, to: :ekn
  
  # This is now just a processing record
  def storage_path
    ekn.storage_root_path.join('batches', id.to_s)
  end
end
```

### 3. Database Migration

```ruby
class CreateEkns < ActiveRecord::Migration[8.0]
  def change
    create_table :ekns do |t|
      t.string :name, null: false
      t.text :description
      t.string :status, default: 'initializing'
      t.integer :user_id  # For future auth
      t.jsonb :metadata, default: {}
      t.jsonb :settings, default: {}
      
      # Statistics (cached)
      t.integer :total_nodes, default: 0
      t.integer :total_relationships, default: 0
      t.integer :total_items, default: 0
      t.float :literacy_score
      
      t.timestamps
    end
    
    add_index :ekns, :user_id
    add_index :ekns, :status
    
    # Add foreign key to ingest_batches
    add_reference :ingest_batches, :ekn, foreign_key: true
  end
end
```

### 4. Migration Strategy for Existing Data

```ruby
class MigrateIngestBatchesToEkns < ActiveRecord::Migration[8.0]
  def up
    # Create an EKN for each existing IngestBatch
    IngestBatch.find_each do |batch|
      ekn = Ekn.create!(
        name: batch.name || "Migrated Dataset #{batch.id}",
        description: "Migrated from IngestBatch ##{batch.id}",
        status: batch.status == 'completed' ? 'active' : 'initializing',
        metadata: {
          migrated_from_batch_id: batch.id,
          migrated_at: Time.current
        }
      )
      
      # Link the batch to its new EKN
      batch.update!(ekn_id: ekn.id)
      
      # Rename Neo4j database if it exists
      if batch.neo4j_database_exists?
        rename_neo4j_database(
          from: "ekn-#{batch.id}",  # Old naming
          to: "ekn_#{ekn.id}"       # New naming
        )
      end
      
      # Rename PostgreSQL schema if it exists
      if batch.postgres_schema_exists?
        rename_postgres_schema(
          from: "ekn_#{batch.id}",   # Old naming
          to: "ekn_#{ekn.id}"        # New naming
        )
      end
    end
  end
  
  def down
    # Remove EKN associations
    IngestBatch.update_all(ekn_id: nil)
    
    # Delete all EKNs
    Ekn.destroy_all
  end
end
```

### 5. Service Updates

#### EknManager Refactoring
```ruby
class EknManager
  def self.create_ekn(name:, description: nil, user: nil)
    ActiveRecord::Base.transaction do
      # Create the EKN record (not IngestBatch!)
      ekn = Ekn.create!(
        name: name,
        description: description,
        user: user,
        status: 'initializing'
      )
      
      # Create isolated resources
      ekn.ensure_resources_exist!
      
      # Mark as active
      ekn.update!(status: 'active')
      
      ekn
    end
  end
  
  def self.add_data_to_ekn(ekn:, files:)
    # Create a new IngestBatch under this EKN
    batch = ekn.ingest_batches.create!(
      source_type: 'upload',
      status: 'pending'
    )
    
    # Process files...
    PipelineRunner.new(batch).run!
    
    batch
  end
end
```

#### NavigatorController Updates
```ruby
class NavigatorController < ApplicationController
  before_action :load_ekn
  
  def index
    @conversations = @ekn.conversations.recent
  end
  
  def chat
    @conversation = @ekn.conversations.find_or_create_by(...)
    # Process chat...
  end
  
  private
  
  def load_ekn
    @ekn = Ekn.find(params[:ekn_id] || session[:current_ekn_id])
    # Ensure we're using the right database
    @database_name = @ekn.neo4j_database_name
  end
end
```

### 6. UI/UX Changes

#### New EKN Management Interface
```erb
<!-- app/views/ekns/index.html.erb -->
<h1>My Knowledge Navigators</h1>

<% @ekns.each do |ekn| %>
  <div class="ekn-card">
    <h3><%= ekn.name %></h3>
    <p><%= ekn.description %></p>
    <ul>
      <li>Created: <%= ekn.created_at %></li>
      <li>Data imports: <%= ekn.ingest_batches.count %></li>
      <li>Total items: <%= ekn.total_items %></li>
      <li>Literacy score: <%= ekn.literacy_score %>%</li>
    </ul>
    <%= link_to "Open Navigator", navigator_path(ekn) %>
    <%= link_to "Add Data", new_ekn_ingest_batch_path(ekn) %>
  </div>
<% end %>

<%= link_to "Create New EKN", new_ekn_path %>
```

### 7. Testing Strategy

1. **Model Tests**
   - EKN creation with resource isolation
   - Multiple IngestBatches per EKN
   - Resource cleanup on deletion

2. **Integration Tests**
   - Create EKN → Add data → Chat flow
   - Multiple data imports accumulating knowledge
   - Isolation between EKNs

3. **Migration Tests**
   - Existing IngestBatches properly migrated
   - Resources renamed correctly
   - No data loss

## Implementation Steps

1. **Phase 1: Create Models** (2 hours)
   - [ ] Create EKN model and migration
   - [ ] Update IngestBatch to belong_to EKN
   - [ ] Create data migration for existing records

2. **Phase 2: Update Services** (3 hours)
   - [ ] Refactor EknManager to work with EKN model
   - [ ] Update Graph services to use EKN's database
   - [ ] Update Embedding services to use EKN's database

3. **Phase 3: Update Controllers/Views** (2 hours)
   - [ ] Create EknsController for CRUD
   - [ ] Update NavigatorController to use EKN
   - [ ] Create EKN management views

4. **Phase 4: Testing & Migration** (2 hours)
   - [ ] Write comprehensive tests
   - [ ] Test migration with existing data
   - [ ] Update documentation

## Breaking Changes

1. **API Changes**
   - `IngestBatch.neo4j_database_name` → delegates to `ekn.neo4j_database_name`
   - `EknManager.create_ekn` returns `Ekn`, not `IngestBatch`

2. **Database Changes**
   - New `ekns` table
   - `ingest_batches` gets `ekn_id` foreign key
   - Database/schema naming changes from `ekn-{batch_id}` to `ekn_{ekn_id}`

## Benefits

1. **Proper Domain Modeling**: EKN represents the actual Knowledge Navigator
2. **Knowledge Accumulation**: Multiple data imports enhance the same EKN
3. **User Organization**: Users can manage multiple distinct knowledge domains
4. **Cleaner Architecture**: Clear separation between the navigator and import sessions
5. **Future-Proof**: Ready for user authentication and multi-tenancy

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Data loss during migration | Comprehensive backup before migration |
| Breaking existing workflows | Provide migration guide and compatibility layer |
| Performance with multiple batches | Implement proper indexing and caching |

## Success Criteria

1. Users can create named EKNs (e.g., "Chicken Knowledge")
2. Users can add data multiple times to the same EKN
3. Each EKN maintains complete isolation
4. Navigator shows cumulative knowledge from all batches
5. Clean migration of existing data

## Timeline

- Day 1: Create models and migrations
- Day 2: Update services and controllers
- Day 3: Testing and deployment

## Questions for Discussion

1. Should we support EKN templates (e.g., "Research Project", "Recipe Collection")?
2. Should EKNs have sharing/collaboration features?
3. Should we implement versioning/snapshots of EKNs?
4. What's the maximum number of EKNs per user?

---

**Priority**: HIGH
**Effort**: 1 week
**Impact**: Foundational - affects entire system architecture

This refactoring is essential for Enliterator to function as intended - as a system where users can create and grow multiple, persistent Knowledge Navigators.