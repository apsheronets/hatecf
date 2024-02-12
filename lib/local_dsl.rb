require File.join(__dir__, "./local.rb")

def target(host:, user: nil, port: nil)
  Local.type_check(:host, host, String)
  Local.type_check(:user, user, String) if user
  Local.type_check(:port, port, Integer) if port
  #Local.target = Local::DEFAULT_TARGET.dup
  Local.target[:host] = host
  Local.target[:user] = user if user
  Local.target[:port] = port if port
end

class LocalFile
  def initialize(path)
  end
end

def local_file(path)
  # File.expand_path("~/dir") -> "/home/user/dir"
  # File.expand_path("~/dir", "/whatever") -> "/home/user/dir" anyway
  # File.expand_path("./dir", "/specific") -> "/specific/dir"
  # File.join('/specific', '/absolute') -> "/specific/absolute"
  path = File.expand_path(path, File.dirname(ENV["_"]))
  Local.die "#{path} doesn't exists" unless File.exist? path
  Local.local_files = Local.local_files | [path]
  return LocalFile.new(path)
end

class LocalEntity
  def initialize(payload)
    @payload = payload
  end
end

def local(x)
  LocalEntity.new(x)
end

class TaskResult
  def afterwards
    yield
  end
end

class ConfigBlockHandler
  attr_accessor :path

  def replace_or_add_line(a, b)
    Local.type_check(1, a, String, Regexp)
    Local.type_check(2, b, String)
    TaskResult.new
  end

  def add_line(s)
    Local.type_check(nil, s, String)
    TaskResult.new
  end

  def add_block(text)
    Local.type_check(nil, text, String)
    TaskResult.new
  end
end

def edit_config(path)
  Local.type_check(nil, path, String)
  h = ConfigBlockHandler.new
  h.path = path
  yield h
  TaskResult.new
end

def service_reload(name)
  Local.type_check(nil, name, String, Symbol)
end

def service_restart(name)
  Local.type_check(nil, name, String, Symbol)
end

def create_user(name, create_home:, shell:)
  Local.type_check(nil, name, String, Symbol)
  Local.type_check(:create_home, create_home, TrueClass, FalseClass)
  Local.type_check(:shell, shell, String)
  TaskResult.new
end

def authorize_ssh_key(user:, key:)
  Local.type_check(:user, user, String, Symbol)
  Local.type_check(:key, key, String, LocalFile)
  TaskResult.new
end

def apt_update
end

def apt_install(names)
  Local.type_check(nil, names, String, Symbol, Array)
  TaskResult.new
end

def apt_remove(names)
  Local.type_check(nil, names, String, Symbol, Array)
  TaskResult.new
end

def command(cmd, expect_status: 0)
  Local.type_check(nil, cmd, String, Symbol, Array)
  Local.type_check(:expect_status, expect_status, Integer, Array, Range)
  TaskResult.new
end

def create_config(path, text)
  Local.type_check(1, path, String)
  Local.type_check(2, text, String)
  TaskResult.new
end

def mkdir_p(x)
  Local.type_check(nil, x, String, Symbol, Array)
  TaskResult.new
end

def cp(src, dst, mode: nil)
  Local.type_check(1, src, String, LocalFile)
  Local.type_check(1, dst, String)
  if mode
    Local.type_check(:mode, mode, String, Integer)
    Local.check_mode mode
  end
  TaskResult.new
end

def chmod(mode, path)
  Local.type_check(2, path, String)
  if mode
    Local.type_check(:mode, mode, String, Integer)
    Local.check_mode mode
  end
  TaskResult.new
end

def ln_s(src, dst)
  Local.type_check(1, src, String)
  Local.type_check(2, dst, String)
  TaskResult.new
end

def block
  yield
end

def as(user, group: nil)
  Local.die 'nested "as" blocks are not supported' if Local.as_user_block
  Local.type_check(nil, user, String, Symbol)
  Local.type_check(nil, group, String, Symbol) if group
  Local.as_user_block = true
  begin
    yield
  ensure
    Local.as_user_block = false
  end
end

def remote_file(path)
  Local.type_check(nil, path, String)
  UndefinedOnLocal.new
end

class UndefinedOnLocal
  def to_s
    "[undefined on local]"
  end
  def method_missing(*args)
    self
  end
end

class RemoteFile
  attr_reader :path
  def initialize(path)
    @path = path
  end
  def read
    UndefinedOnLocal.new
  end
end

def perform!
  Local.perform!
end

# Monkey-patching

class Array
  def afterwards
    yield
  end
end
