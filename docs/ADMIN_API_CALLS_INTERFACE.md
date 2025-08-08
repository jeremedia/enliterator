# Admin API Calls Interface

**Created**: August 2025  
**Purpose**: Comprehensive monitoring and analysis interface for all LLM API calls

## Overview

The Admin API Calls Interface provides a powerful, user-friendly web interface for monitoring, analyzing, and managing all API calls made to LLM providers (OpenAI, Anthropic, Ollama, etc.). Built with Rails and styled with Tailwind CSS, it offers real-time insights into API usage, costs, and performance.

## Features

### 1. Comprehensive Dashboard
- **Real-time Statistics**: View total calls, success rates, costs, and average response times
- **Provider Breakdown**: See usage distribution across different LLM providers
- **Quick Filters**: Access commonly used filters like "Today", "Expensive", "Failed", etc.
- **Export Capabilities**: Download data as CSV for external analysis

### 2. Advanced Filtering
The interface provides multiple filtering options:
- **Date Range**: Filter by custom date ranges
- **Provider**: Filter by OpenAI, Anthropic, Ollama, etc.
- **Model**: Filter by specific model (gpt-4, claude-3.5, llama3.1, etc.)
- **Service**: Filter by service that made the call
- **Status**: Filter by success, failed, rate_limited, timeout
- **Cost Range**: Find expensive calls
- **Response Time**: Identify slow calls
- **Search**: Full-text search across service names, endpoints, and errors

### 3. Sortable Columns
All columns support bidirectional sorting:
- Time (created_at)
- Provider
- Service
- Endpoint
- Model
- Status
- Tokens
- Cost
- Response Time

### 4. Detailed View
Each API call has a detailed view showing:
- **Basic Information**: Provider, service, endpoint, model, status
- **Performance Metrics**: Response time, processing time, queue time
- **Token Usage**: Prompt, completion, total, cached tokens
- **Cost Breakdown**: Input cost, output cost, total cost, cost per 1k tokens
- **Error Details**: Error codes, messages, and full error details
- **Request/Response Data**: Full JSON payloads (with sensitive data protection)
- **Related Records**: Links to associated database records
- **Tracking IDs**: Request IDs, batch IDs, session IDs

### 5. Pagination
Uses Kaminari gem for efficient pagination:
- Configurable items per page (default: 25)
- Shows current range and total count
- Smooth navigation between pages

## Accessing the Interface

### URLs
- **Main Interface**: http://localhost:3000/admin/api_calls
- **Dashboard**: http://localhost:3000/admin
- **Individual Call**: http://localhost:3000/admin/api_calls/:id
- **CSV Export**: http://localhost:3000/admin/api_calls/export.csv

### Navigation
1. Go to the Admin Dashboard
2. Click "API Call Tracking" in the Quick Actions section
3. Or navigate directly to `/admin/api_calls`

## Usage Examples

### Finding Expensive Calls
1. Use the "Quick Filter" dropdown and select "Expensive (>$0.10)"
2. Or set "Min Cost" filter to 0.10
3. Sort by "Cost" column to see most expensive first

### Analyzing Failures
1. Filter by Status = "Failed"
2. Look for patterns in error codes
3. Check response times to identify timeout issues
4. Use the "Retry" button on individual failed calls

### Performance Analysis
1. Filter by "Slow (>5s)" in Quick Filters
2. Sort by "Time (ms)" to find slowest calls
3. Group by model to identify slow models
4. Check queue times vs response times

### Cost Tracking
1. View "Today's Cost" in the dashboard stats
2. Filter by date range for specific periods
3. Export to CSV for detailed cost analysis
4. Monitor cost per 1k tokens for efficiency

## Visual Indicators

### Status Colors
- **Green**: Success
- **Red**: Failed
- **Yellow**: Rate Limited
- **Orange**: Timeout
- **Blue**: Pending
- **Gray**: Unknown

### Provider Colors
- **Green**: OpenAI
- **Purple**: Anthropic
- **Gray**: Ollama
- **Blue**: Other

### Cost Highlighting
- **Normal**: < $0.01
- **Orange**: $0.01 - $0.10
- **Red Bold**: > $0.10

### Response Time Highlighting
- **Normal**: < 2 seconds
- **Orange**: 2-5 seconds
- **Red Bold**: > 5 seconds

## Filters Reference

### Special Filters
- **Expensive**: Calls costing more than $0.10
- **Slow**: Calls taking more than 5 seconds
- **Failed**: All failed calls
- **Cached**: Calls that used cached responses
- **Today**: Calls made today
- **Yesterday**: Calls made yesterday
- **This Week**: Current week's calls
- **This Month**: Current month's calls

### Search Capabilities
The search field searches across:
- Service names
- Endpoints
- Error messages
- Request IDs

## Export Options

### CSV Export
Includes the following columns:
- ID
- Provider
- Service
- Endpoint
- Model
- Status
- Prompt Tokens
- Completion Tokens
- Total Tokens
- Input Cost
- Output Cost
- Total Cost
- Response Time (ms)
- Error Code
- Created At

### JSON Export (API)
Available at `/admin/api_calls.json` with same filter parameters

## Performance Considerations

### Database Indexes
The system includes optimized indexes for:
- Type (STI provider)
- Service name
- Model used
- Status
- Created at
- Composite indexes for common queries

### Query Optimization
- Uses includes() to prevent N+1 queries
- Efficient aggregation queries for stats
- Pagination to limit result sets

## Security

### Access Control
- Currently restricted to development environment
- In production, requires admin authentication
- Sensitive data truncation in request params

### Data Protection
- Request parameters truncated to prevent exposure
- Response data can be filtered
- User association for audit trails

## Troubleshooting

### No Data Showing
1. Check if API calls exist: `ApiCall.count` in Rails console
2. Clear filters and try again
3. Check date ranges

### Slow Loading
1. Add missing indexes if needed
2. Reduce per_page count
3. Use more specific filters

### Export Issues
1. Check for special characters in data
2. Verify CSV generation permissions
3. Try smaller date ranges

## Future Enhancements

Planned improvements include:
- Real-time updates via WebSockets
- Graphical charts and visualizations
- Automated alerting for anomalies
- Bulk operations (retry multiple, delete old)
- API endpoint comparison tools
- Cost prediction and budgeting
- Performance benchmarking
- Integration with monitoring tools

## Testing

Run the test script to verify the interface:
```bash
rails runner script/test_admin_api_calls.rb
```

This will:
- Check database status
- Test filtering options
- Verify controller actions
- Test route generation
- Check performance metrics
- Display recent API calls

## Conclusion

The Admin API Calls Interface provides comprehensive visibility into your LLM API usage, enabling:
- **Cost Control**: Track and optimize API spending
- **Performance Monitoring**: Identify and fix slow calls
- **Error Analysis**: Quickly diagnose and retry failures
- **Usage Insights**: Understand patterns and optimize usage
- **Compliance**: Audit trail for all API interactions

Use this interface to maintain efficient, cost-effective, and reliable LLM integrations!