# EKN Dynamic UI Generation Specification

## Vision
Enable the Enliterator Knowledge Navigator (EKN) to generate, modify, and compose user interfaces through natural language conversation, making data exploration as simple as having a dialogue with a knowledgeable colleague who can instantly create any visualization you need.

## Core Concept
The EKN acts as an **AI UI Designer** that:
- Understands user intent from natural language
- Selects appropriate visualization components
- Composes multi-component interfaces
- Modifies UIs based on feedback
- Learns from successful patterns

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   User Conversation                      │
│          "Show me how camps evolved after COVID"         │
└─────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────┐
│              Intent & Context Analysis                   │
│   - Temporal analysis needed (evolution)                 │
│   - Comparison required (before/after)                   │
│   - Data pools: Evolutionary, Manifest, Experience       │
└─────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────┐
│              UI Pattern Selection                        │
│   - Primary: Split Timeline                              │
│   - Secondary: Statistical Comparison                    │
│   - Interactions: Zoom, Filter, Drill-down              │
└─────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────┐
│           UI Specification Generation                    │
│   {                                                      │
│     "component": "split-timeline",                       │
│     "data_query": "MATCH (e:Evolutionary)...",          │
│     "config": { "split_point": "2020-03-01" }          │
│   }                                                      │
└─────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────┐
│            Component Rendering                           │
│   <DynamicUI spec={uiSpec} onInteraction={...} />      │
└─────────────────────────────────────────────────────────┘
```

## Implementation Components

### 1. UI Pattern Recognition Service

```ruby
# app/services/ui/pattern_recognizer.rb
module UI
  class PatternRecognizer
    # Analyze user request to determine UI needs
    def analyze(user_request, context = {})
      {
        intent: extract_intent(user_request),
        data_patterns: identify_data_patterns(user_request),
        suggested_components: suggest_components(user_request),
        interaction_needs: determine_interactions(user_request, context)
      }
    end
    
    private
    
    def extract_intent(request)
      case request.downcase
      when /evolv|chang|transform|progress/
        :temporal_evolution
      when /connect|relat|network|influenc/
        :relationship_exploration  
      when /where|locat|map|geographic/
        :spatial_analysis
      when /compar|versus|different/
        :comparative_analysis
      when /explore|browse|investigate/
        :open_exploration
      else
        :general_query
      end
    end
    
    def identify_data_patterns(request)
      patterns = []
      patterns << :temporal if request.match?(/\d{4}|year|month|time|when/)
      patterns << :spatial if request.match?(/where|location|place/)
      patterns << :categorical if request.match?(/type|category|kind/)
      patterns << :quantitative if request.match?(/how many|count|amount/)
      patterns
    end
    
    def suggest_components(request)
      components = []
      
      # Primary component based on intent
      components << case extract_intent(request)
      when :temporal_evolution then 'timeline'
      when :relationship_exploration then 'network-graph'
      when :spatial_analysis then 'map'
      when :comparative_analysis then 'comparison-chart'
      else 'data-table'
      end
      
      # Additional components based on patterns
      components << 'filter-panel' if request.match?(/filter|only|specific/)
      components << 'statistics-panel' if request.match?(/stats|metrics|numbers/)
      
      components
    end
  end
end
```

### 2. UI Specification DSL

```ruby
# app/models/ui_specification.rb
class UISpecification
  include ActiveModel::Model
  
  attr_accessor :component, :data_query, :config, :interactions, :layout
  
  # DSL for building UI specifications
  class Builder
    def initialize
      @spec = UISpecification.new
    end
    
    def component(type, **options)
      @spec.component = type
      @spec.config = options
      self
    end
    
    def with_data(query)
      @spec.data_query = query
      self
    end
    
    def interactive(*interactions)
      @spec.interactions = interactions
      self
    end
    
    def layout(type = :single)
      @spec.layout = type
      self
    end
    
    def build
      @spec
    end
  end
  
  # Convert to JSON for frontend
  def to_json
    {
      component: component,
      dataQuery: data_query,
      config: config,
      interactions: interactions,
      layout: layout
    }.to_json
  end
