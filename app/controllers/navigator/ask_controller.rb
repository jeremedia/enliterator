class Navigator::AskController < ApplicationController
  def show
    ekn = Ekn.joins(:ingest_batches).where(ingest_batches: { status: 'complete' }).first
    
    unless ekn
      render plain: "No EKN with complete data found", status: :not_found
      return
    end
    
    svc = Graph::NavigatorService.new(ekn: ekn)
    q = params[:q].presence
    
    if q
      # Answer a specific question
      @answer = svc.answer(q)
      @question = q
      @mode = params[:mode] || 'table'
    else
      # Run answerability test on top-50
      questions_config = YAML.load_file(Rails.root.join('config', 'top50.yml'))
      questions = questions_config['questions']
      
      @batch_report = svc.answerability_run(questions: questions)
      
      # Calculate whole-graph metrics for reporting
      metrics_service = Graph::StageMetrics.new(ekn: ekn, batch: ekn.ingest_batches.last)
      @metrics = metrics_service.calculate_all_metrics
    end
  end
end