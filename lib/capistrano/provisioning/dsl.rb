require 'tempfile'

module Capistrano
  module Provisioning
    class DSL
      def initialize(context)
        @context = context
      end

      def file(path, options = {})
        owner = options[:owner] || "root"
        cmd = "sudo -u #{owner} mkdir -p #{File.dirname(path)}"
        execute(cmd)
        upload(path)
        if owner
          cmd = "sudo chown #{owner} #{path}"
          execute(cmd)
        end
        if mode = options[:mode]
          cmd = "sudo chmod #{mode} #{path}"
          execute(cmd)
        end
      end

      def package(package, options = {})
        package_name = options[:name] || package
        return if package_installed?(package_name, options[:version])
        cmd = "sudo yum upgrade --quiet -y #{package}"
        execute(cmd)
      end

      def package_group(*groups)
        groups.each do |group|
          next if group_installed?(group)
          cmd = "sudo yum groupinstall --quiet -y '#{group}'"
          execute(cmd)
        end
      end

      def update
        execute("yum clean all")
        execute("sudo yum --quiet -y update")
      end

      def user(username, options = {})
        return if user_exists?(username)
        cmd = "sudo adduser #{username}"
        cmd << " --password '#{options[:password]}'" if options[:password]
        execute(cmd)
      end

      private

      def execute(cmd)
        @context.execute(cmd)
      end

      def group_installed?(group)
        test("yum groups list installed | grep -i '#{group}' > /dev/null")
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

      def upload(path)
        tempfile = Tempfile.new("mytempfile", "/tmp")
        @context.upload!("#{Dir.pwd}/files#{path}", tempfile.path)
        cmd = "sudo mv #{tempfile.path} #{path}"
        execute(cmd)
        tempfile.close
      end

      def user_exists?(username)
        test("getent passwd #{username} > /dev/null")
      end
    end
  end
end
