require 'spec_helper'

describe ObjectController do
  it "should redirect you to root if no object is found" do
    get :show, id: 'avalon:bad-pid'
    expect(response).to redirect_to root_path
  end

  it "should redirect you to the object show page" do
    obj = FactoryGirl.create(:media_object)
    get :show, id: obj.pid
    expect(response).to redirect_to(media_object_path(obj)) 
  end

  it "should pass along request params" do
    obj = FactoryGirl.create(:media_object)
    get :show, id: obj.pid, foo: 'bar'
    expect(response).to redirect_to(media_object_path(obj, {foo: 'bar'}))
  end
end
