import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["metricsContainer", "loadingSpinner", "errorMessage"]
  static values = { 
    eknSlug: String,
    batchId: Number 
  }

  connect() {
    this.loadMetrics()
  }

  async loadMetrics() {
    // Show loading state
    if (this.hasLoadingSpinnerTarget) {
      this.loadingSpinnerTarget.classList.remove("hidden")
    }
    
    if (this.hasMetricsContainerTarget) {
      this.metricsContainerTarget.innerHTML = '<div class="text-gray-500 text-center py-8">Loading graph metrics...</div>'
    }

    try {
      const response = await fetch(`/ekn/${this.eknSlugValue}/ask/metrics?batch_id=${this.batchIdValue}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      
      // Hide loading spinner
      if (this.hasLoadingSpinnerTarget) {
        this.loadingSpinnerTarget.classList.add("hidden")
      }

      // Render metrics
      this.renderMetrics(data.metrics)
      
    } catch (error) {
      console.error('Error loading metrics:', error)
      this.showError('Failed to load graph metrics. Please try again.')
    }
  }

  renderMetrics(metrics) {
    if (!this.hasMetricsContainerTarget) return
    
    let html = ''
    
    // Graph Metrics Summary
    if (metrics.graph_metrics) {
      const gm = metrics.graph_metrics
      const gs = metrics.gate_status || {}
      
      html += `
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          <div class="bg-gray-50 rounded-lg p-4">
            <div class="text-sm font-medium text-gray-500">Total Nodes</div>
            <div class="mt-1 text-2xl font-semibold text-gray-900">
              ${this.formatNumber(gm.total_nodes)}
            </div>
            <div class="text-sm text-gray-600">
              ${this.formatNumber(gm.total_edges)} edges
            </div>
          </div>
          
          <div class="bg-gray-50 rounded-lg p-4">
            <div class="text-sm font-medium text-gray-500">Mean Degree</div>
            <div class="mt-1 text-2xl font-semibold ${gs.gates?.mean_degree?.passed ? 'text-green-600' : 'text-red-600'}">
              ${gm.mean_degree}
            </div>
            <div class="text-sm text-gray-600">
              Target: ≥ ${gs.gates?.mean_degree?.threshold || 0.3}
            </div>
          </div>
          
          <div class="bg-gray-50 rounded-lg p-4">
            <div class="text-sm font-medium text-gray-500">Graph Density</div>
            <div class="mt-1 text-2xl font-semibold text-gray-900">
              ${(gm.density * 100).toFixed(3)}%
            </div>
            <div class="text-sm text-gray-600">
              Edge coverage
            </div>
          </div>
      `
      
      if (metrics.coverage_metrics) {
        const cm = metrics.coverage_metrics
        html += `
          <div class="bg-gray-50 rounded-lg p-4">
            <div class="text-sm font-medium text-gray-500">Connected Coverage</div>
            <div class="mt-1 text-2xl font-semibold ${gs.gates?.lcc_coverage?.passed ? 'text-green-600' : 'text-red-600'}">
              ${(cm.lcc_coverage * 100).toFixed(1)}%
            </div>
            <div class="text-sm text-gray-600">
              Target: ≥ ${((gs.gates?.lcc_coverage?.threshold || 0.5) * 100).toFixed(0)}%
            </div>
          </div>
        `
      }
      
      html += '</div>'
    }
    
    // Pool Distribution
    if (metrics.graph_metrics?.pool_distribution) {
      html += `
        <div class="mb-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-3">Pool Distribution</h3>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
      `
      
      for (const [pool, count] of Object.entries(metrics.graph_metrics.pool_distribution)) {
        html += `
          <div class="bg-gray-50 rounded p-2">
            <div class="text-sm font-medium text-gray-600">${pool}</div>
            <div class="text-lg font-semibold text-gray-900">${this.formatNumber(count)}</div>
          </div>
        `
      }
      
      html += '</div></div>'
    }
    
    // Gate Status
    if (metrics.gate_status) {
      const gs = metrics.gate_status
      const statusColor = gs.all_passed ? 'green' : 'yellow'
      const iconPath = gs.all_passed 
        ? 'M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z'
        : 'M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z'
      
      html += `
        <div class="mb-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-3">Stage 5.5 Gate Status</h3>
          <div class="bg-${statusColor}-50 rounded-lg p-4">
            <div class="flex items-center">
              <svg class="h-5 w-5 text-${statusColor}-400 mr-2" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="${iconPath}" clip-rule="evenodd" />
              </svg>
              <span class="text-sm font-medium text-${statusColor}-800">
                ${gs.passed_count} of ${gs.total_gates} gates passed
              </span>
            </div>
            
            <div class="mt-3 space-y-2">
      `
      
      for (const [gateName, gateData] of Object.entries(gs.gates || {})) {
        html += `
          <div class="flex justify-between text-sm">
            <span class="text-gray-600">${this.humanize(gateName)}</span>
            <span class="font-medium ${gateData.passed ? 'text-green-600' : 'text-red-600'}">
              ${gateData.value} ${gateData.passed ? '✓' : '✗'}
            </span>
          </div>
        `
      }
      
      html += '</div></div></div>'
    }
    
    // Diversity Metrics
    if (metrics.diversity_metrics) {
      const dm = metrics.diversity_metrics
      const gs = metrics.gate_status || {}
      
      html += `
        <div class="mb-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-3">Relationship Diversity</h3>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="bg-gray-50 rounded-lg p-4">
              <div class="text-sm font-medium text-gray-500">Unique Verbs</div>
              <div class="mt-1 text-2xl font-semibold ${gs.gates?.verb_diversity?.passed ? 'text-green-600' : 'text-red-600'}">
                ${dm.unique_verbs}
              </div>
              <div class="text-sm text-gray-600">
                Target: ≥ ${gs.gates?.verb_diversity?.threshold || 3}
              </div>
            </div>
            
            <div class="bg-gray-50 rounded-lg p-4">
              <div class="text-sm font-medium text-gray-500">Verified Edges</div>
              <div class="mt-1 text-2xl font-semibold text-gray-900">
                ${dm.verified_edges}
              </div>
              <div class="text-sm text-gray-600">
                Total verified
              </div>
            </div>
            
            <div class="bg-gray-50 rounded-lg p-4">
              <div class="text-sm font-medium text-gray-500">Path Patterns</div>
              <div class="mt-1 text-2xl font-semibold text-gray-900">
                ${dm.unique_path_patterns}
              </div>
              <div class="text-sm text-gray-600">
                Unique patterns
              </div>
            </div>
          </div>
        </div>
      `
    }
    
    this.metricsContainerTarget.innerHTML = html
  }

  showError(message) {
    if (this.hasLoadingSpinnerTarget) {
      this.loadingSpinnerTarget.classList.add("hidden")
    }
    
    if (this.hasMetricsContainerTarget) {
      this.metricsContainerTarget.innerHTML = `
        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-red-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm text-red-700">${message}</p>
            </div>
          </div>
        </div>
      `
    }
  }

  formatNumber(num) {
    return new Intl.NumberFormat().format(num)
  }

  humanize(str) {
    return str.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())
  }
}