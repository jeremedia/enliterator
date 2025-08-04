# Enliterator GitHub Project Plan

## Overview

This document outlines the complete GitHub project structure for implementing Enliterator, a Rails 8 application that creates enliterated datasets with literate runtime capabilities.

### Current Progress Summary

✅ **Completed**:
- Rails 8 application initialized with PostgreSQL
- Docker Compose configured (PostgreSQL, Redis, Neo4j, MinIO)
- Solid Queue, Cache, and Cable setup
- Base service module structure created
- OpenAI client configured with Responses API v0.16.0
- CLAUDE.md updated with Responses API requirements
- Example MCP service demonstrating structured outputs

🚧 **In Progress**:
- Database migrations for core models

📋 **Upcoming**:
- Ten Pool Canon model implementation
- Zero-touch pipeline stages
- MCP server endpoints
- Fine-tuning pipeline
- Testing infrastructure

---

## Milestones & Issues

### Milestone 1: Foundation & Infrastructure ✅
**Status**: COMPLETED
**Goal**: Set up Rails 8 with all required services and basic structure

#### Completed Issues:
- [x] #1 Setup Rails 8 Application
- [x] #2 Configure External Services (Neo4j, Redis, pgvector, MinIO)
- [x] #3 Environment Configuration
- [x] #4 Base Application Structure

---

### Milestone 2: Core Data Models & Rights System 🚧
**Status**: IN PROGRESS
**Goal**: Implement the Ten Pool Canon with rights-aware foundation

#### Issues:
- [ ] #5 **Create ProvenanceAndRights Model**
  - Create migration and model
  - Implement publishability/training_eligibility derivation
  - Add consent status and license enums
  - Create rights checking service

- [ ] #6 **Create Core Pool Models Part 1**
  - Idea model with relationships
  - Manifest model with relationships
  - Experience model with relationships
  - Include HasRights and TimeTrackable concerns

- [ ] #7 **Create Core Pool Models Part 2**
  - Relational, Evolutionary, Practical models
  - Emanation model
  - Implement time fields (valid_time/observed_at)

- [ ] #8 **Lexicon & Ontology System**
  - Create LexiconAndOntology model
  - Implement surface forms tracking
  - Build normalization service
  - Cache canonical terms with Solid Cache

- [ ] #9 **Intent & Task Model**
  - Create IntentAndTask model
  - Add delivery extensions
  - Session state management

---

### Milestone 3: Pipeline Stages 1-3 (Intake to Lexicon)
**Status**: NOT STARTED
**Goal**: Implement early pipeline stages with Solid Queue jobs

#### Issues:
- [ ] #10 **Stage 0: Frame the Mission**
  - Create MissionFraming service
  - Maturity tier selection (M0-M6)
  - Generate evaluation question set

- [ ] #11 **Stage 1: Intake System**
  - Create Ingest::BundleProcessor job
  - File discovery and hashing
  - MIME type routing
  - Deduplication logic

- [ ] #12 **Stage 2: Rights & Provenance Triage**
  - Create Rights::TriageJob
  - License inference service
  - Quarantine system for ambiguous items
  - Rights derivation pipeline

- [ ] #13 **Stage 3: Lexicon Bootstrap**
  - Create Lexicon::BootstrapJob
  - Canonical term extraction
  - Surface form generation
  - Negative form detection

---

### Milestone 4: Pipeline Stages 4-6 (Extraction to Indices)
**Status**: NOT STARTED
**Goal**: Build knowledge extraction and graph assembly

#### Issues:
- [ ] #14 **Stage 4: Pool Filling**
  - Create Pools::ExtractionJob
  - OpenAI Structured Output integration
  - Entity extraction per pool
  - Relation extraction with verb glossary

- [ ] #15 **Stage 5: Graph Assembly**
  - Create Graph::AssemblyJob
  - Neo4j node/edge creation
  - Constraint enforcement
  - Duplicate resolution

- [ ] #16 **Graph Services**
  - Path textization service
  - Cypher query builders
  - Relationship management
  - Graph validation

- [ ] #17 **Stage 6: Representations & Retrieval**
  - Create Embedding::BuilderJob
  - Generate repr_text
  - pgvector index creation
  - Rights-aware filtering

---

### Milestone 5: Pipeline Stages 7-8 (Scoring to Delivery)
**Status**: NOT STARTED
**Goal**: Complete pipeline with evaluation and deliverables

#### Issues:
- [ ] #18 **Stage 7: Literacy Scoring**
  - Create Scoring::LiteracyJob
  - Coverage calculation
  - Flow density metrics
  - Gap report generation

- [ ] #19 **Stage 8: Deliverables Generation**
  - Create Deliverables::GeneratorJob
  - Promptpack assembly
  - Evaluation bundle creation
  - Change log generation

- [ ] #20 **Pipeline Orchestration**
  - Create Pipeline::Orchestrator
  - Stage dependencies management
  - Error handling and recovery
  - Progress tracking

- [ ] #21 **Acceptance Gates**
  - Implement gate validators
  - Rights verification
  - Path textization validation
  - Spatial summary checks

