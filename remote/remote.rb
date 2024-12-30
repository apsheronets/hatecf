module Remote
  extend self

  # $HOME variable should be imported from local machine
  # in order to access ~/ paths
  # and directory of scrip should be imported
  # in order to access relative ./ paths
  attr_accessor :local_home, :local_script_dir

  class LocalFile
    attr_reader :local_path
    def initialize(local_path)
      @local_path = local_path
    end

    def remote_path
      raise "local home wasn't set!" if Remote.local_home.nil?
      # Temporary swapping $HOME for File.expand_path
      t_home = ENV["HOME"]
      begin
        $stdout.flush
        ENV["HOME"] = Remote.local_home
        # File.expand_path("~/dir") -> "/home/user/dir"
        # File.expand_path("~/dir", "/whatever") -> "/home/user/dir" anyway
        # File.expand_path("./dir", "/specific") -> "/specific/dir"
        # File.join('/specific', '/absolute') -> "/specific/absolute"
        r = File.join(__dir__, "local_files", File.expand_path(local_path, Remote.local_script_dir))
      ensure
        ENV["HOME"] = t_home
      end
      return r
    end
  end

  attr_accessor :block_contexts
  @block_contexts = []

  class TaskResult
    attr_reader :changed
    def initialize(changed)
      @changed = changed
      # propagating change to the block above
      Remote.block_contexts[-1] = Remote.block_contexts[-1] || changed unless Remote.block_contexts[-1].nil?
    end
    def afterwards(&block)
      if @changed
        yield
      end
    end
  end

  class ConfigBlockHandler
    attr_reader :changed
    def initialize(path, handler)
      @path = path
      @handler = handler
      @changed = false
    end

    def replace_or_add_line(a, b)
      task_result = Remote.task do
        b = b.strip
        content = File.read(@handler)
        case a # force to one line
        when String
          a_regexp = /^#{Regexp.quote(a)}$/
        when Regexp
          a_regexp = /^#{a}$/
        end
        if content.match /^#{Regexp.quote(b)}$/
          Remote.ok "#{@path} config includes #{b.inspect}"
        else
          a_match = content.match(a_regexp)
          if a_match
            Remote.destructive "replacing in config #{@path} line #{a_match[0].inspect} with #{b.inspect}" do
              @handler.truncate(0)
              @handler.write(content.gsub(a_regexp, b))
            end
          else # appending
            Remote.destructive "appending config #{@path} with #{b.inspect}" do
              @handler.seek(-1, IO::SEEK_END) if @handler.size > 0
              @handler.write("\n")
              @handler.write(b)
              @handler.write("\n")
            end
          end
        end
        @handler.seek(0, IO::SEEK_SET) # rewind handler back
      end
      @changed = @changed || task_result.changed # propagate to block
    end

    def add_line(line)
      task_result = Remote.task do
        line = line.strip
        content = File.read(@handler)
        if content.include? line
          Remote.ok "#{@path} config includes #{line}"
        else
            Remote.destructive "appending config #{@path} with #{b.inspect}" do
              @handler.seek(-1, IO::SEEK_END) if @handler.size > 0
              @handler.write("\n")
              @handler.write(b)
              @handler.write("\n")
            end
        end
        @handler.seek(0, IO::SEEK_SET) # rewind handler back
      end
      @changed = @changed || task_result.changed # propagate to block

    end

    def add_block(text)
      task_result = Remote.task do
        content = File.read(@handler)
        if content.include? text.strip
          Remote.ok "config #{@path} includes the block of text"
        else
          Remote.destructive "appending config #{@path} with the block of text" do
            @handler.seek(-1, IO::SEEK_END) if @handler.size > 0
            @handler.write("\n")
            @handler.write(text)
          end
        end
        @handler.seek(0, IO::SEEK_SET) # rewind handler back
      end
      @changed = @changed || task_result.changed # propagate to block
    end
  end

  def service_reload(name)
    destructive "reloading service #{name}" do
      cmd = ["systemctl", "reload", name]
      spawn(cmd, expect_status: 0)
    end
  end

  def service_restart(name)
    destructive "restarting service #{name}" do
      cmd = ["systemctl", "restart", name]
      spawn(cmd, expect_status: 0)
    end
  end

  require 'etc'
  def user_exists?(name)
    begin
      Etc.getpwnam(name)
      true
    rescue
      false
    end
  end

  def get_user_home_dir(name)
    Etc.getpwnam(name).dir
  end

  def get_uid_and_gid_of_user(name)
    r = Etc.getpwnam(name)
    [r.uid, r.gid]
  end

  def create_user(name, create_home, shell)
    if user_exists?(name)
      ok "#{name} user exists"
    else
      destructive "creating user #{name}" do
        cmd = ["useradd", name]
        cmd << "--create-home" if create_home
        cmd << "--shell" << shell if shell
        spawn cmd, expect_status: 0
      end
    end
  end

  require 'fileutils'
  def authorize_ssh_key(user, key)
    case key
    when LocalFile
      key_text = File.read(key.remote_path).strip
    when String
      key_text = key
    else
      raise "type #{key.class} is not supported for a SSH public key"
    end
    home_dir = get_user_home_dir(user)
    ssh_dir = File.join(home_dir, ".ssh")
    authorized_keys_path = File.join(ssh_dir, "authorized_keys")
    if File.exist? authorized_keys_path
      file_mode = @dry_run ? File::RDONLY : File::RDWR | File::APPEND
      File.open(authorized_keys_path, file_mode, 0600) do |f|
        f.flock(File::LOCK_EX)
        content = File.read(f)
        if content.include? key_text
          ok "#{authorized_keys_path} has the key"
        else
          destructive "appending key to #{authorized_keys_path}" do
            f.seek(-1, IO::SEEK_END) if f.size > 0
            f.write(key_text)
            f.write("\n")
          end
        end
      end
    else
      unless File.exist? ssh_dir
        destructive "creating #{ssh_dir}" do
          FileUtils.mkdir ssh_dir, mode: 0700
          File.chown(*(get_uid_and_gid_of_user(user) << ssh_dir))
        end
      end
      destructive "creating #{authorized_keys_path} with the key" do
        File.open(authorized_keys_path, File::CREAT | File::WRONLY, 0600) do |f|
          f.flock(File::LOCK_EX)
          f.write(key_text)
          f.write("\n")
        end
        File.chown(*(get_uid_and_gid_of_user(user) << authorized_keys_path))
      end
    end
  end

  attr_accessor :apt_updated
  def dpkg_installed?(names)
    #            | virtual | virtual | removed
    #            | package | package | but
    #            | present | absent  | dependency
    #     method |         |         | left
    # ----------------------------------------
    #    dpkg -s | exit 1  | exit 1  | exit 1
    # ----------------------------------------
    # dpkg-qeury | exit 0  | exit 1  | exit 0
    #         -W |         |         |
    case names
    when Array
      cmd = ["dpkg-query", "-W"] + names
    when String
      cmd = ["dpkg-query", "-W", names]
    end
    spawn(cmd, expect_status: [0,1]) == 0
  end

  def apt_update
    task do
      destructive "apt-get update" do
        spawn ["apt-get", "update", "-q"], expect_status: 0
      end
    end
  end

  def apt_install(names)
    names = names.to_s if names.is_a? Symbol
    names = names.split(/\s+/).map(&:strip).select{|x|not x.empty?} if names.is_a? String
    if dpkg_installed?(names)
      ok "installed: #{names.join(', ')}"
    else
      destructive "apt-get install #{names.join(' ')}" do
        unless apt_updated
          cmd = ["apt-get", "update", "-q"]
          spawn(cmd, expect_status: 0)
          apt_updated = true
        end

        cmd = ["apt-get", "install", "--no-install-recommends", "-y"]
        cmd += names
        spawn(cmd, expect_status: 0)
      end
    end
  end

  def apt_remove(names)
    names = names.to_s if names.is_a? Symbol
    names = names.split(/\s+/).map(&:strip).select{|x|not x.empty?} if names.is_a? String
    installed = names.each.select do |x|
      dpkg_installed? x
    end
    if installed.empty?
      ok "removed: #{names.join(", ")}"
    else
      installed.each do |name|
        destructive "apt-get remove #{name}" do
          cmd = ["apt-get", "remove", "-y"]
          cmd += names
          spawn cmd, expect_status: 0
        end
      end
      # We need to run autoremove because dpkg treat
      # removed packages with installed dependencies
      # as still installed. See the note in "dpkg_installed?"
      # method
      destructive "apt-get autoremove" do
        spawn ["apt-get", "autoremove", "-y"], expect_status: 0
      end
    end
  end

  def create_config(path, text)
    path = File.expand_path path
    unless File.exist?(path) && File.read(path).rstrip == text.rstrip
      destructive "writing config #{path}" do
        File.open(path, File::CREAT | File::TRUNC | File::WRONLY) do |f|
          f.flock(File::LOCK_EX)
          f.write(text)
          f.write("\n") unless text[-1] == "\n"
        end
      end
    else
      ok "#{path} already there"
    end
  end

  class RemoteFile
    attr_reader :path
    def initialize(path)
      @path = path
    end
    def read
      File.read(@path)
    end
  end

  def mkdir_p(x)
    x = File.expand_path x
    if File.directory? x
      ok "#{x} directory exists"
    else
      destructive "mkdir -p #{x}" do
        FileUtils.mkdir_p x
      end
    end
  end

  def rm(x)
    x = File.expand_path x
    if File.exists? x
      destructive "rm #{x}" do
        FileUtils.rm x
      end
    else
      ok "#{x} already removed"
    end
  end

  # TODO: the dst is a dir case
  def cp(src, dst, mode)
    src = src.remote_path if src.is_a? LocalFile
    dst = File.expand_path dst
    if (not File.exist?(dst)) || (not FileUtils.cmp(src, dst))
      destructive "copying to #{dst.inspect}" do
        FileUtils.cp src, dst
      end
    else
      ok "#{dst} already there"
    end
    if mode
      mode = mode.to_i(8) if mode.is_a? String
      if File.stat(dst).mode % 010000 == mode
        ok "#{dst} already in #{sprintf "%04o", mode}"
      else
        destructive "chmod #{sprintf "%04o", mode} #{dst}" do
          File.chmod(mode, dst)
        end
      end
    end
  end

  def chmod(mode, path)
    mode = mode.to_i(8) if mode.is_a? String
    path = File.expand_path path
    if File.stat(path).mode % 010000 == mode
      ok "#{path} already in #{sprintf "%04o", mode}"
    else
      destructive "chmod #{sprintf "%04o", mode} #{path}" do
        File.chmod(mode, path)
      end
    end
  end

  def ln_s(src, dst)
    src = File.expand_path src
    dst = File.expand_path dst
    if File.exist?(dst) &&File.lstat(dst).symlink? && File.readlink(dst) == src
      ok "#{dst} leads to #{src}"
    else
      destructive "ln -s #{src} #{dst}" do
        FileUtils.ln_s src, dst
      end
    end
  end

  #attr_accessor :impressionating_user

  def spawn(cmd, expect_status: nil)
    expect_status = [expect_status] unless expect_status.nil? || expect_status.respond_to?(:include?)
    stdout_r, stdout_w = IO.pipe
    debug "executing #{cmd.inspect}"
    pid, status = Process.wait2(Process.spawn(*cmd, in: File::NULL, out: stdout_w, err: stdout_w))
    if expect_status && (not expect_status.include?(status.exitstatus))
      stdout_w.close
      text = stdout_r.read
      raise CommandError.new("A process #{cmd.inspect} returned unexpected exit status #{status.exitstatus}", text)
    end
    stdout_w.close
    stdout_r.close
    return status.exitstatus
  end

  class CommandError < StandardError
    attr_reader :output
    def initialize(msg, output)
      @output = output
      super(msg)
    end
  end

  def ok(s)
    info "[ ] #{s}"
  end

  attr_reader :dry_run
  @dry_run = false
  def destructive(desc = nil)
    if desc
      if @dry_run
        info "[-] NOT #{desc} [dry run]"
      else
        info "[x] #{desc}"
      end
    end
    @task_changed_something = true
    yield unless @dry_run
  end

  attr_reader :ok_counter, :changed_counter
  @ok_counter = @changed_counter = 0
  def task
    @task_changed_something = false
    begin
      yield
    rescue => e
      handle_error e
    end
    if @task_changed_something
      @changed_counter += 1
    else
      @ok_counter += 1
    end
    TaskResult.new @task_changed_something
  end

  def handle_error(exc)
    $stderr.puts
    #exclude = [
    #  "hatecf.rb",
    #  "remote.rb",
    #]
    #line = caller.select do |line|
    #  not exclude.find{|x| line.include? x}
    #  #$stderr.puts line unless exclude.find{|x| line.include? x}
    #end.first

    exc.backtrace.each do |line|
      $stderr.puts line
    end
    $stderr.puts
    $stderr.puts exc.message
    $stderr.puts
    if exc.respond_to? :output
      $stderr.puts exc.output
      $stderr.puts
    end
    exit 1
  end

  def debug(s)
    info s if @verbose
  end

  def info(s)
    $stdout.puts s
    $stdout.flush
  end

  require 'json'
  def save_state
    JSON.dump({
      ok_counter: @ok_counter,
      changed_counter: @changed_counter,
    })
  end

  def load_state(json)
    h = JSON.parse(json, symbolize_names: true)
    @ok_counter      = h[:ok_counter]
    @changed_counter = h[:changed_counter]
  end

  require 'optparse'
  OptionParser.new do |opts|
    opts.on "--local-home HOME" do |x|
      @local_home = x
    end
    opts.on "--local-script-dir DIR" do |x|
      @local_script_dir = x
    end
    opts.on "--dry" do |x|
      @dry_run = true
    end
    opts.on "-v" do |x|
      @verbose = true
    end
  end.parse!
end
