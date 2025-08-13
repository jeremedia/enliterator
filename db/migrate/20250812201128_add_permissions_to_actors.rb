class AddPermissionsToActors < ActiveRecord::Migration[8.0]
  def change
    add_column :actors, :permissions, :jsonb
  end
end
