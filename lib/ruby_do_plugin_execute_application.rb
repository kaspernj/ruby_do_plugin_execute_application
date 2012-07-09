class Ruby_do_plugin_execute_application < Ruby_do::Plugin::Base
  def initialize(*args, &block)
    super(*args, &block)
    
    #Find icon-paths to scan for icons.
    @icon_paths = []
    
    self.scan_icon_dir("/usr/share/pixmaps")
    self.scan_icon_dir("/usr/share/icons")
    
    @icon_exts = ["png", "xpm", "svg"]
    
    
    #Scan XDG-dirs for .desktop application files.
    @apps = []
    ENV["XDG_DATA_DIRS"].split(":").each do |val|
      path = "#{val}/applications"
      self.scan_dir(path) if File.exists?(path)
    end
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
    Dir.foreach(path) do |file|
      next if file[0, 1] == "."
      fp = "#{path}/#{file}"
      
      if File.directory?(fp)
        self.scan_dir(fp)
      else
        cont = File.read(fp)
        
        data = {}
        cont.scan(/^(.+?)=(.+)$/) do |match|
          data[match[0].to_s.downcase] = match[1]
        end
        
        icon_paths = []
        icon_path = nil
        
        if icon = data["icon"]
          if File.exists?(icon)
            icon_path = icon
          else
            @icon_paths.each do |path|
              @icon_exts.each do |ext|
                fp = "#{path}/#{icon}.#{ext}"
                if File.exists?(fp)
                  icon_paths << fp
                end
              end
            end
          end
        end
        
        if !icon_paths.empty?
          icon_paths.sort!(&self.method(:sortmethod))
          icon_path = icon_paths.first
        end
        
        if data["name"] and data["exec"]
          @apps << {
            :name => data["name"],
            :namel => data["name"].to_s.downcase,
            :exec => data["exec"],
            :icon => icon,
            :icon_path => icon_path
          }
        end
      end
    end
  end
  
  def on_options
    return {
      :widget => Gtk::Label.new("Test execute app")
    }
  end
  
  def on_search(args)
    return Enumerator.new do |yielder|
      @apps.each do |app|
        found_all = true
        args[:words].each do |word|
          if app[:namel].index(word) == nil
            found_all = false
            break
          end
        end
        
        if found_all
          yielder << Ruby_do::Plugin::Result.new(
            :plugin => self,
            :title => app[:name],
            :title_html => "<b>#{Knj::Web.html(app[:name])}</b>",
            :descr => sprintf(_("Open the application: '%1$s' with the command '%2$s'."), app[:name], app[:exec]),
            :exec => app[:exec],
            :icon => app[:icon_path]
          )
        end
      end
    end
  end
  
  def execute_result(args)
    Knj::Os.subproc(args[:res].args[:exec])
    return :close_win_main
  end
end