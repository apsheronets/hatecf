module Local
  extend self

  DEFAULT_TARGET = { user: "root", port: 22 }.freeze
  attr_accessor :target
  @target = {}

  attr_accessor :as_user_block
  @as_user_block = false

  def print_location
    exclude = [
      "local.rb",
      "local_dsl.rb",
    ]
    caller.each do |line|
      $stderr.puts line unless exclude.find{|x| line.include? x}
    end
  end

  def die(message)
    $stderr.puts "Script error: #{message}"
    print_location
    exit 1
  end

  def type_check(name, value, *types)
    unless types.find{|x| value.is_a? x}
      case name
      when 1
        arg_dsc = "first argument"
      when 2
        arg_dsc = "second argument"
      when 3
        arg_dsc = "third argument"
      when Symbol
        arg_dsc = %{argument "#{name}:"}
      else
        arg_dsc = "argument"
      end
      if types.length > 1
        types_dsc = "types #{types.map(&:to_s).join(" or ")}"
      else
        types_dsc = "type #{types.first}"
      end
      hints = types.map do |t|
        case t.to_s
        when "LocalFile"
          %{LocalFile is a file on this very computer and could be defined as local_file("~/hello")}
        when "Regexp"
          "Regexp is a regular expression wrapped in /slashes/"
        else
          nil
        end
      end.compact.map{|x|"\nHint: #{x}"}.join
      die "#{arg_dsc} should be of #{types_dsc}, but #{value.class.to_s} here#{hints}"
    end
  end

  def check_mode(mode)
    mode = mode.to_i(8) if mode.is_a? String
    die "please supply up to 4 digits before the leading zero, example: 00644" if mode && mode >= 010000
  end

  attr_accessor :local_files
  @local_files = []

  require 'pathname'
  def copy_local_files_to(dir)
    @local_files.each do |local_file|
      # dublicating the whole directory stucture
      acc = []
      Pathname.new(local_file).each_filename do |chunk|
        source_path = File.join(*(['/'] + acc << chunk))
        dst = File.join([dir] + acc << chunk)
        if File.directory? source_path
          unless File.directory? dst
            debug "mkdir #{dst}"
            FileUtils.mkdir_p(dst)
          end
        else
          debug "cp #{source_path} #{dst}"
          FileUtils.cp(source_path, dst)
        end
        acc << chunk
      end
    end
  end

  require 'tmpdir'
  def perform!
    die "no target host specified!" if (@target[:host] || "").empty?
    script_path = File.expand_path(ENV["_"])
    script_dir = File.dirname(File.expand_path(ENV["_"]))
    status = nil
    Dir.mktmpdir "hatecf" do |tmp_dir|
      debug "using temporary dir #{tmp_dir}"
      FileUtils.cp(script_path, File.join(tmp_dir, "script.rb"))
      File.chmod(00777, File.join(tmp_dir, "script.rb"))
      FileUtils.cp(File.join(__dir__, "../remote/hatecf.rb"    ), tmp_dir)
      FileUtils.cp(File.join(__dir__, "../remote/remote_dsl.rb"), tmp_dir)
      FileUtils.cp(File.join(__dir__, "../remote/remote.rb"    ), tmp_dir)
      FileUtils.cp(File.join(__dir__, "../bootstrap_ruby"      ), tmp_dir)
      File.chmod(00777, File.join(tmp_dir, "bootstrap_ruby"))
      unless @local_files.empty?
        local_files_dir = File.join(tmp_dir, "local_files")
        FileUtils.mkdir local_files_dir
        copy_local_files_to(local_files_dir)
      end
      cmd = "tar -czP #{tmp_dir} | ssh #{@target[:user] || DEFAULT_TARGET[:user]}@#{@target[:host]} \"tar -xzP -C / && (cd #{tmp_dir} && ./bootstrap_ruby && RUBYLIB=. ./script.rb #{@dry_run ? "--dry " : " "}--local-home #{ENV["HOME"]} --local-script-dir #{script_dir}); rm -r #{tmp_dir}\""
      debug "executing: #{cmd}"
      pid, status = Process.wait2(Process.spawn(cmd))
      debug "exit status: #{status.exitstatus}"
    end
    exit status.exitstatus
  end

  require 'optparse'
  OptionParser.new do |opts|
    opts.on "--dry", "don't change anything, just test everything" do |x|
      @dry_run = true
    end
  end.parse!

  def debug(s)
  end

  def info(s)
    $stdout.puts s
    $stdout.flush
  end
end
