require "ibm_power_hmc"

describe IbmPowerHmc::PartitionTemplate do
  def build_template(with_adapters: false)
    adapters = with_adapters ? '<virtualFibreChannelClientAdapters schemaVersion="V1_0"><Metadata><Atom/></Metadata></virtualFibreChannelClientAdapters>' : ''
    xml = <<~XML
      <entry xmlns="http://www.w3.org/2005/Atom" xmlns:etag="http://a9.com/-/spec/opensearch/1.1/">
        <id>uuid</id><published>2024-01-01T00:00:00.000Z</published>
        <content type="application/vnd.ibm.powervm.templates+xml;type=PartitionTemplate">
          <PartitionTemplate schemaVersion="V1_0">
            <partitionTemplateName>t</partitionTemplateName>
            <logicalPartitionConfig schemaVersion="V1_0">
              <partitionName>p</partitionName>
              <clientNetworkAdapters schemaVersion="V1_0"/>
              #{adapters}
              <suspendEnable>false</suspendEnable>
              <kvmCapable>false</kvmCapable>
            </logicalPartitionConfig>
          </PartitionTemplate>
        </content>
      </entry>
    XML
    described_class.new(REXML::Document.new(xml).root)
  end

  def lpar_children(tmpl)
    tmpl.xml.elements['logicalPartitionConfig'].elements.map(&:name)
  end

  it "emits vFC deploy form with locationCode, in schema order, with the template's schemaVersion" do
    tmpl = build_template
    tmpl.vfc = [{:vios => "vios2", :port => "fcs0", :location => "U78DA.ND0.WZS03EJ-P0-C1-T0"}]

    expect(lpar_children(tmpl)).to eq(%w[partitionName clientNetworkAdapters virtualFibreChannelClientAdapters suspendEnable kvmCapable])
    adaps = tmpl.xml.elements['logicalPartitionConfig/virtualFibreChannelClientAdapters']
    expect(adaps.attributes['schemaVersion']).to eq("V1_0")
    adapter = adaps.elements['VirtualFibreChannelClientAdapter']
    expect(adapter.elements.map(&:name)).to eq(%w[Metadata locationCode connectingPartitionName portName])
    expect(adapter.elements['locationCode'].text).to eq("U78DA.ND0.WZS03EJ-P0-C1-T0")
    expect(adapter.elements['portName'].text).to eq("fcs0")
  end

  it "replaces an existing vFC element in place" do
    tmpl = build_template(:with_adapters => true)
    tmpl.vfc = [{:vios => "vios2", :port => "fcs0", :location => "L"}]

    expect(lpar_children(tmpl).count("virtualFibreChannelClientAdapters")).to eq(1)
    expect(lpar_children(tmpl)).to eq(%w[partitionName clientNetworkAdapters virtualFibreChannelClientAdapters suspendEnable kvmCapable])
  end

  it "emits vSCSI with the HMC element set and IBM's PhyscalVolumeVTDName spelling" do
    tmpl = build_template
    tmpl.vscsi = [{:vios => "vios1", :physvol => "hdisk4", :vtd_name => "aa"}]

    adapter = tmpl.xml.elements['logicalPartitionConfig/virtualSCSIClientAdapters/VirtualSCSIClientAdapter']
    expect(adapter.elements.map(&:name)).to eq(%w[Metadata name PhyscalVolumeVTDName associatedLogicalUnits associatedPhysicalVolume connectingPartitionName AssociatedTargetDevices associatedVirtualOpticalMedia])
    expect(adapter.elements['PhyscalVolumeVTDName'].text).to eq("aa")
    expect(adapter.elements['associatedPhysicalVolume/PhysicalVolume/name'].text).to eq("hdisk4")
    expect(adapter.elements['connectingPartitionName'].text).to eq("vios1")
    expect(lpar_children(tmpl)).to eq(%w[partitionName clientNetworkAdapters virtualSCSIClientAdapters suspendEnable kvmCapable])
  end

  it "omits PhyscalVolumeVTDName when no vtd_name is given" do
    tmpl = build_template
    tmpl.vscsi = [{:vios => "vios1", :physvol => "hdisk4"}]

    adapter = tmpl.xml.elements['logicalPartitionConfig/virtualSCSIClientAdapters/VirtualSCSIClientAdapter']
    expect(adapter.elements['PhyscalVolumeVTDName']).to be_nil
  end

  it "adds Metadata/Atom to VLAN adapters and keeps their position" do
    tmpl = build_template
    tmpl.vlans = [{:name => "vlan10", :vlan_id => "10", :switch => "ETHERNET0"}]

    expect(lpar_children(tmpl)).to eq(%w[partitionName clientNetworkAdapters suspendEnable kvmCapable])
    expect(tmpl.xml.elements['logicalPartitionConfig/clientNetworkAdapters/ClientNetworkAdapter/Metadata/Atom']).not_to be_nil
  end
end
