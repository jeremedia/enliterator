class Navigator::AskController < ApplicationController
  def show
    ekn = Ekn.joins(:ingest_batches).where(ingest_batches: { status: "completed" }).first

    unless ekn
      render plain: "No EKN with complete data found", status: :not_found
      return
    end

    svc = Graph::NavigatorService.new(ekn: ekn)
    q = params[:question].presence || params[:q].presence

    if q
      # Answer a specific question using OpenAI
      ask_service = Navigator::AskService.new(ekn: ekn, question: q)
      @answer = ask_service.call
      @question = q
      @mode = params[:mode] || "conversation"
    else
      # Don't auto-run the full test - it's too slow
      # Instead show a form to test individual questions
      @batch_report = nil

      # Just calculate metrics without running all questions
      p "Calculating metrics for EKN: #{ekn.id}"
      metrics_service = Graph::StageMetrics.new(ekn: ekn, batch: ekn.ingest_batches.last)
      p "Metrics service initialized for EKN: #{ekn.id}"
      @metrics = metrics_service.calculate_all_metrics
    end
  end
end
