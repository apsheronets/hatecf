require './remote.rb'

def target(*args)
  # skip on remote
end

def local_file(path)
  Remote::LocalFile.new(path)
end

def edit_config(path)
  path = File.expand_path path
  File.open(path, File::RDWR) do |f|
    f.flock(File::LOCK_EX)
    h = Remote::ConfigBlockHandler.new(path, f)
    yield h
    return Remote::TaskResult.new(h.changed)
  end
end

def service_reload(name)
  Remote.task do
    Remote.service_reload(name)
  end
end

def service_restart(name)
  Remote.task do
    Remote.service_restart(name)
  end
end

def create_user(name, create_home: false, shell: nil)
  Remote.task do
    Remote.create_user(name, create_home, shell)
  end
end

def authorize_ssh_key(user:, key:)
  Remote.task do
    Remote.authorize_ssh_key(user, key)
  end
end

def apt_update
  Remote.apt_update
end

def apt_install(names)
  Remote.task do
    Remote.apt_install names
  end
end

def apt_remove(names)
  Remote.task do
    Remote.apt_remove(names)
  end
end

def command(cmd, expect_status: 0)
  Remote.task do
    Remote.destructive "executing #{cmd.inspect}" do
      Remote.spawn(cmd, expect_status: expect_status)
    end
  end
end

def create_config(path, text)
  Remote.task do
    Remote.create_config(path, text)
  end
end

def mkdir_p(x)
  Remote.task do
    Remote.mkdir_p(x)
  end
end

def rm(x)
  Remote.task do
    Remote.rm(x)
  end
end

def cp(src, dst, mode: nil)
  Remote.task do
    Remote.cp(src, dst, mode)
  end
end

def chmod(mode, path)
  Remote.task do
    Remote.chmod(mode, path)
  end
end

def ln_s(src, dst)
  Remote.task do
    Remote.ln_s(src, dst)
  end
end

class CheckResult
  def initialize(result)
    @result = result
  end
  def fix
    yield unless @result
  end
  def check(message = nil)
    if @result
      # skip
      CheckResult.new @result
    else
      result = yield
      Remote.ok message if result && message
      CheckResult.new result
    end
  end
end

def check(message = nil)
  result = yield
  Remote.ok message if result && message
  CheckResult.new result
end

def block
  Remote.block_contexts << false
  begin
    yield
  ensure
    changed = Remote.block_contexts.pop
  end
  Remote::TaskResult.new(changed)
end

def as(user, group: nil)
  require 'etc'
  u = Etc.getpwnam(user)
  if group
    g = Etc.getgrnam(group)
  else
    begin
      g = Etc.getgrnam(user)
    rescue
    end
  end
  rd, wr = IO.pipe # for state
  child_pid = fork
  if child_pid # parent
    wr.close
    pid, status = Process.wait2(child_pid)
    if status.exitstatus > 0
      exit status.exitstatus
    else
      Remote.load_state(rd.read)
      rd.close
    end
  else # child
    rd.close
    wr.close_on_exec = true
    #ENV["USER"] = user
    #ENV["LOGNAME"] = user
    ENV["HOME"] = u.dir # required at least for File.expand_path
    Process.gid = Process.egid = g.gid if g
    Process.uid = Process.euid = u.uid
    yield
    wr.write(Remote.save_state)
    wr.flush
    wr.close
    $stdout.flush
    $stderr.flush
    exit 0
  end
end

def remote_file(path)
  Remote::RemoteFile.new(path)
end

def perform! # legacy, not needed since 0.2
  Remote.perform!
end

Kernel.at_exit do
  Remote.perform!
end

# Monkey-patching

module ArrayExtension
  @task_result = nil
  def afterwards(&block)
    @task_result.afterwards(&block)
  end
  def each
    Remote.block_contexts << false
    begin
      r = super
    ensure
      changed = Remote.block_contexts.pop
    end
    @task_result = Remote::TaskResult.new(changed)
    return r
  end
end

class Array
  prepend ArrayExtension
end
