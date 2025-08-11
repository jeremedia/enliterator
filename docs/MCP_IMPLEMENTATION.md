# MCP Implementation in Enliterator

## Critical Understanding

There are TWO different MCP patterns in this codebase:

### 1. MCP Server (What we built)
**Location**: `/api/v1/mcp/sse/`
**Purpose**: Enliterator acts as an MCP **server** that external clients (ChatGPT, Claude, etc.) can connect to
**Implementation**: 
- Uses SSE (Server-Sent Events)
- JSON-RPC 2.0 protocol
- Tools: search, fetch, bridge, extract_and_link, analyze_pools

### 2. MCP Client (Using OpenAI's Responses API)
**Purpose**: Enliterator uses external MCP servers or its own tools via OpenAI's Responses API
**Implementation**:
```ruby
OPENAI.responses.create(
  model: "gpt-5",
  input: messages,  # NOT "messages:"
  tools: [
    {
      type: "mcp",
      server_label: "enliterator",
      server_url: "https://e.dev.domt.app/api/v1/mcp/sse/",
      require_approval: "never"
    }
  ]
)
```

## CRITICAL RULES

1. **NEVER use `chat.completions` for MCP tools** - Only `responses.create` supports MCP
2. **NEVER use `response_format` with responses API** - Use response classes instead
3. **For JSON schema outputs without MCP**: Still use `chat.completions.create` with `response_format`
4. **For structured outputs with response classes**: Use `responses.create` with `text:` parameter

## API Patterns

### Pattern 1: Structured Output (Response Class)
```ruby
class MyResponse < OpenAI::Helpers::StructuredOutput::BaseModel
  required :field, String
end

OPENAI.responses.create(
  model: model,
  input: messages,
  text: MyResponse
)
```

### Pattern 2: JSON Schema Output (No MCP)
```ruby
OPENAI.chat.completions.create(
  model: model,
  messages: messages,
  response_format: {
    type: "json_schema",
    json_schema: {
      name: "extraction",
      strict: true,
      schema: { ... }
    }
  }
)
```

### Pattern 3: MCP Tool Usage
```ruby
OPENAI.responses.create(
  model: model,
  input: messages,
  tools: [{
    type: "mcp",
    server_label: "stripe",
    server_url: "https://mcp.stripe.com",
    headers: { "Authorization": "Bearer ..." }
  }]
)
```

## Current Status

- MCP Server: ✅ COMPLETE (serves tools to external clients)
- MCP Client: ❌ NOT IMPLEMENTED (would use responses.create with tools)
- JSON Schema Extraction: ✅ WORKS (uses chat.completions)

## Important Notes

1. The MCP tools in `/app/services/mcp/` are for SERVING, not consuming
2. These tools use `chat.completions` because they need JSON schema outputs
3. This is correct - they're not using MCP themselves, they're providing MCP to others
4. To use MCP tools internally, we'd need to refactor to use `responses.create` with `tools:`