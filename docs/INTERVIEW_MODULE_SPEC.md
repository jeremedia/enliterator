# Interview Module Specification
**Literate Interface for Dataset Creation and Preparation**

## Overview

The Interview module provides a conversational, literate interface for creating, supplying, and preparing datasets for the Enliterator pipeline. It guides users through the process of assembling data collections that can be successfully enliterated, ensuring all requirements are met before pipeline processing begins.

## Core Objectives

1. **Guided Data Collection**: Conversationally guide users through assembling complete datasets
2. **Rights & Provenance Capture**: Ensure all necessary rights and provenance information is collected upfront
3. **Pre-validation**: Validate data completeness and structure before pipeline ingestion
4. **Template-based Assembly**: Provide domain-specific templates for common dataset types
5. **Progressive Disclosure**: Start simple, reveal complexity as needed
6. **Literate Feedback**: Explain what's missing, why it matters, and how to fix it

## Key Components

### 1. Interview Engine
- Conversational state machine for data collection
- Adaptive questioning based on data type and domain
- Progress tracking and resumability
- Multi-modal input support (text, files, URLs, APIs)

### 2. Dataset Builder
- Incremental dataset assembly
- Automatic structure detection
- Relationship inference
- Metadata extraction

### 3. Validation Suite
- Pre-flight checks for pipeline readiness
- Rights completeness verification
- Minimum viable dataset assessment
- Quality scoring preview

### 4. Template Library
- Domain-specific interview templates
- Common dataset patterns
- Best practices and examples
- Custom template creation

## Interview Flow

### Phase 1: Discovery
```
Interview: "What kind of knowledge are you looking to enliterate?"
User: "I have 5 years of Burning Man camp placement data"
Interview: "Excellent! Camp placement data can reveal fascinating patterns. 
           Let me help you prepare this for enliteration. First, let's 
           understand what you have..."
```

### Phase 2: Assessment
- Inventory available data sources
- Identify core entities (camps, years, locations)
- Detect relationships and temporal patterns
- Assess current structure and format

### Phase 3: Rights & Provenance
```
Interview: "Before we proceed, let's establish the rights for this data.
           Can you tell me about the source and any usage restrictions?"
```
- Capture license/consent information
- Document data sources
- Establish publishability constraints
- Set training eligibility

### Phase 4: Gap Identification
```
Interview: "I notice we have camp names and locations, but we're missing
           the camp descriptions and themes. These would significantly 
           enhance the enliterated dataset. Would you like to add them?"
```
- Identify missing but valuable data
- Suggest enrichments
- Prioritize additions by impact

### Phase 5: Structuring
- Guide canonical naming
- Establish temporal fields
- Define spatial representations
- Map to Ten Pool Canon

### Phase 6: Preparation
```
Interview: "Great! Your dataset is nearly ready. Let me prepare it for
           the pipeline. I'll create a structured bundle with all the
           necessary metadata..."
```
- Generate intake-ready bundle
- Create manifest file
- Add processing hints
- Package for ingestion

## Implementation Structure

```
app/services/interview/
├── engine.rb                 # Core interview state machine
├── dataset_builder.rb        # Incremental dataset assembly
├── validators/
│   ├── completeness.rb      # Check data completeness
│   ├── rights.rb            # Verify rights/provenance
│   ├── structure.rb         # Validate structure
│   └── quality.rb           # Assess quality metrics
├── templates/
│   ├── base_template.rb     # Abstract template class
│   ├── event_data.rb        # Events/festivals template
│   ├── organization.rb      # Org/community template
│   ├── creative_works.rb    # Art/media template
│   └── knowledge_base.rb    # Documentation template
├── analyzers/
│   ├── entity_detector.rb   # Detect entities in raw data
│   ├── relationship_finder.rb # Find relationships
│   ├── temporal_analyzer.rb # Analyze time patterns
│   └── spatial_analyzer.rb  # Analyze location data
└── packager.rb              # Bundle for pipeline

app/controllers/interview_controller.rb  # Web interface
app/views/interview/                     # Interview UI views

lib/tasks/interview.rake                 # CLI interface
```

## User Interfaces

### 1. Web Interface
- Conversational chat interface
- Drag-and-drop file upload
- Progress visualization
- Real-time validation feedback

### 2. CLI Interface
```bash
# Start interactive interview
rails interview:start

# Use template
rails interview:from_template[event_data]

# Resume previous session
rails interview:resume[session_id]

# Validate existing dataset
rails interview:validate[path/to/data]
```

