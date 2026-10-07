class AddExcludedPathsToChannelWebWidgets < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_web_widgets, :excluded_paths, :jsonb, default: []
  end
end