---

### Milestone 6: MCP Server Implementation
**Status**: NOT STARTED
**Goal**: Build the MCP server with all specified tools

#### Issues:
- [ ] #22 **MCP Server Foundation**
  - Setup MCP server structure
  - Authentication/authorization
  - Request validation framework
  - Audit logging

- [ ] #23 **Core MCP Tools**
  - Implement extract_and_link tool (STARTED - service exists)
  - Implement search tool
  - Implement fetch tool
  - Implement bridge tool

- [ ] #24 **Spatial & Persona Tools**
  - Implement location_neighbors tool
  - Implement set_persona/clear_persona
  - Style capsule generation
  - Spatial analysis services

- [ ] #25 **MCP Helper Tools**
  - Implement explain_path
  - Implement rights_check
  - Tool response formatting
  - Error handling

---

### Milestone 7: Fine-tuning Pipeline
**Status**: NOT STARTED
**Goal**: Build model training system for literate interface

#### Issues:
- [ ] #26 **Fine-tune Dataset Generation**
  - Create FineTune::DatasetBuilder
  - Canonical mapping examples
  - Path narration examples
  - Tool routing examples

- [ ] #27 **OpenAI Fine-tuning Integration**
  - Create FineTune::Trainer service
  - Model upload and training
  - Progress monitoring
  - Model deployment

- [ ] #28 **Runtime Router**
  - Create Runtime::Router
  - Query normalization
  - Tool selection logic
  - Response caching with Solid Cache

- [ ] #29 **Fine-tune Evaluation**
  - Accuracy metrics implementation
  - BLEU/ROUGE scoring
  - Rights compliance checking
  - Performance monitoring

---

### Milestone 8: Dialogue & Delivery System
**Status**: NOT STARTED
**Goal**: Implement conversation and artifact generation

#### Issues:
- [ ] #30 **Dialogue System**
  - Session state management
  - Gap-aware responses
  - Path explanation service
  - Context tracking

- [ ] #31 **Delivery Adapter Framework**
  - Base adapter interface
  - Preflight/postflight hooks
  - Rights checking integration
  - Citation management

- [ ] #32 **Delivery Adapters Part 1**
  - Webpage adapter
  - Markdown adapter
  - PDF adapter
  - Table/CSV adapter

- [ ] #33 **Delivery Adapters Part 2**
  - Map adapter
  - Timeline adapter
  - Outline adapter
  - Voice script adapter

---

### Milestone 9: Testing & Quality Assurance
**Status**: NOT STARTED
**Goal**: Comprehensive testing and performance optimization

#### Issues:
- [ ] #34 **Unit Test Coverage**
  - Model specs (100% coverage)
  - Service object specs
  - Job specs
  - Helper specs

- [ ] #35 **Integration Tests**
  - Pipeline end-to-end tests
  - MCP server integration tests
  - Graph operations tests
  - Rights enforcement tests

- [ ] #36 **Performance Optimization**
  - Query optimization
  - Caching strategies
  - Background job tuning
  - Database indexing

- [ ] #37 **Documentation**
  - API documentation
  - Developer guides
  - Deployment documentation
  - Architecture diagrams

---

### Milestone 10: Production Readiness
**Status**: NOT STARTED
**Goal**: Security, monitoring, and deployment

#### Issues:
- [ ] #38 **Security Hardening**
  - Authentication implementation
  - Rate limiting
  - Input sanitization
  - Security audit

- [ ] #39 **Monitoring & Observability**
  - OpenTelemetry setup
  - Custom metrics
  - Error tracking
  - Performance monitoring

- [ ] #40 **Deployment Configuration**
  - Production Docker setup
  - CI/CD pipeline
  - Database migrations strategy
  - Zero-downtime deployment

- [ ] #41 **Operational Tools**
  - Admin dashboard
  - Data import/export tools
  - Backup strategies
  - Maintenance mode

---

## Next Implementation Steps

Based on current progress, the immediate next steps are:

1. **Complete Milestone 2** - Core Data Models
   - Create database migrations for ProvenanceAndRights
   - Implement the Ten Pool Canon models
   - Set up model relationships and concerns

2. **Begin Milestone 3** - Pipeline Infrastructure
   - Create Solid Queue job base class
   - Implement Stage 1: Intake System
   - Set up file processing infrastructure

3. **Parallel Work**
   - Continue documenting API contracts
   - Set up RSpec testing framework
   - Create development seed data

---

## Development Guidelines

### Priorities
1. **Rights-first**: Every operation must check rights
2. **Test-driven**: Write tests before implementation
3. **Performance**: Monitor and optimize from the start
4. **Documentation**: Keep CLAUDE.md and API docs current

### Code Standards
- Follow Rails conventions
- Use service objects for business logic
- Implement comprehensive error handling
- Add performance metrics to critical paths

### Review Checklist
- [ ] Tests pass
- [ ] Rights checks implemented
- [ ] Performance benchmarks met
- [ ] Documentation updated
- [ ] Error handling complete