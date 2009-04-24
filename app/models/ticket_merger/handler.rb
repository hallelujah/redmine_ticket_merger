module TicketMerger
  
  
  class FileArtifact < StringIO
    attr_reader :content_type
    
    attr_reader :initialized
    attr_reader :original_filename
    attr_reader :path
    attr_reader :description
    
    def empty?
     (!initialized?) || size == 0 
   end
   
   def initialized?
     !! @initialized 
   end
    
    def initialize(path,original_name,description,files_with_mime_types,mode=nil)
      if File.exist?(path)
        super(File.read(path,mode)) 
        self.set_content_type_from_mime_types(files_with_mime_types)    
        @description = description
        @path = path
        @original_filename = original_name
        @initialized = true
      end
    end
    
    class << self
      
      def read(hash_for_files=[],files_with_mime_types={})  
        files_with_mime_types =  YAML.load(File.popen("file -i " + hash_for_files.collect{|hash| "'#{hash[:path]}'"}.join(' ') )) unless hash_for_files.blank?
        hash_for_files.collect do |hash| 
          self.new(hash[:path],hash[:original_filename],hash[:description],files_with_mime_types )
          end.delete_if(&:empty?).inject({}){|memo,f| memo[f.path] = f;memo}
        end        
      end
      
      protected
      
      def set_content_type_from_mime_types(files_with_mime_types={})
        @content_type = files_with_mime_types[self.path]
      end
      
    end
    
    
    class Handler
      # Pour l'instant le merge des tickets est destructif pour certaines parties.
      # TODO : Garder toutes les informations du ticket. Et pouvoir faire un rollback en cas de 
      
      attr_reader :from_issue
      attr_reader :to_issue
      attr_accessor :journals
      attr_accessor :unsaved_attachments
      attr_accessor :attached_attachments
      attr_accessor :time_entries
      
      def initialize(from,to)    
        @from_issue = Issue.find(from)
        @to_issue = Issue.find(to)     
        self.prepare
        self.save
      end
      
      def save
         @to_issue.save   
      end
      
      def separator
          "\n"
      end
      
      
      def time_entries
        @time_entries ||= []
      end
      
      def attached_attachments
        @attached_attachments ||= []        
      end
      
      def unsaved_attachments
        @unsaved_attachments ||= []        
      end
      
      protected
      
      # Merge the journals
      
      def merge_journals
        notes = ([from_issue] + from_issue.journals.find(:all,:order => "created_on ASC").collect(&:notes)).join(separator)
        self.journals = to_issue.journals.build(:user_id => to_issue.author_id, :notes => notes)
      end
      
      
      def merge_attachments   
        files_hash = from_issue.attachments.inject([]) do |memo,value|
          memo <<  {:path => value.diskfile, :original_filename =>  value.filename, :description => value.description}
        end
        attachments = FileArtifact.read(files_hash)
        # TODO : Create attachment observe if it was moved in the model in the future version of Redmine
        
        if attachments && attachments.is_a?(Hash)
          attachments.each_value do |attachment|
            
            next unless attachment && attachment.size > 0
            a = Attachment.create(:container => to_issue, 
                                  :file => attachment,
                                  :description => "Ticket##{from_issue.id} : " + attachment.description.to_s.strip,
                                  :author => to_issue.author)
            a.new_record? ? (self.unsaved_attachments << a) : (self.attached_attachments << a)
          end
          #          if unsaved.any?
          #            flash[:warning] = l(:warning_attachments_not_saved, unsaved.size)
          #          end
        end
        
      end
      
      # Clone the <tt>from_issue.time_entries</tt> 
      def merge_time_entries
        self.time_entries = to_issue.time_entries.build(from_issue.time_entries.map(&:attributes))
        self.time_entries.each do |te|
          te.comments = "Ticket ##{from_issue.id}: #{te.comments}"
          te.user_id = from_issue.author_id          
          te.project_id = from_issue.project_id
        end        
        self.to_issue.time_entries += self.time_entries
      end
      
      def prepare
        self.merge_journals
        self.merge_time_entries
        self.merge_attachments
      end
      
    end
  end
