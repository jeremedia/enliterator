# frozen_string_literal: true

# MCP (Model Context Protocol) Server Implementation for Enliterator
#
# This controller implements a complete MCP server using Server-Sent Events (SSE)
# for real-time communication with AI clients like ChatGPT, Claude, and custom applications.
#
# Architecture:
# - JSON-RPC 2.0 protocol over HTTP/SSE
# - Stateless tool-based architecture  
# - Real-time streaming responses
# - API key authentication
# - Graceful error handling
#
# Required tools for ChatGPT integration:
# - search: Returns array of results with id, title, text, url
# - fetch: Returns full document with id, title, text, url, metadata
#
module Api
  module V1
    module Mcp
      class McpController < ApplicationController
        include ActionController::Live  # Required for Server-Sent Events
        
        # Skip CSRF for API endpoints
        skip_before_action :verify_authenticity_token
        
        # Main SSE endpoint for MCP protocol communication
        # Supports both GET and POST for maximum client compatibility
        # URL must end with /sse/ for ChatGPT compatibility
        def sse
          # Stateless authentication - no sessions or CSRF
          unless valid_mcp_auth?
            render json: { error: "Unauthorized" }, status: :unauthorized
            return
          end
          
          # Configure SSE headers - CRITICAL for proper streaming
          response.headers["Content-Type"] = "text/event-stream"
          response.headers["Cache-Control"] = "no-cache"
          response.headers["Connection"] = "keep-alive"
          response.headers["X-Accel-Buffering"] = "no"  # Prevent nginx buffering
          response.headers["Access-Control-Allow-Origin"] = "*"  # CORS for SSE
          
          begin
            # Parse request - support both GET and POST
            if request.get?
              if params[:jsonrpc].present?
                message = {
                  "jsonrpc" => params[:jsonrpc],
                  "method" => params[:method],
                  "id" => params[:id],
                  "params" => params[:params] || {}
                }
              else
                # Empty GET - client establishing connection
                response.stream.write(": MCP Server Ready\n\n")
                response.stream.close
                return
              end
            else
              # POST request - JSON in body
              request_body = request.body.read
              
              if request_body.blank?
                # Empty POST - client establishing connection
                response.stream.write(": MCP Server Ready\n\n")
                response.stream.close
                return
              end
              
              message = JSON.parse(request_body)
            end
            
            # Log request for debugging
            Rails.logger.info "MCP Request: #{message['method']} (id: #{message['id']})"
            
            # Route message to appropriate handler
            result = handle_mcp_message(message)
            
            # Stream response using SSE format
            response.stream.write("event: message\n")
            response.stream.write("data: #{result.to_json}\n\n")
            
          rescue JSON::ParserError => e
            # JSON-RPC 2.0 Parse Error (-32700)
            error_response = {
              jsonrpc: "2.0",
              error: {
                code: -32700,
                message: "Parse error: #{e.message}"
              },
              id: nil
            }
            response.stream.write("event: error\n")
            response.stream.write("data: #{error_response.to_json}\n\n")
          rescue => e
            Rails.logger.error "MCP SSE error: #{e.message}"
            Rails.logger.error e.backtrace.first(10).join("\n")
            
            # JSON-RPC 2.0 Internal Error (-32603)
            error_response = {
              jsonrpc: "2.0",
              error: {
                code: -32603,
                message: "Internal error: #{e.message}"
              },
              id: message&.dig("id")
            }
            response.stream.write("event: error\n")
            response.stream.write("data: #{error_response.to_json}\n\n")
          ensure
            # CRITICAL: Always close stream to prevent connection leaks
            response.stream.close
          end
        end
        
        # Optional REST endpoint for testing
        def tools
          message = JSON.parse(request.body.read)
          result = handle_mcp_message(message)
          render json: result
        rescue JSON::ParserError => e
          render json: { error: "Invalid JSON: #{e.message}" }, status: :bad_request
        rescue => e
          Rails.logger.error "MCP tools error: #{e.message}"
          render json: { error: "Server error: #{e.message}" }, status: :internal_server_error
        end
        
        private
        
        # Main message router
        def handle_mcp_message(message)
          case message["method"]
          when "initialize"
            handle_initialize_request(message)
          when "tools/list"
            handle_tools_list_request(message)
          when "tools/call"
            handle_tool_call(message)
          else
            # JSON-RPC 2.0 Method Not Found (-32601)
            {
              jsonrpc: "2.0",
              error: {
                code: -32601,
                message: "Method not found: #{message['method']}"
              },
              id: message["id"]
            }
          end
        end
        
        # Handle initialization handshake
        def handle_initialize_request(message)
          # Support multiple protocol versions
          client_version = message.dig("params", "protocolVersion")
          supported_versions = ["2025-06-18", "2025-03-26", "0.1.0"]
          
          protocol_version = supported_versions.include?(client_version) ? client_version : "2025-06-18"
          
          {
            jsonrpc: "2.0",
            result: {
              protocolVersion: protocol_version,
              capabilities: {
                tools: {},
                experimental: {}
              },
              serverInfo: {
                name: "Enliterator MCP Server",
                version: "1.0.0",
                description: "Knowledge Navigator for Enliterated datasets via Ten Pool Canon",
                dataset: {
                  ekns: Ekn.count,
                  items: IngestItem.count,
                  entities: count_neo4j_nodes
                },
                tools_available: 2,  # search and fetch for ChatGPT
                capabilities: ["semantic_search", "entity_extraction", "relationship_discovery"],
                limits: {
                  max_top_k: 50,
                  max_relation_depth: 3,
                  max_text_length: 8000
                }
              }
            },
            id: message["id"]
          }
        end
        
        # Return list of available tools
        def handle_tools_list_request(message)
          {
            jsonrpc: "2.0",
            result: {
              tools: [
                {
                  name: "search",
                  description: "Search the knowledge graph for entities matching a query",
                  inputSchema: {
                    type: "object",
                    properties: {
                      query: {
                        type: "string",
                        description: "Natural language search query"
                      }
                    },
                    required: ["query"]
                  }
                },
                {
                  name: "fetch",
                  description: "Retrieve complete entity details with relationships",
                  inputSchema: {
                    type: "object",
                    properties: {
                      id: {
                        type: "string",
                        description: "Entity ID from search results"
                      }
                    },
                    required: ["id"]
                  }
                }
              ]
            },
            id: message["id"]
          }
        end
        
        # Execute tool calls
        def handle_tool_call(message)
          params = message["params"] || {}
          tool_name = params["name"]
          arguments = params["arguments"] || {}
          
          Rails.logger.info "Tool call: #{tool_name} with args: #{arguments.inspect}"
          
          # Route to appropriate tool service
          case tool_name
          when "search"
            result = ::Mcp::SearchTool.call(**arguments.symbolize_keys)
          when "fetch"
            result = ::Mcp::FetchTool.call(**arguments.symbolize_keys)
          else
            # Unknown tool error
            return {
              jsonrpc: "2.0",
              error: {
                code: -32602,
                message: "Unknown tool: #{tool_name}"
              },
              id: message["id"]
            }
          end
          
          # Format response according to MCP protocol
          # MCP requires results wrapped in content array
          {
            jsonrpc: "2.0",
            result: {
              content: [
                {
                  type: "text",
                  text: result.to_json
                }
              ]
            },
            id: message["id"]
          }
        rescue => e
          Rails.logger.error "Tool call error (#{tool_name}): #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
          
          {
            jsonrpc: "2.0",
            error: {
              code: -32603,
              message: "Tool execution failed: #{e.message}"
            },
            id: message["id"]
          }
        end
        
        # Validate API key authentication
        def valid_mcp_auth?
          auth_header = request.headers["Authorization"]
          api_key = request.headers["X-API-Key"]
          expected_key = ENV["MCP_API_KEY"] || "test-key-123"
          
          if auth_header&.start_with?("Bearer ")
            token = auth_header.split(" ").last
            return token == expected_key
          elsif api_key.present?
            return api_key == expected_key
          end
          
          false
        end
        
        # Helper to count Neo4j nodes
        def count_neo4j_nodes
          # Use the Meta-Enliterator EKN for stats
          ekn = Ekn.find_by(slug: 'meta-enliterator')
          return 0 unless ekn
          
          driver = Graph::Connection.instance.driver
          session = driver.session(database: ekn.neo4j_database_name)
          
          result = session.run("MATCH (n) RETURN count(n) as count")
          count = result.single[:count] || 0
          
          session.close
          count
        rescue => e
          Rails.logger.error "Failed to count Neo4j nodes: #{e.message}"
          0
        end
      end
    end
  end
end