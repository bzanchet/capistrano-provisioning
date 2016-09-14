require 'digest/md5'
require 'tempfile'

module Capistrano
  module Provisioning
    class DSL
      def initialize(context)
        @context = context
      end

      def chmod(mode, *files)
        execute("sudo chmod #{mode} #{files.join(" ")}")
      end

      def chown(owner, *files)
        execute("sudo chown #{owner} #{files.join(" ")}")
      end

      def command(command)
        execute(command)
      end

      # TODO: skip if md5sum matches
      # TODO: proper exception if local file not found
      def file(path, options = {})
        if !options[:remote_path]
          raise ArgumentError.new("Local path must be absolute when no remote path given: #{path}") unless path.start_with?("/")
          return file(File.join(Dir.pwd, "REMOTE", path), remote_path: path)
        end
        raise ArgumentError.new("Invalid file: #{path}") unless File.file?(path)
        raise ArgumentError.new("Remote path should be specified") unless remote_path = options[:remote_path]
        raise ArgumentError.new("Remote path must be absolute: #{remote_path}") unless remote_path.start_with?("/")
        owner = options[:owner] || "root"
        unless dir_exists?(dir = File.dirname(remote_path))
          cmd = "sudo -u #{owner} mkdir -p '#{dir}'"
          execute(cmd)
        end
        unless file_same?(path, remote_path)
          upload(path, remote_path)
        end
        if (owner = options[:owner]) && !owned_by?(owner, remote_path)
          chown(owner, remote_path)
        end
        if (mode = options[:mode]) && !file_permission?(mode, remote_path)
          chmod(mode, remote_path)
        end
      end

      def file_sync
        sync_directory("REMOTE")
      end

      def gem(gem)
        return if gem_installed?(gem)
        cmd = "sudo gem install #{gem} --no-document --quiet"
        execute(cmd)
      end

      def package(package, options = {})
        package_name = options[:name] || package
        return if package_installed?(package_name, options[:version])
        cmd = "sudo yum install --quiet -y #{package}"
        execute(cmd)
      end

      def package_group(*groups)
        groups.each do |group|
          next if group_installed?(group)
          cmd = "sudo yum groupinstall --quiet -y '#{group}'"
          execute(cmd)
        end
      end

      def service(service, options = {})
        if options[:enable]
          execute("sudo systemctl enable #{service}")
        end
        if options[:restart]
          execute("sudo systemctl restart #{service}")
        end
      end

      def sync_directory(path, options = {})
        local_path = File.join(Dir.pwd, path)
        Dir.glob("#{local_path}/**/*") do |file|
          if FileTest.file?(file)
            file(file.gsub(local_path, ""))
          end
        end
      end

      # TODO: add timestamp to file and run only once each 24h
      # TODO: ^^ plus add 'force' option
      def update
        execute("yum clean all")
        execute("sudo yum --quiet -y update")
      end

      # TODO: authorized_keys should append to the file if not there
      # TODO: add sudo option
      def user(username, options = {})
        if !user_exists?(username)
          cmd = "sudo adduser #{username}"
          cmd << " --password '#{options[:password]}'" if options[:password]
          cmd << " --home-dir '#{options[:home]}'" if options[:home]
          execute(cmd)
        end
        if options[:authorized_keys]
          raise ArgumentError.new(":authorized_keys must be an array") unless options[:authorized_keys].is_a?(Array)
          home_dir = options[:home] || "/home/#{username}"
          options[:authorized_keys].each do |key_file|
            file(key_file, remote_path: "#{home_dir}/.ssh/authorized_keys", owner: username, mode: 400)
          end
        end
      end

      private

      def dir_exists?(dir)
        test("sudo test -d '#{dir}'")
      end

      def capture(cmd)
        @context.capture(cmd)
      end

      def execute(cmd)
        @context.execute(cmd)
      end

      def file_exists?(file)
        test("sudo test -f '#{file}'")
      end

      def file_permission?(permission, file)
        stat = capture("sudo stat #{file}")
        stat.scan(/Access: \(\d(\d{3})/).flatten.first == permission.to_s
      end

      def file_same?(local_path, remote_path)
        return false unless file_exists?(remote_path)
        local_digest = Digest::MD5.file(local_path).to_s
        remote_digest = capture("sudo md5sum '#{remote_path}'").split(" ").first
        local_digest == remote_digest
      end

      def gem_installed?(gem)
        test("gem query -i #{gem} > /dev/null")
      end

      def group_installed?(group)
        test("yum groups list installed | grep -i '#{group}' > /dev/null")
      end

      def owned_by?(user, file)
        test("sudo -u #{user} test -O #{file}")
      end

      def package_installed?(package, version = nil)
        return unless test("rpm -qi --quiet #{package}")
        if version
          installed_version = @context.capture("rpm -qa #{package} --queryformat '%{version}'")
          version == installed_version
        else
          # no version given
          true
        end
      end

      def test(cmd)
        @context.test(cmd)
      end

      def upload(local_path, remote_path)
        raise ArgumentError.new("Invalid file: #{local_path}") unless File.file?(local_path)
        tempfile = Tempfile.new("mytempfile", "/tmp")
        @context.upload!(local_path, tempfile.path)
        cmd = "sudo cp #{tempfile.path} #{remote_path}"
        execute(cmd)
        tempfile.close
      end

      def user_exists?(username)
        test("getent passwd #{username} > /dev/null")
      end
    end
  end
end
