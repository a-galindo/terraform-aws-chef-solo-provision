cookbook_file '/tmp/myApp.jar' do
  source 'myApp.jar'
  owner 'ec2-user'
  group 'ec2-user'
  mode '0755'
  action :create
end


##
#  Setting the right java for our app
##
package "java" do
  action :remove
end

package "java-1.8.0-openjdk-src.x86_64" do
  action :install
end

## Setting as a service, commented to avoid centOs service bug with chef
#service "myApp_service" do
#  supports :status => false, :restart => false
#  start_command "java -Dserver.port=8484 -jar /tmp/myApp.jar &"
#  action [ :enable, :start ]
#end

##
# as a work around we execute the app with a bash command
##
bash 'run_jar' do
     code <<-EOF
        java -Dserver.port=8484 -jar /tmp/myApp.jar &
     EOF
end
