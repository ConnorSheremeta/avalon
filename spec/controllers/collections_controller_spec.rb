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

describe Admin::CollectionsController, type: :controller do
  render_views

  describe 'security' do
    let(:collection) { FactoryGirl.create(:collection) }
    describe 'ingest api' do
      it "all routes should return 401 when no token is present" do
        expect(get :index, format: 'json').to have_http_status(401)
        expect(get :show, id: collection.id, format: 'json').to have_http_status(401)
        expect(get :items, id: collection.id, format: 'json').to have_http_status(401)
        expect(post :create, format: 'json').to have_http_status(401)
        expect(put :update, id: collection.id, format: 'json').to have_http_status(401)
      end
      it "all routes should return 403 when a bad token in present" do
        request.headers['Avalon-Api-Key'] = 'badtoken'
        expect(get :index, format: 'json').to have_http_status(403)
        expect(get :show, id: collection.id, format: 'json').to have_http_status(403)
        expect(get :items, id: collection.id, format: 'json').to have_http_status(403)
        expect(post :create, format: 'json').to have_http_status(403)
        expect(put :update, id: collection.id, format: 'json').to have_http_status(403)
      end
    end
    describe 'normal auth' do
      context 'with end-user' do
        before do
          login_as :user
        end
        #New is isolated here due to issues caused by the controller instance not being regenerated
        it "should redirect to /" do
          expect(get :new).to redirect_to(root_path)
        end
        it "all routes should redirect to /" do
          expect(get :index).to redirect_to(root_path)
          expect(get :show, id: collection.id).to redirect_to(root_path)
          expect(get :edit, id: collection.id).to redirect_to(root_path)
          expect(get :remove, id: collection.id).to redirect_to(root_path)
          expect(post :create).to redirect_to(root_path)
          expect(put :update, id: collection.id).to redirect_to(root_path)
          expect(patch :update, id: collection.id).to redirect_to(root_path)
          expect(delete :destroy, id: collection.id).to redirect_to(root_path)
        end
      end
    end
  end

  describe "#manage" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do
      request.env["HTTP_REFERER"] = '/'
      login_as(:administrator)
    end

    it "should add users to manager role" do
      manager = FactoryGirl.create(:manager)
      put 'update', id: collection.id, submit_add_manager: 'Add', add_manager: manager.username
      collection.reload
      expect(manager).to be_in(collection.managers)
    end

    it "should not add users to manager role" do
      user = FactoryGirl.create(:user)
      put 'update', id: collection.id, submit_add_manager: 'Add', add_manager: user.username
      collection.reload
      expect(user).not_to be_in(collection.managers)
      expect(flash[:notice]).not_to be_empty
    end

    it "should remove users from manager role" do
      #initial_manager = FactoryGirl.create(:manager).username
      collection.managers += [FactoryGirl.create(:manager).username]
      collection.save!
      manager = User.where(username: collection.managers.first).first
      put 'update', id: collection.id, remove_manager: manager.username
      collection.reload
      expect(manager).not_to be_in(collection.managers)
    end
  end

  describe "#edit" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do
      request.env["HTTP_REFERER"] = '/'
    end

    it "should add users to editor role" do
      login_as(:administrator)
      editor = FactoryGirl.build(:user)
      put 'update', id: collection.id, submit_add_editor: 'Add', add_editor: editor.username
      collection.reload
      expect(editor).to be_in(collection.editors)
    end

    it "should remove users from editor role" do
      login_as(:administrator)
      editor = User.where(username: collection.editors.first).first
      put 'update', id: collection.id, remove_editor: editor.username
      collection.reload
      expect(editor).not_to be_in(collection.editors)
    end
  end

  describe "#deposit" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do
      request.env["HTTP_REFERER"] = '/'
    end

    it "should add users to depositor role" do
      login_as(:administrator)
      depositor = FactoryGirl.build(:user)
      put 'update', id: collection.id, submit_add_depositor: 'Add', add_depositor: depositor.username
      collection.reload
      expect(depositor).to be_in(collection.depositors)
    end

    it "should remove users from depositor role" do
      login_as(:administrator)
      depositor = User.where(username: collection.depositors.first).first
      put 'update', id: collection.id, remove_depositor: depositor.username
      collection.reload
      expect(depositor).not_to be_in(collection.depositors)
    end
  end

  describe "#index" do
    let!(:collection) { FactoryGirl.create(:collection) }
    subject(:json) { JSON.parse(response.body) }

    it "should return list of collections" do
      request.headers['Avalon-Api-Key'] = 'secret_token'
      get 'index', format:'json'
      expect(json.count).to eq(1)
      expect(json.first['id']).to eq(collection.pid)
      expect(json.first['name']).to eq(collection.name)
      expect(json.first['unit']).to eq(collection.unit)
      expect(json.first['description']).to eq(collection.description)
      expect(json.first['object_count']['total']).to eq(collection.media_objects.count)
      expect(json.first['object_count']['published']).to eq(collection.media_objects.reject{|mo| !mo.published?}.count)
      expect(json.first['object_count']['unpublished']).to eq(collection.media_objects.reject{|mo| mo.published?}.count)
      expect(json.first['roles']['managers']).to eq(collection.managers)
      expect(json.first['roles']['editors']).to eq(collection.editors)
      expect(json.first['roles']['depositors']).to eq(collection.depositors)
    end
  end

  describe 'pagination' do
    subject(:json) { JSON.parse(response.body) }
    it 'should paginate index' do
      5.times { FactoryGirl.create(:collection) }
      request.headers['Avalon-Api-Key'] = 'secret_token'
      get 'index', format:'json', per_page: '2'
      expect(json.count).to eq(2)
      expect(response.headers['Per-Page']).to eq('2')
      expect(response.headers['Total']).to eq('5')
    end
    it 'should paginate collection/items' do
      collection = FactoryGirl.create(:collection, items: 5)
      request.headers['Avalon-Api-Key'] = 'secret_token'
      get 'items', id: collection.pid, format: 'json', per_page: '2'
      expect(json.count).to eq(2)
      expect(response.headers['Per-Page']).to eq('2')
      expect(response.headers['Total']).to eq('5')
    end
  end

  describe "#show" do
    let!(:collection) { FactoryGirl.create(:collection) }

    it "should allow access to managers" do
      login_user(collection.managers.first)
      get 'show', id: collection.id
      expect(response).to be_ok
    end

    context "with json format" do
      subject(:json) { JSON.parse(response.body) }

      it "should return json for specific collection" do
        request.headers['Avalon-Api-Key'] = 'secret_token'
        get 'show', id: collection.pid, format:'json'
        expect(json['id']).to eq(collection.pid)
        expect(json['name']).to eq(collection.name)
        expect(json['unit']).to eq(collection.unit)
        expect(json['description']).to eq(collection.description)
        expect(json['object_count']['total']).to eq(collection.media_objects.count)
        expect(json['object_count']['published']).to eq(collection.media_objects.reject{|mo| !mo.published?}.count)
        expect(json['object_count']['unpublished']).to eq(collection.media_objects.reject{|mo| mo.published?}.count)
        expect(json['roles']['managers']).to eq(collection.managers)
        expect(json['roles']['editors']).to eq(collection.editors)
        expect(json['roles']['depositors']).to eq(collection.depositors)
      end

      it "should return 404 if requested collection not present" do
        request.headers['Avalon-Api-Key'] = 'secret_token'
        get 'show', id: 'avalon:doesnt_exist', format: 'json'
        expect(response.status).to eq(404)
        expect(JSON.parse(response.body)["errors"].class).to eq Array
        expect(JSON.parse(response.body)["errors"].first.class).to eq String
      end
    end
  end

  describe "#items" do
    let!(:collection) { FactoryGirl.create(:collection, items: 2) }

    it "should return json for specific collection's media objects" do
      request.headers['Avalon-Api-Key'] = 'secret_token'
      get 'items', id: collection.pid, format: 'json'
      expect(JSON.parse(response.body)).to include(collection.media_objects[0].pid,collection.media_objects[1].pid)
      #TODO add check that mediaobject is serialized to json properly
    end

  end

  describe "#create" do
    let!(:collection) { FactoryGirl.build(:collection) }

    it "should notify administrators" do
      login_as(:administrator) #otherwise, there are no administrators to mail
      mock_delay = double('mock_delay').as_null_object 
      allow(NotificationsMailer).to receive(:delay).and_return(mock_delay)
      expect(mock_delay).to receive(:new_collection)
      request.headers['Avalon-Api-Key'] = 'secret_token'
      post 'create', format:'json', admin_collection: {name: collection.name, description: collection.description, unit: collection.unit, managers: collection.managers}
    end
    it "should create a new collection" do
      request.headers['Avalon-Api-Key'] = 'secret_token'
      post 'create', format:'json', admin_collection: {name: collection.name, description: collection.description, unit: collection.unit, managers: collection.managers}
      expect(JSON.parse(response.body)['id'].class).to eq String
      expect(JSON.parse(response.body)).not_to include('errors')
    end
    it "should return 422 if collection creation failed" do
      request.headers['Avalon-Api-Key'] = 'secret_token'
      post 'create', format:'json', admin_collection: {name: collection.name, description: collection.description, unit: collection.unit}
      expect(response.status).to eq(422)
      expect(JSON.parse(response.body)).to include('errors')
      expect(JSON.parse(response.body)["errors"].class).to eq Array
      expect(JSON.parse(response.body)["errors"].first.class).to eq String
    end

  end

  describe "#update" do
    it "should notify administrators if name changed" do
      login_as(:administrator) #otherwise, there are no administrators to mail
      mock_delay = double('mock_delay').as_null_object 
      allow(NotificationsMailer).to receive(:delay).and_return(mock_delay)
      expect(mock_delay).to receive(:update_collection)
      @collection = FactoryGirl.create(:collection)
      put 'update', id: @collection.pid, admin_collection: {name: "#{@collection.name}-new", description: @collection.description, unit: @collection.unit}
    end

    context "update REST API" do
      let!(:collection) { FactoryGirl.create(:collection)}

      it "should update a collection via API" do
        old_description = collection.description
        request.headers['Avalon-Api-Key'] = 'secret_token'
        put 'update', format: 'json', id: collection.pid, admin_collection: {description: collection.description+'new'}
        expect(JSON.parse(response.body)['id'].class).to eq String
        expect(JSON.parse(response.body)).not_to include('errors')
        collection.reload
        expect(collection.description).to eq old_description+'new'
      end
      it "should return 422 if collection update via API failed" do
        allow_any_instance_of(Admin::Collection).to receive(:save).and_return false
        request.headers['Avalon-Api-Key'] = 'secret_token'
        put 'update', format: 'json', id: collection.pid, admin_collection: {description: collection.description+'new'}
        expect(response.status).to eq(422)
        expect(JSON.parse(response.body)).to include('errors')
        expect(JSON.parse(response.body)["errors"].class).to eq Array
        expect(JSON.parse(response.body)["errors"].first.class).to eq String
      end
    end

    context "access controls" do
      let!(:collection) { FactoryGirl.create(:collection)}

      it "should not allow empty user" do
        expect{ put 'update', id: collection.pid, submit_add_user: "Add", add_user: "", add_user_display: ""}.not_to change{ collection.reload.default_read_users.size }
      end

      it "should not allow empty class" do
        expect{ put 'update', id: collection.pid, submit_add_class: "Add", add_class: "", add_class_display: ""}.not_to change{ collection.reload.default_read_groups.size }
      end

    end
  end

  describe 'batch actions' do
    before(:each) do
      allow(Avalon::Configuration).to receive(:lookup).and_call_original
      allow(Avalon::Configuration).to receive(:lookup)
        .with('dropbox.path').and_return('spec/fixtures/dropbox')
      allow(Avalon::Configuration).to receive(:lookup)
        .with('email.notification').and_return('test_archivist@example.com')
      Dir['spec/fixtures/**/*.xlsx.process*','spec/fixtures/**/*.xlsx.error']
        .each { |file| File.delete(file) }
      User.create(username: 'test_archivist@example.com',
                  email: 'test_archivist@example.com')
      RoleControls.add_user_role('test_archivist@example.com', 'manager')

      @dropbox_dir = collection.dropbox.base_directory
      FileUtils.mkdir_p @dropbox_dir

      request.env["HTTP_REFERER"] = '/'
      login_as(:administrator)

      # Don't ever let a batch ingest job to actually run
      allow(AvalonJobs).to receive(:collection_batch_ingest)
    end

    after :each do
      Dir['spec/fixtures/**/*.xlsx.process*','spec/fixtures/**/*.xlsx.error']
        .each { |file| File.delete(file) }
      RoleControls.remove_user_role('test_archivist@example.com','manager')

      if @dropbox_dir =~ %r{spec/fixtures/dropbox/RSpec} 
        FileUtils.rm_rf @dropbox_dir
      end
    end

    let!(:collection) { FactoryGirl.create(:collection, name: 'RSpec Collection',
                                           managers: ['test_archivist@example.com']) }

    describe '#batch_ingest' do
      it 'launches a batch when a manifest exists' do
        # No *.error, *.processed, or *.processing exists
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx"
        expect(collection.dropbox.manifest_state).to eq(:processable)

        post 'batch_ingest', id: collection.pid

        expect(AvalonJobs).to have_received(:collection_batch_ingest)
        expect(flash[:notice])
          .to eq('Batch ingest for collection "RSpec Collection" initiated ...')
      end

      it 'doesn\'t launch a batch when no manifest exists' do
        expect(File.exists?("#{@dropbox_dir}/manifest.xlsx")).to be_falsey
        expect(collection.dropbox.manifest_state).to eq(:not_found)

        post 'batch_ingest', id: collection.pid

        expect(AvalonJobs).to_not have_received(:collection_batch_ingest)
        expect(flash[:error]).to eq('No manifests found')
      end

      # Batch has had a previous error
      it 'doesn\'t run when an error file exists' do
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx"
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx.error"
        expect(collection.dropbox.manifest_state).to eq(:error)
        post 'batch_ingest', id: collection.pid

        expect(AvalonJobs).to_not have_received(:collection_batch_ingest)
        expect(flash[:error])
          .to eq('Batch already has an error recorded for collection "RSpec Collection". '\
                 'Remove the *.error file from the dropbox to reprocess')
      end

      # Batch is currently running
      it 'doesn\'t run when an processing file exists' do
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx"
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx.processing"
        expect(collection.dropbox.manifest_state).to eq(:processing)

        post 'batch_ingest', id: collection.pid

        expect(AvalonJobs).to_not have_received(:collection_batch_ingest)
        expect(flash[:error])
          .to eq('Batch is currently processing for collection "RSpec Collection"')
      end

      # Batch has already run
      it 'doesn\'t run when a processed file exists' do
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx"
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx.processed"
        expect(collection.dropbox.manifest_state).to eq(:processed)

        post 'batch_ingest', id: collection.pid

        expect(response).to redirect_to(admin_collection_path(collection))
        expect(AvalonJobs).to_not have_received(:collection_batch_ingest)
        expect(flash[:error])
          .to eq('Batch has already been processed for collection "RSpec Collection". '\
                 'Remove the *.processed file from the dropbox to reprocess')
      end
    end

    describe '#batch_log' do
      it 'fails when no log file exists' do
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx"
        expect(File.exists?("#{@dropbox_dir}/manifest.xlsx.log")).to be_falsey

        get 'batch_log', id: collection.pid

        expect(response).to redirect_to(admin_collection_path(collection))
        expect(flash[:error])
          .to eq('Batch ingest log not found for collection "RSpec Collection".')
      end

      it 'shows a log when it exists' do
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx"
        File.write("#{@dropbox_dir}/manifest.xlsx.log", 'A batch log message')

        expect(collection.dropbox.manifest_state).to eq(:processable)

        get 'batch_log', id: collection.pid

        expect(response.status).to eq(200)
        expect(response.body)
          .to include("** #{@dropbox_dir}/manifest.xlsx.log (processable) **\nA batch log message\n\n")
      end

      it 'concatenates two logs' do
        FileUtils.touch "#{@dropbox_dir}/manifest.xlsx"
        File.write("#{@dropbox_dir}/manifest.xlsx.log", 'A batch log message')

        FileUtils.touch "#{@dropbox_dir}/manifest.csv"
        File.write("#{@dropbox_dir}/manifest.csv.log", 'A second batch log message')

        expect(collection.dropbox.manifest_state).to eq(:processable)

        get 'batch_log', id: collection.pid

        expect(response.status).to eq(200)
        # Order of concatenation shouldn't matter
        log1 = "** #{@dropbox_dir}/manifest.xlsx.log (processable) **\nA batch log message\n\n"
        log2 = "** #{@dropbox_dir}/manifest.csv.log (processable) **\nA second batch log message\n\n"
        expect(response.body).to include(log1)
        expect(response.body).to include(log2)
      end
    end

  end
end
