# Copyright 2011-2015, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
# 
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed 
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the 
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

require 'spec_helper'
require 'avalon/bib_retriever'

describe Avalon::BibRetriever do
  let(:bib_id) { '7763100' }
  let(:mods) { File.read(File.expand_path("../../../fixtures/#{bib_id}.mods",__FILE__)) }
  before(:each) do
    allow(Avalon::Configuration).to receive(:lookup).and_call_original
    allow(Avalon::Configuration).to receive(:lookup).with('bib_retriever')
      .and_return({ 'protocol' => 'sru',
                    'url' => 'http://zgate.example.edu:9000/db' })
  end

  describe 'configured?' do
    it 'valid' do
      expect(Avalon::BibRetriever).to be_configured
    end
    
    it 'invalid' do
      allow(Avalon::Configuration).to receive(:lookup).with('bib_retriever')
        .and_return({ 'protocol' => 'unknown',
                      'url' => 'http://zgate.example.edu:9000/db' })
      expect(Avalon::BibRetriever).not_to be_configured
    end
    
    it 'missing' do
      allow(Avalon::Configuration).to receive(:lookup).with('bib_retriever')
        .and_return(nil)
      expect(Avalon::BibRetriever).not_to be_configured
    end
  end
  
  describe 'sru' do
    let(:sru_url) { "http://zgate.example.edu:9000/db?version=1.1&operation=searchRetrieve&maximumRecords=1&recordSchema=marcxml&query=rec.id=%5E%25#{bib_id}" }
    
    describe 'default namespace' do
      let(:sru_response) { File.read(File.expand_path("../../../fixtures/#{bib_id}.xml",__FILE__)) }

      before :each do
        FakeWeb.register_uri :get, sru_url, body: sru_response
      end
      
      after :each do
        FakeWeb.clean_registry
      end
      
      it 'retrieves proper MODS' do
        response = Avalon::BibRetriever.instance.get_record("^%#{bib_id}")
        expect(Nokogiri::XML(response)).to be_equivalent_to(mods)
      end
    end
    
    describe 'alternate namespace' do
      let(:sru_response) { File.read(File.expand_path("../../../fixtures/#{bib_id}-ns.xml",__FILE__)) }

      before :each do
        allow(Avalon::Configuration).to receive(:lookup).with('bib_retriever')
          .and_return({ 'protocol' => 'sru',
                        'url' => 'http://zgate.example.edu:9000/db',
                        'namespace' => 'http://example.edu/fake/sru/namespace/' })
        FakeWeb.register_uri :get, sru_url, body: sru_response
      end
      
      after :each do
        FakeWeb.clean_registry
      end
      
      it 'retrieves proper MODS' do
        response = Avalon::BibRetriever.instance.get_record("^%#{bib_id}")
        expect(Nokogiri::XML(response)).to be_equivalent_to(mods)
      end
    end
  end
  
  describe 'zoom' do
    it 'retrieves proper MODS' do
      skip "need a reasonable way to mock ruby-zoom"
    end
  end
end
