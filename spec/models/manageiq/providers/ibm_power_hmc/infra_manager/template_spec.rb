describe ManageIQ::Providers::IbmPowerHmc::InfraManager::Template do
  let(:ems)               { FactoryBot.create(:ems_ibm_power_hmc_infra_with_authentication) }
  let(:template)          { FactoryBot.create(:ibm_power_hmc_template, :ext_management_system => ems, :ems_ref => "template1_uuid", :name => "template1") }
  let(:archived_template) { FactoryBot.create(:ibm_power_hmc_template, :ext_management_system => nil, :ems_ref => "template2_uuid", :name => "template2") }

  context "template" do
    it "supports clone" do
      expect(template.supports?(:clone)).to (be true), "unsupported reason: #{described_class.unsupported_reason(:clone)}"
      expect(archived_template.supports?(:clone)).to be false
    end
    it "supports provisioning" do
      expect(template.supports?(:provisioning)).to (be true), "unsupported reason: #{described_class.unsupported_reason(:provisioning)}"
      expect(archived_template.supports?(:provisioning)).to be false
    end
  end

  describe "#provision_lpar" do
    let(:switch) { FactoryBot.create(:switch, :name => "ETHERNET0") }
    let(:host)   { FactoryBot.create(:ibm_power_hmc_host, :ext_management_system => ems, :ems_ref => "sys1_uuid", :switches => [switch]) }
    let!(:lan)   { FactoryBot.create(:lan, :name => "vlan10", :tag => "10", :switch => switch) }
    let!(:vios)  { FactoryBot.create(:ibm_power_hmc_vios, :ext_management_system => ems, :host => host, :name => "vios1", :ems_ref => "vios1_uuid") }
    let!(:fcs)   do
      hw = FactoryBot.create(:hardware, :vm_or_template => vios)
      FactoryBot.create(:guest_device, :hardware => hw, :controller_type => "Fibre channel port", :device_name => "fcs0", :location => "U78DA.ND0.WZS03EJ-P0-C1-T0")
    end

    let(:base_options) do
      {:name => "new-lpar", :host_id => host.id, :vlan => "vlan10"}
    end

    def stub_provision(options, &blk)
      allow(ems).to receive(:with_provider_connection).and_yield(double("connection", :template_provision => "new-lpar-uuid"))
      template.provision_lpar(options)
    end

    it "calls template_provision without storage changes when no overrides given" do
      conn = double("connection")
      expect(conn).to receive(:template_provision) do |_tmpl, _host, changes|
        expect(changes).not_to have_key(:vscsi)
        expect(changes).not_to have_key(:vfc)
        expect(changes).not_to have_key(:vopt)
        "new-lpar-uuid"
      end
      allow(ems).to receive(:with_provider_connection).and_yield(conn)
      template.provision_lpar(base_options)
    end

    it "passes vscsi changes when vscsi_storage is provided" do
      conn = double("connection")
      expect(conn).to receive(:template_provision) do |_tmpl, _host, changes|
        expect(changes[:vscsi]).to eq([{:vios => "vios1", :physvol => "hdisk10"}])
        "new-lpar-uuid"
      end
      allow(ems).to receive(:with_provider_connection).and_yield(conn)
      template.provision_lpar(base_options.merge(:vscsi_storage => "vios1:hdisk10"))
    end

    it "passes vfc changes when vfc_storage is provided" do
      conn = double("connection")
      expect(conn).to receive(:template_provision) do |_tmpl, _host, changes|
        expect(changes[:vfc]).to eq([{:vios => "vios1", :port => "fcs0", :location => "U78DA.ND0.WZS03EJ-P0-C1-T0"}])
        "new-lpar-uuid"
      end
      allow(ems).to receive(:with_provider_connection).and_yield(conn)
      template.provision_lpar(base_options.merge(:vfc_storage => "vios1:fcs0"))
    end

    it "passes both vscsi and vfc changes when both overrides are provided" do
      conn = double("connection")
      expect(conn).to receive(:template_provision) do |_tmpl, _host, changes|
        expect(changes[:vscsi]).to eq([{:vios => "vios1", :physvol => "hdisk10"}])
        expect(changes[:vfc]).to eq([{:vios => "vios1", :port => "fcs0", :location => "U78DA.ND0.WZS03EJ-P0-C1-T0"}])
        "new-lpar-uuid"
      end
      allow(ems).to receive(:with_provider_connection).and_yield(conn)
      template.provision_lpar(base_options.merge(:vscsi_storage => "vios1:hdisk10", :vfc_storage => "vios1:fcs0"))
    end

    it "uses the location code given in vfc_storage without a lookup" do
      conn = double("connection")
      expect(conn).to receive(:template_provision) do |_tmpl, _host, changes|
        expect(changes[:vfc]).to eq([{:vios => "vios1", :port => "fcs0", :location => "U78-X"}])
        "new-lpar-uuid"
      end
      allow(ems).to receive(:with_provider_connection).and_yield(conn)
      template.provision_lpar(base_options.merge(:vfc_storage => "vios1:fcs0:U78-X"))
    end

    it "raises when the FC port location cannot be resolved" do
      allow(ems).to receive(:with_provider_connection).and_yield(double("connection"))
      expect { template.provision_lpar(base_options.merge(:vfc_storage => "vios1:fcs9")) }
        .to raise_error(MiqException::MiqProvisionError, /fcs9/)
    end
  end
end
