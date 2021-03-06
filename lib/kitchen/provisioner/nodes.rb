# -*- encoding: utf-8 -*-
#
# Author:: Matt Wrock (<matt@mattwrock.com>)
#
# Copyright (C) 2015, Matt Wrock
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen'
require 'kitchen/provisioner/chef_zero'
require 'kitchen/provisioner/finder'
require 'net/ping'

module Kitchen
  module Provisioner
    # Nodes provisioner for Kitchen.
    #
    # @author Matt Wrock <matt@mattwrock.com>
    class Nodes < ChefZero
      def create_sandbox
        FileUtils.rm(node_file) if File.exist?(node_file)
        create_node
        super
      end

      def create_node
        FileUtils.mkdir_p(node_dir) unless Dir.exist?(node_dir)
        template_to_write = node_template
        File.open(node_file, 'w') do |out|
          out << JSON.pretty_generate(template_to_write)
        end
      end

      def state_file
        @state_file ||= Kitchen::StateFile.new(
          config[:kitchen_root],
          instance.name
        ).read
      end

      def ipaddress
        state = state_file

        if %w(127.0.0.1 localhost).include?(state[:hostname])
          return get_reachable_guest_address(state)
        end
        state[:hostname]
      end

      def fqdn
        state = state_file
        begin
          [:username, :password].each do |prop|
            state[prop] = instance.driver[prop] if instance.driver[prop]
          end
          Finder.for_transport(instance.transport, state).find_fqdn
        rescue
          nil
        end
      end

      def chef_environment
        env = '_default'
        if config[:client_rb] && config[:client_rb][:environment]
          env = config[:client_rb][:environment]
        end
        env
      end

      def node_template
        {
          id: instance.name,
          chef_environment: chef_environment,
          automatic: {
            ipaddress: ipaddress,
            platform: instance.platform.name.split('-')[0].downcase,
            fqdn: fqdn
          },
          normal: config[:attributes],
          run_list: config[:run_list]
        }
      end

      def node_dir
        File.join(config[:test_base_path], 'nodes')
      end

      def node_file
        File.join(node_dir, "#{instance.name}.json")
      end

      def get_reachable_guest_address(state)
        active_ips(instance.transport, state).each do |address|
          next if address == '127.0.0.1'
          return address if Net::Ping::External.new.ping(address)
        end
      end

      def active_ips(transport, state)
        # inject creds into state for legacy drivers
        [:username, :password].each do |prop|
          state[prop] = instance.driver[prop] if instance.driver[prop]
        end
        ips = Finder.for_transport(transport, state).find_ips
        fail 'Unable to retrieve IPs' if ips.empty?
        ips
      end
    end
  end
end
