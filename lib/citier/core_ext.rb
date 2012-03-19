class ActiveRecord::Base 
  
  def self.set_acts_as_citier(citier)
    @acts_as_citier = citier
  end
  
  def self.acts_as_citier?
    @acts_as_citier || false
  end

  def self.[](column_name) 
    arel_table[column_name]
  end

  def is_new_record(state)
    @new_record = state
  end

  def self.create_class_writable(class_reference)  #creation of a new class which inherits from ActiveRecord::Base
    Class.new(ActiveRecord::Base) do
      include Citier::InstanceMethods::ForcedWriters
      
      t_name = class_reference.table_name
      t_name = t_name[5..t_name.length]

      if t_name[0..5] == "view_"
        t_name = t_name[5..t_name.length]
      end

      # set the name of the table associated to this class
      # this class will be associated to the writable table of the class_reference class
      self.table_name = t_name
    end
  end
end

def create_citier_view(theclass)  #function for creating views for migrations 
  
  return unless theclass.acts_as_citier? #Security in case we call this on a non-citier model
  
  # flush any column info in memory
  # Loops through and stops once we've cleaned up to our root class.
  reset_class = theclass
  
  until reset_class == ActiveRecord::Base
    citier_debug("Resetting column information on #{reset_class}")
    reset_class.reset_column_information
    reset_class = reset_class.superclass
  end

  #Need to reset column information on the writable class
  theclass::Writable.reset_column_information
  #May not need to reset info on the superclass as it could have been covered above but worth doing. Won't harm hey?
  theclass.superclass.reset_column_information
  
  self_columns = theclass::Writable.column_names.select{ |c| c != "id" }
  parent_columns = theclass.superclass.column_names.select{ |c| c != "id" }
  columns = parent_columns+self_columns
  self_read_table = theclass.table_name
  self_write_table = theclass::Writable.table_name
  parent_read_table = theclass.superclass.table_name
  sql = "CREATE VIEW #{self_read_table} AS SELECT #{parent_read_table}.id, #{columns.join(',')} FROM #{parent_read_table}, #{self_write_table} WHERE #{parent_read_table}.id = #{self_write_table}.id" 
  
  #Use our rails_sql_views gem to create the view so we get it outputted to schema
  create_view "#{self_read_table}", "SELECT #{parent_read_table}.id, #{columns.join(',')} FROM #{parent_read_table}, #{self_write_table} WHERE #{parent_read_table}.id = #{self_write_table}.id" do |v|
    v.column :id
    columns.each do |c|
      v.column c.to_sym
    end
  end
  
  citier_debug("Creating citier view -> #{sql}")
  #theclass.connection.execute sql
  
 
end

def drop_citier_view(theclass) #function for dropping views for migrations 
  self_read_table = theclass.table_name
  sql = "DROP VIEW #{self_read_table}"
  
  drop_view(self_read_table.to_sym) #drop using our rails sql views gem
  
  citier_debug("Dropping citier view -> #{sql}")
  #theclass.connection.execute sql
end

def update_citier_view(theclass) #function for updating views for migrations
  
  citier_debug("Updating citier view for #{theclass}")
  
  if theclass.table_exists?
    drop_citier_view(theclass)
    create_citier_view(theclass)
  else
    citier_debug("Error: #{theclass} VIEW doesn't exist.")
  end
  
end

def create_or_update_citier_view(theclass) #Convienience function for updating or creating views for migrations
  
  citier_debug("Create or Update citier view for #{theclass}")
  
  if theclass.table_exists?
    update_citier_view(theclass)
  else
    citier_debug("VIEW DIDN'T EXIST. Now creating for #{theclass}")
    create_citier_view(theclass)
  end
  
end

# Used if you update the root model and want to update all subsequent views.
def update_all_citier_views_for_root_class(klass)
  
  # The condition for delete_if checks for...
  #We're only interested in classes which are in our acting class :)
  #Don't include our main class as there is no view
  #Delete anything that isn't a descendent of our class
   citier_classes = Dir['app/models/*.rb'].map {|f| File.basename(f, '.*').camelize.constantize }.delete_if do |the_class| 
     !the_class.respond_to?(:acts_as_citier?) || !the_class.acts_as_citier? || the_class == klass || the_class.base_class != klass  
   end
   
   #citier_debug("Updated ALL #{citier_classes}")
   #debugger
   #Now update all the relevent views
   citier_classes.each do |citier_class|
     update_citier_view(citier_class)
   end
   
end