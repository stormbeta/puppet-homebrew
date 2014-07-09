require 'puppet/provider/package/homebrew'

Puppet::Type.type(:package).provide(
    :cask, :parent => Puppet::Type.type(:package).provider(:brew)
) do
  desc "Homebrew-cask repository management on OS X"

  has_feature :installable, :install_options
  has_feature :versionable
  has_feature :upgradeable
  has_feature :uninstallable

  commands :id   => "/usr/bin/id"
  commands :stat => "/usr/bin/stat"
  commands :sudo => "/usr/bin/sudo"
  commands :brew => "/usr/local/bin/brew"

  # Install packages, known as formulas, using brew.
  def install
    Puppet.notice "Installing #{@resource[:name]}"
    should = @resource[:ensure]
    package_name = @resource[:name]
    case should
    when true, false, Symbol
      # pass
    else
      package_name += "-#{should}"
    end
    Puppet.debug "  Package: #{package_name}"

    args = [command(:brew), :cask, :install, package_name ]
    if install_options.any?
      args.push(*install_options)
    end
    output = execute(*args)

    # Fail hard if there is no formula available.
    if output =~ /Error: No available cask/
      raise Puppet::ExecutionFailure,
          "Could not find casl package #{@resource[:name]}"
    end

  end

  def uninstall
    Puppet.notice "Uninstalling #{@resource[:name]}"
    begin
      execute([command(:brew), :cask, :uninstall, @resource[:name]])
    rescue Puppet::ExecutionFailure
      Puppet.err "Package #{@resource[:name]} Uninstall failed: #{$!}"
      nil
    end
  end
  # Install packages, known as formulas, using brew.
  def install
    Puppet.notice "Casking package #{@resource[:name]}"
    output = execute(
        [
            "sudo", "-E", "-u", "vagrant", command(:brew), :cask, :install,
            @resource[:name]
        ],
        :custom_environment => {'HOME' => '/Users/vagrant'}
    )

    # Fail hard if there is no tap available.
    if output =~ /Error: No available cask/
      raise Puppet::ExecutionFailure, "Could not find package #{@resource[:name]}"
    end
  end

  def installed?
    is_not_installed = execute([
        command(:brew), :info, :cask, @resource[:name]
    ]).split("\n").grep(/^Not installed$/).first
    is_not_installed.nil?
  end

  def query
    Puppet.debug "Querying #{@resource[:name]}"
    begin
      cellar_path = execute([command(:brew), :cask]).chomp
      Puppet.debug "Cellars path: #{cellar_path}"
      info = execute([
          command(:brew), :cask, :info, @resource[:name]
      ]).split("\n").grep(/^#{cellar_path}/).first
      return nil if info.nil?
      version = info[%r{^#{cellar_path}/[^/]+/(\S+)}, 1]
      Puppet.debug "  Package #{@resource[:name]} is at version: #{version}.\n  info: #{info}"
      {
        :name     => @resource[:name],
        :ensure   => version,
        :provider => :brew
      }
    rescue Puppet::ExecutionFailure
      Puppet.err "Package #{@resource[:name]} Query failed: #{$!}"
      raise Puppet::Error, "Brew error: #{$!}"
    end
  end

  def latest
    Puppet.debug "Querying latest for #{@resource[:name]}"
    begin
      execpipe([command(:brew), :cask, :info, @resource[:name]]) do |process|
        process.each_line do |line|
          line.chomp!
          next if line.empty?
          next if line !~ /^#{@resource[:name]}:\s(.*)/i
          Puppet.debug "  Latest versions for #{@resource[:name]}: #{$1}"
          versions = $1
          #return 'HEAD' if versions =~ /\bHEAD\b/
          return $1 if versions =~ /stable (\d+[^\s]*)\s+\(bottled\)/
          return $1 if versions =~ /stable (\d+.*), HEAD/
          return $1 if versions =~ /stable (\d+.*)/
          return $1 if versions =~ /(\d+.*)/
        end
      end
      nil
    rescue Puppet::ExecutionFailure
      Puppet.err "Package #{@resource[:name]} Query Latest failed: #{$!}"
      nil
    end
  end

  def self.package_list(options={})
    Puppet.debug "Listing currently installed brews"
    brew_list_command = [command(:brew), :cask, :list]

    if name = options[:justme]
      brew_list_command << name
    end

    begin
      list = execute(brew_list_command).
        lines.
        map {|line| name_version_split(line) }
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not list packages: #{detail}"
    end

    if options[:justme]
      return list.shift
    else
      return list
    end
  end

end
