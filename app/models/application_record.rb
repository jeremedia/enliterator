# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  
  # Enable PgSearch for all models
  include PgSearch::Model
  
  # Global configuration for PgSearch
  PgSearch.multisearch_options = {
    using: {
      tsearch: { prefix: true, dictionary: "english" },
      trigram: { threshold: 0.3 }
    }
  }
  
  # Make all models multisearchable by default on repr_text if present
  def self.inherited(child_class)
    super
    
    child_class.class_eval do
      if column_names.include?("repr_text")
        multisearchable against: :repr_text,
                        if: :searchable?
      end
    end
  end
  
  # Override in models to control searchability
  def searchable?
    # Only index records with proper rights
    respond_to?(:provenance_and_rights) && 
      provenance_and_rights.present? && 
      !provenance_and_rights.quarantined?
  end
end
