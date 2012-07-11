class Ruby_do_plugin_execute_application < Ruby_do::Plugin::Base
  def start
    #Scan XDG-dirs for .desktop application files.
    dirs_scanned = []
    @results_found = []
    @debug = false
    
    #Do this in thread to avoid locking app.
    Thread.new do
      begin
        ENV["XDG_DATA_DIRS"].split(":").each do |val|
          val = val.to_s.gsub("//", "/").gsub(/\/$/, "")
          
          next if dirs_scanned.index(val) != nil
          dirs_scanned << val
          
          path = "#{val}/applications"
          self.scan_dir(path) if File.exists?(path)
        end
        
        #Delete static results which were not found after scanning.
        self.rdo_plugin_args[:rdo].ob.list(:Static_result, "plugin_id" => self.model.id, "id_not" => @results_found) do |sres|
          print "Deleting result because it not longer exists: '#{sres[:id_str]}'.\n" if @debug
          self.rdo_plugin_args[:rdo].ob.delete(sres)
        end
      rescue => e
        $stderr.puts "Error when updating 'execute_application'-plugin."
        $stderr.puts e.inspect
        $stderr.puts e.backtrace
      end
    end
  end
  
  def load_icons
    print "Loading icons.\n" if @debug
    
    #Find icon-paths to scan for icons.
    @icon_paths = []
    
    self.scan_icon_dir("/usr/share/pixmaps")
    self.scan_icon_dir("/usr/share/icons")
    
    @icon_exts = ["png", "xpm", "svg"]
  end
  
  def scan_icon_dir(path)
    @icon_paths << path
    
    Dir.foreach(path) do |file|
      next if file[0, 1] == "."
      fp = "#{path}/#{file}"
      
      if File.directory?(fp)
        self.scan_icon_dir(fp)
      end
    end
  end
  
  def sortmethod(path1, path2)
    #puts "Paths (#{path1}, #{path2})"
    
    path1l = path1.downcase
    path2l = path2.downcase
    
    sizem1 = path1.match(/(\d+)x(\d+)/)
    sizem2 = path2.match(/(\d+)x(\d+)/)
    
    if path1l.index("highcontrast") != nil
      return 1
    elsif path2l.index("highcontrast") != nil
      return -1
    elsif sizem1 and sizem2
      return sizem2[1].to_i <=> sizem1[1].to_i
    else
      return path2 <=> path1
    end
  end
  
  def scan_dir(path)
    print "Path: #{path}\n" if @debug
    
    Dir.foreach(path) do |file|
      next if file[0, 1] == "."
      fp = "#{path}/#{file}".gsub("//", "/")
      
      if File.directory?(fp)
        self.scan_dir(fp)
      else
        if sres = self.static_result_get(fp) and fp.to_s.downcase.index("poedit") == nil
          @results_found << sres.id
          print "Skipping because exists: #{fp}\n" if @debug
          next
        end
        
        cont = File.read(fp)
        
        data = {}
        cont.scan(/^(.+?)=(.+)$/) do |match|
          data[match[0].to_s.downcase] = match[1]
        end
        
        if !data["name"] or !data["exec"]
          print "Skipping because no name or no exec: #{fp}\n" if @debug
          next
        end
        
        icon_paths = []
        icon_path = nil
        
        [data["icon"], data["name"]].each do |icon|
          next if icon.to_s.strip.empty?
          
          if icon
            icon_paths << icon if File.exists?(icon)
            
            self.load_icons if !@icon_paths
            @icon_paths.each do |path|
              icon_fp = "#{path}/#{icon}"
              icon_paths << icon_fp if File.exists?(icon_fp)
              
              @icon_exts.each do |ext|
                icon_fp = "#{path}/#{icon}.#{ext}"
                icon_paths << icon_fp if File.exists?(icon_fp)
              end
            end
          end
        end
        
        if !icon_paths.empty?
          icon_paths.sort!(&self.method(:sortmethod))
          icon_path = icon_paths.first
        end
        
        print "Registering: #{fp}\n" if @debug
        exec_data = data["exec"].gsub("%U", "").gsub("%F", "").strip
        res = self.register_static_result(
          :id_str => fp,
          :title => data["name"],
          :descr => sprintf(_("Open the application: '%1$s' with the command '%2$s'."), data["name"], exec_data),
          :icon_path => icon_path,
          :data => {
            :exec => exec_data
          }
        )
        
        @results_found << res[:sres].id
      end
    end
  end
  
  def on_options
    return {
      :widget => Gtk::Label.new("Test execute app")
    }
  end
  
  def execute_static_result(args)
    Knj::Os.subproc(args[:sres].data[:exec])
    return :close_win_main
  end
end