end
```

### 3. Component Library Mapping

```yaml
# config/ui_components.yml
components:
  timeline:
    data_requirements: [temporal_field, entities]
    pools: [evolutionary, manifest]
    interactions: [zoom, pan, filter, select]
    variants:
      split: "Show before/after comparison"
      layered: "Multiple data series"
      animated: "Play through time"
    
  network-graph:
    data_requirements: [nodes, edges]
    pools: [relational, manifest, idea]
    interactions: [zoom, drag, filter, expand]
    variants:
      force: "Physics-based layout"
      hierarchical: "Tree structure"
      circular: "Circular layout"
    
  map:
    data_requirements: [coordinates, values]
    pools: [spatial, manifest]
    interactions: [zoom, pan, select, layer_toggle]
    variants:
      heat: "Density visualization"
      cluster: "Grouped points"
      choropleth: "Regions"
      
  comparison-chart:
    data_requirements: [categories, values]
    pools: [any]
    interactions: [filter, sort, drill_down]
    variants:
      bar: "Side-by-side bars"
      radar: "Multi-dimensional"
      scatter: "Correlation"
      
  data-table:
    data_requirements: [entities, attributes]
    pools: [any]
    interactions: [sort, filter, search, export]
    variants:
      simple: "Basic table"
      grouped: "Hierarchical groups"
      pivot: "Pivot table"
```

### 4. Natural Language to UI Specification

```ruby
# app/services/ui/natural_language_mapper.rb
module UI
  class NaturalLanguageMapper
    def initialize(ekn_model)
      @ekn = ekn_model
      @pattern_recognizer = PatternRecognizer.new
    end
    
    def process(user_request, conversation_context)
      # Analyze the request
      analysis = @pattern_recognizer.analyze(user_request, conversation_context)
      
      # Generate UI specification
      spec = UISpecification::Builder.new
      
      # Select primary component
      spec.component(analysis[:suggested_components].first)
      
      # Build data query based on pools needed
      query = build_query_for_intent(analysis[:intent])
      spec.with_data(query)
      
      # Add interactions
      spec.interactive(*analysis[:interaction_needs])
      
      # Determine layout
      if analysis[:suggested_components].size > 1
        spec.layout(:split)
      else
        spec.layout(:single)
      end
      
      spec.build
    end
    
    private
    
    def build_query_for_intent(intent)
      case intent
      when :temporal_evolution
        "MATCH (e:Evolutionary)-[:VERSION_OF]->(m:Manifest) 
         RETURN e, m ORDER BY e.observed_at"
      when :relationship_exploration
        "MATCH (n1)-[r:CONNECTS_TO|INFLUENCES|EMBODIES]->(n2) 
         RETURN n1, r, n2"
      when :spatial_analysis
        "MATCH (m:Manifest)-[:LOCATED_AT]->(s:Spatial) 
         RETURN m, s"
      else
        "MATCH (n) RETURN n LIMIT 100"
      end
    end
  end
end
```

### 5. Frontend Component Factory

```javascript
// app/javascript/knowledge_navigator/component_factory.js
import React from 'react';
import Timeline from './components/Timeline';
import NetworkGraph from './components/NetworkGraph';
import Map from './components/Map';
import ComparisonChart from './components/ComparisonChart';
import DataTable from './components/DataTable';

class ComponentFactory {
  static components = {
    'timeline': Timeline,
    'network-graph': NetworkGraph,
    'map': Map,
    'comparison-chart': ComparisonChart,
    'data-table': DataTable
  };
  
  static create(spec, callbacks) {
    const Component = this.components[spec.component];
    
    if (!Component) {
      console.error(`Unknown component type: ${spec.component}`);
      return null;
    }
    
    return (
      <Component
        dataQuery={spec.dataQuery}
        config={spec.config}
        interactions={spec.interactions}
        onInteraction={callbacks.onInteraction}
        onDataRequest={callbacks.onDataRequest}
      />
    );
  }
  
  static compose(specs, layout) {
    switch(layout) {
      case 'split':
        return (
          <div className="split-view">
            {specs.map(spec => this.create(spec))}
          </div>
        );
      case 'tabs':
        return (
          <TabContainer>
            {specs.map(spec => 
              <Tab key={spec.component}>
                {this.create(spec)}
              </Tab>
            )}
          </TabContainer>
        );
      default:
        return this.create(specs[0]);
    }
  }
}
```

### 6. Dynamic UI React Component

```javascript
// app/javascript/knowledge_navigator/dynamic_ui.jsx
import React, { useState, useEffect } from 'react';
import ComponentFactory from './component_factory';

