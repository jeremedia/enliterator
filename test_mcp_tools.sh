#!/bin/bash

# Test script for MCP tools
# Run with: bash test_mcp_tools.sh

BASE_URL="http://localhost:3077/api/v1/mcp/sse/"
API_KEY="test-key-123"

echo "================================="
echo "Testing MCP Tools"
echo "================================="
echo ""

# Test 1: List all tools
echo "1. Listing all available tools:"
echo "--------------------------------"
curl -X POST $BASE_URL \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/list",
    "params": {},
    "id": "test-list-1"
  }' 2>/dev/null | jq '.result.tools | map(.name)'

echo ""
echo ""

# Test 2: Bridge tool - Find path between two entities
echo "2. Testing bridge tool - Finding path between Radical Inclusion and Gratitude:"
echo "-------------------------------------------------------------------------------"
curl -X POST $BASE_URL \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "bridge",
      "arguments": {
        "a": "Radical Inclusion",
        "b": "Gratitude",
        "max_paths": 2
      }
    },
    "id": "test-bridge-1"
  }' 2>/dev/null | jq -r '.result.content[0].text' | jq '.'

echo ""
echo ""

# Test 3: Extract and Link tool
echo "3. Testing extract_and_link tool - Extracting entities from text:"
echo "-------------------------------------------------------------------"
curl -X POST $BASE_URL \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "extract_and_link",
      "arguments": {
        "text": "The principle of Radical Inclusion means that everyone is welcome at Burning Man. We celebrate the concept of Gifting, where participants give freely without expecting anything in return. The Temple provides a sacred space for reflection and remembrance.",
        "mode": "extract_and_link",
        "link_threshold": 0.6
      }
    },
    "id": "test-extract-1"
  }' 2>/dev/null | jq -r '.result.content[0].text' | jq '{
    mode: .mode,
    summary: .summary,
    entities_extracted: (.entities_extracted | length),
    entities_linked: (.entities_linked | length)
  }'

echo ""
echo ""

# Test 4: Analyze Pools tool
echo "4. Testing analyze_pools tool - Analyzing Ten Pool Canon distribution:"
echo "------------------------------------------------------------------------"
curl -X POST $BASE_URL \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "analyze_pools",
      "arguments": {
        "text": "Burning Man is an annual event held in the Black Rock Desert where participants create a temporary city based on ten principles. The Man, a large wooden effigy, is burned on Saturday night as thousands gather to witness this ritual. Art installations dot the landscape, while theme camps offer experiences ranging from music to workshops. The event happens in late August and early September.",
        "include_entities": true
      }
    },
    "id": "test-analyze-1"
  }' 2>/dev/null | jq -r '.result.content[0].text' | jq '{
    dominant_pool: .dominant_pool,
    distribution: .distribution,
    analysis: .analysis
  }'

echo ""
echo ""

# Test 5: Search tool (existing, but good to verify)
echo "5. Testing search tool - Searching for 'principles':"
echo "------------------------------------------------------"
curl -X POST $BASE_URL \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "search",
      "arguments": {
        "query": "principles"
      }
    },
    "id": "test-search-1"
  }' 2>/dev/null | jq -r '.result.content[0].text' | jq '.results | length'

echo ""
echo "================================="
echo "MCP Tools Test Complete!"
echo "================================="