### 3. API Interface
```ruby
# Programmatic usage
interview = Interview::Engine.new
interview.start(domain: 'burning_man')
interview.add_data(source: 'camps.csv')
interview.set_rights(license: 'CC-BY-SA')
bundle = interview.prepare_for_pipeline
```

## Example Interview Session

```
$ rails interview:start

🎤 Welcome to Enliterator Interview!
   I'll help you prepare your data for enliteration.

📊 What type of knowledge would you like to work with?
   1. Event or festival data
   2. Organizational knowledge
   3. Creative works collection
   4. Research documentation
   5. Something else

> 1

🎪 Great choice! Event data often contains rich patterns.
   What event are we working with?

> Burning Man camps from 2018-2023

🏕️ Excellent! Camp data can reveal fascinating evolution patterns.
   What data do you currently have? (files, databases, APIs, etc.)

> I have CSV files with camp names, locations, and years

📁 Perfect! Let's start there. You can:
   - Drop the CSV files here
   - Provide a directory path
   - Paste a sample

> /data/burning_man/camps/

✅ Found 6 CSV files (2018-2023)
   Analyzing structure...

📊 I've identified:
   - 3,457 unique camps
   - 6 years of placements
   - Clock-based location system

⚠️ Opportunities to enhance your dataset:
   1. Camp descriptions/themes (HIGH impact)
   2. Camp contact info (MEDIUM impact)
   3. Art installations (MEDIUM impact)
   4. Infrastructure details (LOW impact)

   Would you like to add any of these?

> Let me add camp descriptions

📝 Great! How would you like to provide them?
   1. Additional CSV with descriptions
   2. API endpoint
   3. I'll help you structure them

> 1

📎 Please provide the descriptions file:

> /data/burning_man/camp_descriptions.csv

✅ Excellent! Matched 2,891 camps with descriptions.

📋 Now let's establish data rights.
   What's the source of this data?

> Burning Man Organization placement team

🔒 What usage rights apply?
   1. Public domain
   2. Creative Commons
   3. Internal use only
   4. Custom license

> 2

📜 Which Creative Commons license?
   1. CC-BY (Attribution)
   2. CC-BY-SA (Attribution-ShareAlike)
   3. CC-BY-NC (Attribution-NonCommercial)
   4. Other

> 2

✅ Rights recorded: CC-BY-SA

🎯 Can this data be used for AI training?

> Yes

✅ Training eligibility: Approved

🔍 Final check before preparation:
   
   Dataset: Burning Man Camps 2018-2023
   ├── Entities: 3,457 camps
   ├── Temporal: 6 years
   ├── Spatial: Clock/street coordinates
   ├── Descriptions: 84% coverage
   ├── Rights: CC-BY-SA
   └── Training: Eligible

   Ready to prepare for enliteration?

> Yes

📦 Preparing your dataset...
   ✓ Structuring entities
   ✓ Normalizing locations
   ✓ Establishing timeline
   ✓ Mapping to pools
   ✓ Creating manifest
   ✓ Packaging bundle

✅ Dataset prepared successfully!
   Bundle ID: bm_camps_2024_12_15
   Location: /tmp/enliterator/bundles/bm_camps_2024_12_15.zip

🚀 Ready for pipeline ingestion:
   rails enliterator:ingest[/tmp/enliterator/bundles/bm_camps_2024_12_15.zip]

💡 Tip: Your dataset has strong temporal and spatial patterns.
   The enliterated version will excel at questions like:
   - "How did theme camps migrate over time?"
   - "What camps consistently placed near Center Camp?"
   - "Which themes emerged post-pandemic?"

Thank you for preparing your data with Interview!
```

## Integration Points

### With Existing Pipeline
- Generates Stage 1 (Intake) compatible bundles
- Pre-populates Stage 2 (Rights) metadata
- Suggests Stage 3 (Lexicon) canonical terms
- Previews Stage 7 (Literacy) scoring

### With Future Features
- MCP tools for interview assistance
- Fine-tuned models for better entity detection
- Retrieval from existing graphs for enrichment

## Success Metrics

1. **Time to First Bundle**: < 10 minutes for simple datasets
2. **Completion Rate**: > 80% of started interviews
3. **Pipeline Success**: > 95% of interview-prepared bundles pass Stage 1
4. **Rights Completeness**: 100% have required rights metadata
5. **User Satisfaction**: Clear understanding of what was prepared and why

## Next Steps

1. Implement core Interview::Engine
2. Create first template (event_data)
3. Build CLI interface
4. Add web interface
5. Create validation suite
6. Document best practices
7. Add to main pipeline documentation

---

The Interview module transforms the often complex process of data preparation into a guided conversation, ensuring datasets are properly structured, documented, and ready for enliteration.