export default function DynamicUI({ conversation }) {
  const [uiSpec, setUiSpec] = useState(null);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  
  // Listen for UI generation requests from conversation
  useEffect(() => {
    conversation.on('generateUI', async (spec) => {
      setLoading(true);
      setUiSpec(spec);
      
      // Fetch data based on spec
      const data = await fetchDataForSpec(spec);
      setData(data);
      setLoading(false);
    });
    
    conversation.on('modifyUI', (modification) => {
      setUiSpec(prev => applyModification(prev, modification));
    });
  }, [conversation]);
  
  const handleInteraction = (interaction) => {
    // Send interaction back to EKN
    conversation.send('uiInteraction', interaction);
  };
  
  const handleDataRequest = (query) => {
    // Handle drill-down or data exploration
    conversation.send('dataRequest', query);
  };
  
  if (loading) {
    return <LoadingAnimation />;
  }
  
  if (!uiSpec) {
    return null;
  }
  
  return (
    <div className="dynamic-ui-container">
      {ComponentFactory.create(
        uiSpec,
        {
          onInteraction: handleInteraction,
          onDataRequest: handleDataRequest
        }
      )}
    </div>
  );
}
```

### 7. Training Data Generation

```ruby
# lib/tasks/ui_training.rake
namespace :ekn do
  namespace :ui do
    desc "Generate UI training data from successful interactions"
    task generate_training_data: :environment do
      training_data = []
      
      # Collect successful UI generation patterns
      UIGenerationLog.successful.find_each do |log|
        training_data << {
          messages: [
            {
              role: "user",
              content: log.user_request
            },
            {
              role: "assistant",
              content: log.ekn_response,
              function_call: {
                name: "generate_ui",
                arguments: log.ui_specification.to_json
              }
            }
          ]
        }
      end
      
      # Add modification examples
      UIModificationLog.successful.find_each do |log|
        training_data << {
          messages: [
            {
              role: "user",
              content: log.modification_request
            },
            {
              role: "assistant",
              content: log.ekn_response,
              function_call: {
                name: "modify_ui",
                arguments: {
                  current: log.before_spec,
                  modification: log.modification,
                  result: log.after_spec
                }.to_json
              }
            }
          ]
        }
      end
      
      # Save as JSONL
      File.open("tmp/ui_training_data.jsonl", "w") do |f|
        training_data.each { |data| f.puts data.to_json }
      end
      
      puts "Generated #{training_data.size} training examples"
    end
  end
end
```

### 8. UI Learning Loop

```ruby
# app/services/ui/learning_service.rb
module UI
  class LearningService
    def record_interaction(request, spec, outcome)
      UIGenerationLog.create!(
        user_request: request,
        ui_specification: spec,
        user_satisfaction: outcome[:satisfaction],
        interaction_time: outcome[:time_spent],
        successful: outcome[:task_completed]
      )
      
      # Learn from successful patterns
      if outcome[:satisfaction] >= 4
        learn_pattern(request, spec)
      end
    end
    
    def learn_pattern(request, spec)
      # Extract patterns from successful interactions
      pattern = {
        request_patterns: extract_linguistic_patterns(request),
        component_choice: spec.component,
        config_settings: spec.config,
        interaction_patterns: spec.interactions
      }
      
      # Store in pattern library
      UIPattern.create!(pattern)
      
      # Update EKN training if enough new patterns
      if UIPattern.unprocessed.count > 100
        FineTuneJob.perform_later('ui_generation')
      end
    end
    
    def suggest_ui_for(request)
      # Find similar successful patterns
      similar = UIPattern.similar_to(request).limit(5)
      
      # Combine best elements
      suggestion = UISpecification::Builder.new
      
      # Use most common component
      component = similar.group(:component_choice).count.first[0]
      suggestion.component(component)
      
      # Merge config settings
      config = similar.map(&:config_settings).reduce(&:merge)
      suggestion.config(config)
      
      suggestion.build
    end
  end
