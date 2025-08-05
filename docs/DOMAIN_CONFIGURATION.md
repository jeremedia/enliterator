# Enliterator Domain Configuration

## Port Assignment: 3077

The Enliterator application runs on port **3077** to avoid conflicts with other Rails applications.

## Configured Domains

| Domain | Target | Environment | Status |
|--------|--------|-------------|--------|
| **e.dev.domt.app** | http://100.104.170.10:3077 | Development | ✅ Active |
| **e.domt.app** | http://100.104.170.10:3077 | Production* | ✅ Active |

*Currently pointing to Mac for development. Will be updated to jer-serve (100.74.87.20) for production deployment.

## Infrastructure Setup

### 1. Caddy Proxy
Both domains are configured in the Caddy proxy server to forward HTTPS traffic to the Rails application:
- SSL certificates are automatically managed by Caddy
- HTTPS traffic on ports 443 is proxied to port 3077

### 2. DNS Configuration
A records have been created pointing to the Caddy server:
- e.dev.domt.app → 143.110.147.77
- e.domt.app → 143.110.147.77

### 3. Tailscale Network
The application is accessible within the Tailscale network:
- Mac development machine: 100.104.170.10
- jer-serve production: 100.74.87.20

## Starting the Application

The application is configured to automatically use port 3077:

```bash
# Start development server
bin/dev

# This will:
# - Start on port 3077
# - Display URLs for both domains
# - Allow connections from e.dev.domt.app and e.domt.app
```

## Rails Configuration

### Development Environment
```ruby
# config/environments/development.rb
config.hosts << "e.dev.domt.app"
config.hosts << "e.domt.app"
config.action_mailer.default_url_options = { 
  host: "e.dev.domt.app", 
  protocol: "https" 
}
```

### Production Environment
```ruby
# config/environments/production.rb
config.hosts = [
  "e.domt.app",
  "e.dev.domt.app",
  /.*\.domt\.app/
]
```

### Port Configuration
```bash
# bin/dev
export PORT="${PORT:-3077}"
```

## Access URLs

### Development
- **Primary**: https://e.dev.domt.app
- **Health Check**: https://e.dev.domt.app/up
- **Welcome Page**: https://e.dev.domt.app/

### Production (Future)
- **Primary**: https://e.domt.app
- **Health Check**: https://e.domt.app/up
- **API Endpoint**: https://e.domt.app/api/v1/

## Testing the Configuration

1. **Start the server**:
   ```bash
   bin/dev
   ```

2. **Test development domain**:
   ```bash
   curl -I https://e.dev.domt.app/up
   # Should return HTTP 200
   ```

3. **Test production domain** (currently pointing to Mac):
   ```bash
   curl -I https://e.domt.app/up
   # Should return HTTP 200
   ```

4. **View in browser**:
   - Navigate to https://e.dev.domt.app
   - You should see the Enliterator welcome page with pipeline status

## Troubleshooting

### Port Already in Use
If port 3077 is already in use:
```bash
# Find process using port 3077
lsof -i :3077

# Kill the process if needed
kill -9 [PID]
```

### Domain Not Resolving
Check DNS propagation:
```bash
dig e.dev.domt.app
dig e.domt.app
```

### Rails Host Authorization Error
If you see a host authorization error, ensure the domain is added to the allowed hosts in the appropriate environment file.

### SSL Certificate Issues
Caddy automatically manages SSL certificates. If there are issues:
```bash
# On the Caddy server
caddy reload
```

## Future Production Deployment

When ready to deploy to production on jer-serve:

1. Update the Caddy configuration to point e.domt.app to 100.74.87.20:3077
2. Deploy the Rails application to jer-serve
3. Update environment variables on jer-serve
4. Start the application with production settings

## Security Notes

- The application uses Rails host authorization to prevent DNS rebinding attacks
- All traffic is encrypted with HTTPS via Caddy
- The Tailscale network provides an additional layer of security
- Database connections are restricted to the local network

---

*Last Updated: 2025-08-05*