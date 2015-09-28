#
# The NXAPI provider for cisco_ospf_vrf.
#
# May, 2015
#
# Copyright (c) 2015 Cisco and/or its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'cisco_node_utils' if Puppet.features.cisco_node_utils?
begin
  require 'puppet_x/cisco/autogen'
rescue LoadError # seen on master, not on agent
  # See longstanding Puppet issues #4248, #7316, #14073, #14149, etc. Ugh.
  require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..',
                                     'puppet_x', 'cisco', 'autogen.rb'))
end

Puppet::Type.type(:cisco_ospf_vrf).provide(:nxapi) do
  desc 'The NXAPI provider.'

  confine feature: :cisco_node_utils
  defaultfor operatingsystem: :nexus

  mk_resource_methods

  # Property symbol array for method auto-generation.
  OSPF_VRF_PROPS = [
    :default_metric, :log_adjacency, :router_id,
    :timer_throttle_lsa_start, :timer_throttle_lsa_hold,
    :timer_throttle_lsa_max, :timer_throttle_spf_start,
    :timer_throttle_spf_hold, :timer_throttle_spf_max
  ]

  PuppetX::Cisco::AutoGen.mk_puppet_methods(:non_bool, self, '@vrf',
                                            OSPF_VRF_PROPS)

  def initialize(value={})
    super(value)
    ospf = @property_hash[:ospf]
    vrf = @property_hash[:vrf]
    @vrf = Cisco::RouterOspfVrf.vrfs[ospf][vrf] unless ospf.nil?
    @property_flush = {}
  end

  def self.get_properties(ospf, name, vrf)
    debug "Checking ospf instance, #{ospf} #{name}"
    current_state = {
      name:   "#{ospf} #{name}",
      ospf:   ospf,
      vrf:    name,
      ensure: :present,
    }
    # Call node_utils getter for each property
    OSPF_VRF_PROPS.each do |prop|
      current_state[prop] = vrf.send(prop)
    end
    # Special Cases
    # Display cost_value in MBPS
    cost_value, cost_type = vrf.auto_cost
    cost_value *= 1000 if
      cost_type == Cisco::RouterOspfVrf::OSPF_AUTO_COST[:gbps]
    current_state[:auto_cost] = cost_value
    debug current_state
    new(current_state)
  end # self.get_properties

  def self.instances
    vrf_instances = []
    Cisco::RouterOspfVrf.vrfs.each do |ospf, vrfs|
      vrfs.each do |name, vrf|
        begin
          vrf_instances << get_properties(ospf, name, vrf)
        end
      end
    end
    vrf_instances
  end # self.instances

  def self.prefetch(resources)
    vrf_instances = instances
    resources.keys.each do |name|
      provider = vrf_instances.find { |vrf| vrf.name == name }
      resources[name].provider = provider unless provider.nil?
    end
  end # self.prefetch

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_flush[:ensure] = :present
  end

  def destroy
    fail 'VRF default cannot be removed by cisco_ospf_vrf. Use cisco_ospf to remove the entire OSPF process including the default VRF.' if @resource[:vrf] == 'default'
    @property_flush[:ensure] = :absent
  end

  def property_set(new_vrf=false)
    OSPF_VRF_PROPS.each do |prop|
      if @resource[prop]
        send("#{prop}=", @resource[prop]) if new_vrf
        unless @property_flush[prop].nil?
          @vrf.send("#{prop}=", @property_flush[prop]) if
            @vrf.respond_to?("#{prop}=")
        end
      end
    end
    # Set methods that are not autogenerated follow.
    auto_cost_set unless @resource[:auto_cost].nil?
    timer_throttle_lsa_set
    timer_throttle_spf_set
  end

  # convert auto_cost to Mbps to match manifest.
  def convert_cost_type(value, type)
    value *= 1000 if type == Cisco::RouterOspfVrf::OSPF_AUTO_COST[:gbps]
    value
  end

  def default_auto_cost_mbps
    default_value, default_type = @vrf.default_auto_cost
    convert_cost_type(default_value, default_type)
  end

  def auto_cost
    return :default if
      @resource[:auto_cost] == :default &&
      @property_hash[:auto_cost] == default_auto_cost_mbps
    @property_hash[:auto_cost]
  end

  def auto_cost_set
    if @resource[:auto_cost] == :default
      value = default_auto_cost_mbps
    else
      value = @resource[:auto_cost]
    end
    @vrf.auto_cost_set(value, Cisco::RouterOspfVrf::OSPF_AUTO_COST[:mbps])
  end

  def timer_throttle_lsa_set
    return unless @property_flush[:timer_throttle_lsa_start] ||
                  @property_flush[:timer_throttle_lsa_hold] ||
                  @property_flush[:timer_throttle_lsa_max]

    if @property_flush[:timer_throttle_lsa_start]
      start = @property_flush[:timer_throttle_lsa_start]
    else
      start = @vrf.timer_throttle_lsa_start
    end

    if @property_flush[:timer_throttle_lsa_hold]
      hold = @property_flush[:timer_throttle_lsa_hold]
    else
      hold = @vrf.timer_throttle_lsa_hold
    end

    if @property_flush[:timer_throttle_lsa_max]
      max = @property_flush[:timer_throttle_lsa_max]
    else
      max = @vrf.timer_throttle_lsa_max
    end
    @vrf.timer_throttle_lsa_set(start, hold, max)
  end

  def timer_throttle_spf_set
    return unless @property_flush[:timer_throttle_spf_start] ||
                  @property_flush[:timer_throttle_spf_hold] ||
                  @property_flush[:timer_throttle_spf_max]

    if @property_flush[:timer_throttle_spf_start]
      start = @property_flush[:timer_throttle_spf_start]
    else
      start = @vrf.timer_throttle_spf_start
    end

    if @property_flush[:timer_throttle_spf_hold]
      hold = @property_flush[:timer_throttle_spf_hold]
    else
      hold = @vrf.timer_throttle_spf_hold
    end

    if @property_flush[:timer_throttle_spf_max]
      max = @property_flush[:timer_throttle_spf_max]
    else
      max = @vrf.timer_throttle_spf_max
    end
    @vrf.timer_throttle_spf_set(start, hold, max)
  end

  def flush
    if @property_flush[:ensure] == :absent
      @vrf.destroy
      @vrf = nil
    else
      if @vrf.nil?
        new_vrf = true
        @vrf = Cisco::RouterOspfVrf.new(@resource[:ospf], @resource[:vrf])
      end
      property_set(new_vrf)
    end
    puts_config
  end

  def puts_config
    if @vrf.nil?
      info "Vrf=#{@resource[:name]} is absent."
      return
    end

    # Dump all current properties for this interface
    current = sprintf("\n%30s: %s", 'vrf', @vrf.name)
    OSPF_VRF_PROPS.each do |prop|
      current.concat(sprintf("\n%30s: %s", prop, @vrf.send(prop)))
    end
    debug current
  end # puts_config
end
