desc "Provisions the server"
task :provision do
  on release_roles :all do |host|
    interpreter = Capistrano::Provisioning::DSL.new(self)
    interpreter.instance_eval do
      #FIXME: can do better than Dir.pwd
      eval File.read("#{Dir.pwd}/recipe.rb")
    end
  end
end