end
```

## Implementation Phases

### Phase 1: Template-Based UI (Week 1)
- Implement basic component library
- Create fixed UI templates
- Simple keyword mapping ("show timeline" → Timeline component)
- Basic data fetching

### Phase 2: Parameterized Generation (Week 2)
- Add configuration options to components
- Natural language parameter extraction
- Dynamic data queries based on request
- Basic layout options (single, split)

### Phase 3: Compositional UI (Week 3)
- Multi-component interfaces
- Component coordination (linked interactions)
- Complex layouts (tabs, grids, overlays)
- State management between components

### Phase 4: Modification & Refinement (Week 4)
- Natural language UI modifications
- Interactive refinement loop
- Preference learning
- Context-aware suggestions

### Phase 5: Full Generative UI (Week 5-6)
- Novel component combinations
- Custom layouts based on data shape
- Adaptive interfaces based on device/context
- Proactive UI suggestions

## Training Data Examples

```jsonl
{"messages": [{"role": "user", "content": "Show me how ideas evolved from 2018 to 2023"}, {"role": "assistant", "content": "I'll create a timeline showing the evolution of ideas over that period.", "ui_spec": {"component": "timeline", "config": {"start": "2018-01-01", "end": "2023-12-31", "groupBy": "idea_category"}, "data_query": "MATCH (i:Idea)-[:EVOLVED_INTO]->(i2:Idea) WHERE i.created_at >= '2018-01-01' AND i.created_at <= '2023-12-31' RETURN i, i2"}}]}

{"messages": [{"role": "user", "content": "Where are the main clusters of activity?"}, {"role": "assistant", "content": "Let me show you a heat map of activity clusters.", "ui_spec": {"component": "map", "config": {"type": "heat", "radius": 100}, "data_query": "MATCH (m:Manifest)-[:LOCATED_AT]->(s:Spatial) RETURN s.coordinates, count(m) as density"}}]}

{"messages": [{"role": "user", "content": "Compare pre and post pandemic patterns"}, {"role": "assistant", "content": "I'll create a split comparison view showing patterns before and after March 2020.", "ui_spec": {"component": "comparison-chart", "config": {"type": "split-timeline", "split_date": "2020-03-01"}, "data_query": "MATCH (e:Experience) RETURN e.observed_at, e.category, e.sentiment"}}]}

{"messages": [{"role": "user", "content": "Make the timeline bigger and add filters"}, {"role": "assistant", "content": "I'll expand the timeline and add filtering controls.", "ui_modification": {"resize": {"scale": 1.5}, "add_component": "filter-panel", "config": {"filters": ["category", "date_range", "keywords"]}}}]}
```

## Integration with Existing Enliterator

### Database Models
```ruby
# app/models/ui_generation_log.rb
class UIGenerationLog < ApplicationRecord
  belongs_to :conversation
  belongs_to :ingest_batch
  
  scope :successful, -> { where(successful: true) }
  scope :high_satisfaction, -> { where('user_satisfaction >= ?', 4) }
end

# app/models/ui_pattern.rb  
class UIPattern < ApplicationRecord
  scope :similar_to, ->(request) { 
    where("request_patterns @> ?", extract_patterns(request).to_json)
  }
  scope :unprocessed, -> { where(processed: false) }
end
```

### API Endpoints
```ruby
# app/controllers/api/ui_controller.rb
class Api::UIController < ApplicationController
  def generate
    spec = UI::NaturalLanguageMapper.new(current_ekn)
                                    .process(params[:request], session[:context])
    
    render json: spec
  end
  
  def modify
    modified = UI::ModificationService.new
                                     .apply(params[:current_spec], params[:modification])
    
    render json: modified
  end
  
  def record_feedback
    UI::LearningService.new.record_interaction(
      params[:request],
      params[:spec],
      params[:outcome]
    )
    
    head :ok
  end
end
```

## Success Metrics

### Technical Metrics
- UI generation latency < 500ms
- Component render time < 100ms
- Modification application < 200ms
- Training data generation > 1000 examples/week

### User Experience Metrics
- Correct component selection > 85%
- User satisfaction > 4.2/5
- Task completion rate > 80%
- Average modifications per UI < 2

### Learning Metrics
- Pattern recognition accuracy > 90%
- Novel UI combination success > 60%
- Preference prediction accuracy > 75%

## Key Principles

1. **UI as Data**: Treat UI specifications as data that can be stored, retrieved, and modified
2. **Progressive Enhancement**: Start simple, add complexity based on success
3. **Learn from Usage**: Every interaction improves future suggestions
4. **Natural Language First**: Never expose technical details to users
5. **Composable Components**: Build complex UIs from simple, reusable parts
6. **Context Awareness**: Consider conversation history and user preferences
7. **Fail Gracefully**: Always have a fallback visualization

## Conclusion

This system transforms the EKN from a conversational interface into a dynamic UI generator that understands data deeply and can create appropriate visualizations through natural dialogue. By treating UI generation as a learnable skill rather than hard-coded logic, the system continuously improves its ability to help users explore and understand their data.