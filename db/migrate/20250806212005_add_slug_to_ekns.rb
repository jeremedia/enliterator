class AddSlugToEkns < ActiveRecord::Migration[8.0]
  def change
    add_column :ekns, :slug, :string
    add_index :ekns, :slug, unique: true
  end
end
